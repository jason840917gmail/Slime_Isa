import { GAME_CONSTANTS } from '../../Constant';
import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { JsonValue } from '../../content/scenes/types';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import type { Node } from '../../runtime/scene/Node';
import type { PhysicsContact } from '../../runtime/scene/physics/PhysicsContact';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

export const WORLD_EXIT_SERVICE = 'world.exit-navigation';

export interface WorldExitRequest {
  readonly mapId: string;
  readonly exitId: string;
  readonly targetAreaId: string;
  readonly entry: string;
  readonly actorNodeId: string;
  readonly gate: JsonValue;
}

export type WorldExitResult =
  | { readonly status: 'ignored' }
  | { readonly status: 'blocked'; readonly message: string }
  | { readonly status: 'queued' };

export interface WorldExitPort {
  requestExit(request: WorldExitRequest): WorldExitResult;
}

interface OverlapObservingArea extends Node {
  readonly currentContacts: readonly PhysicsContact[];
}

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('WorldExitScript requires a registered script identity.');
  return context.scriptId;
}

export class WorldExitScript extends ScriptNode {
  readonly mapId: string;
  readonly exitId: string;
  readonly targetAreaId: string;
  readonly entry: string;
  readonly gate: JsonValue;
  /** Simulation time after mounting during which arrivals standing in the exit are ignored. */
  readonly arrivalGraceMs: number;
  private world?: WorldExitPort;
  private simulationTimeMs = 0;
  private queued = false;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    this.mapId = this.stringProperty('mapId');
    this.exitId = this.stringProperty('exitId');
    this.targetAreaId = this.stringProperty('targetAreaId');
    this.entry = this.stringProperty('entry');
    this.gate = context.properties.gate ?? {};
    const grace = context.properties.arrivalGraceMs;
    this.arrivalGraceMs = typeof grace === 'number' && Number.isFinite(grace) && grace >= 0
      ? grace
      : GAME_CONSTANTS.worldNavigation.edgeTransitionGraceMs;
    this.registerSignalHandler<PhysicsContact>('on_body_entered', (contact) => this.evaluate(contact));
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.world = this.service<WorldExitPort>(WORLD_EXIT_SERVICE);
    this.simulationTimeMs = 0;
    this.queued = false;
    this.set_physics_process(true);
  }

  override _exit_tree(): void {
    this.set_physics_process(false);
    this.world = undefined;
  }

  /**
   * Exits are level-triggered like the legacy overlap zones: every step an
   * actor stays inside re-requests navigation, so unlocking a gate while
   * standing in it, or still standing in an exit after the arrival grace,
   * navigates without leaving and re-entering.
   */
  override _physics_process(deltaSeconds: number): void {
    this.simulationTimeMs += deltaSeconds * 1000;
    if (this.queued || this.simulationTimeMs < this.arrivalGraceMs) return;
    const area = this.getReference<Node>('area')?.configuredTarget as Partial<OverlapObservingArea> | undefined;
    if (!area || !Array.isArray(area.currentContacts)) return;
    for (const contact of area.currentContacts) {
      this.evaluate(contact);
      if (this.queued) return;
    }
  }

  private evaluate(contact: PhysicsContact): void {
    if (contact.otherKind !== 'character-body' || this.queued || this.simulationTimeMs < this.arrivalGraceMs) return;
    const result = this.world?.requestExit({
      mapId: this.mapId,
      exitId: this.exitId,
      targetAreaId: this.targetAreaId,
      entry: this.entry,
      actorNodeId: contact.otherId,
      gate: this.gate,
    }) ?? { status: 'blocked' as const, message: 'Navigation unavailable' };
    if (result.status === 'queued') this.queued = true;
    this.getSignal<WorldExitResult>('navigation_resolved')?.emit(result);
  }

  private stringProperty(key: string): string {
    const value = this.exportedProperties[key];
    return typeof value === 'string' ? value : '';
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): WorldExitScript {
    return new WorldExitScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
