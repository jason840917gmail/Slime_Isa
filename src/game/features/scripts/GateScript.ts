import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { Node } from '../../runtime/scene/Node';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

export const GATE_LOCK_SERVICE = 'world.gate-lock';

/** Persistent unlock state of world gates, shared with gated world exits. */
export interface GateLockPort {
  isUnlocked(mapId: string, gateId: string): boolean;
}

interface FrameNode extends Node {
  frame: number;
}

interface CollisionToggleNode extends Node {
  collisionEnabled: boolean;
}

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('GateScript requires a registered script identity.');
  return context.scriptId;
}

/**
 * A physical gate that blocks a passage until the player unlocks it with a key
 * item (press interact nearby). Unlocking goes through the same persisted gate
 * record as gated world exits (`mapId` + `gateId`), so an exit behind the gate
 * opens with it. When open, the `visual` sprite shows `openFrame` and the
 * `doors` body stops colliding; the pillars stay solid.
 */
export class GateScript extends ScriptNode {
  readonly mapId: string;
  readonly gateId: string;
  readonly requiredItemId: string;
  readonly consumeOnUnlock: boolean;
  readonly prompt: string;
  readonly lockedPrompt: string;
  readonly lockedMessage: string;
  readonly unlockedMessage: string;
  /** World-space distance from the gate origin within which it can be used. */
  readonly interactRadius: number;
  /** How far above the gate origin the interaction key badge floats. */
  readonly badgeRise: number;
  private readonly closedFrame: number;
  private readonly openFrame: number;
  private lock?: GateLockPort;
  private opened = false;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    this.mapId = this.stringProperty('mapId', '');
    this.gateId = this.stringProperty('gateId', '');
    this.requiredItemId = this.stringProperty('requiredItemId', '');
    this.consumeOnUnlock = context.properties.consumeOnUnlock !== false;
    this.prompt = this.stringProperty('prompt', 'Unlock gate');
    this.lockedPrompt = this.stringProperty('lockedPrompt', 'Locked');
    this.lockedMessage = this.stringProperty('lockedMessage', 'The gate is locked.');
    this.unlockedMessage = this.stringProperty('unlockedMessage', 'The gate unlocks!');
    this.interactRadius = this.numberProperty('interactRadius', 150);
    this.badgeRise = this.numberProperty('badgeRise', 120);
    this.closedFrame = this.numberProperty('closedFrame', 0);
    this.openFrame = this.numberProperty('openFrame', 1);
    // Scene connections (a pressure plate's `pressed`) can swing the gate open.
    this.registerSignalHandler('open', () => this.open());
  }

  get isOpen(): boolean {
    return this.opened;
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.lock = this.service<GateLockPort>(GATE_LOCK_SERVICE);
    this.apply(this.lock.isUnlocked(this.mapId, this.gateId));
  }

  override _ready(): void {
    // Siblings are ready by now; re-apply in case they entered after the script.
    this.apply(this.opened);
  }

  override _exit_tree(): void {
    this.lock = undefined;
  }

  /** Swings the gate open after a successful unlock. */
  open(): void {
    if (this.opened) return;
    this.apply(true);
    this.getSignal<{ gateId: string }>('opened')?.emit({ gateId: this.gateId });
  }

  private apply(open: boolean): void {
    this.opened = open;
    const visual = this.getReference<Node>('visual')?.configuredTarget as Partial<FrameNode> | undefined;
    if (visual && typeof visual.frame === 'number') visual.frame = open ? this.openFrame : this.closedFrame;
    const doors = this.getReference<Node>('doors')?.configuredTarget as Partial<CollisionToggleNode> | undefined;
    if (doors && typeof doors.collisionEnabled === 'boolean') doors.collisionEnabled = !open;
  }

  private stringProperty(key: string, fallback: string): string {
    const value = this.exportedProperties[key];
    return typeof value === 'string' ? value : fallback;
  }

  private numberProperty(key: string, fallback: number): number {
    const value = this.exportedProperties[key];
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): GateScript {
    return new GateScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
