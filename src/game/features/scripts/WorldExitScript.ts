import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { JsonValue } from '../../content/scenes/types';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
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
  private world?: WorldExitPort;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    this.mapId = this.stringProperty('mapId');
    this.exitId = this.stringProperty('exitId');
    this.targetAreaId = this.stringProperty('targetAreaId');
    this.entry = this.stringProperty('entry');
    this.gate = context.properties.gate ?? {};
    this.registerSignalHandler<PhysicsContact>('on_body_entered', (contact) => this.onBodyEntered(contact));
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.world = this.service<WorldExitPort>(WORLD_EXIT_SERVICE);
  }

  override _exit_tree(): void {
    this.world = undefined;
  }

  private onBodyEntered(contact: PhysicsContact): void {
    if (contact.otherKind !== 'character-body') return;
    const result = this.world?.requestExit({
      mapId: this.mapId,
      exitId: this.exitId,
      targetAreaId: this.targetAreaId,
      entry: this.entry,
      actorNodeId: contact.otherId,
      gate: this.gate,
    }) ?? { status: 'blocked' as const, message: 'Navigation unavailable' };
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
