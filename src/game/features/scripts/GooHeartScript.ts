import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { Node } from '../../runtime/scene/Node';
import { Node2D } from '../../runtime/scene/Node2D';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

export const GOO_HEART_SERVICE = 'world.goo-heart';
/** The `object.goo-heart` default; placed hearts must override it. */
export const UNASSIGNED_HEART_ID = 'unassigned';

/** Run-wide Goo Heart bookkeeping; the world composition root owns the effect. */
export interface GooHeartPort {
  isCollected(heartId: string): boolean;
  /** Grants the heart (max HP up) and remembers it for the rest of the run. */
  collect(heartId: string, at: Readonly<{ x: number; y: number }>): void;
  playerPosition(): Readonly<{ x: number; y: number }> | undefined;
}

export interface GooHeartEvent {
  readonly heartId: string;
}

interface BobbingNode extends Node {
  visible: boolean;
  visualOffset: { readonly x: number; readonly y: number };
}

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('GooHeartScript requires a registered script identity.');
  return context.scriptId;
}

/**
 * A Goo Heart hidden in the world: walking over it raises max HP for the rest
 * of the run. `heartId` is unique across every map, so a heart can be taken
 * only once per run; a collected heart stays gone after save and load. The
 * `visual` sprite bobs gently while the heart waits.
 */
export class GooHeartScript extends ScriptNode {
  readonly heartId: string;
  readonly radius: number;
  private readonly bobPx: number;
  private port?: GooHeartPort;
  private taken = false;
  private elapsed = 0;
  private restOffset?: { readonly x: number; readonly y: number };

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    const heartId = context.properties.heartId;
    this.heartId = typeof heartId === 'string' ? heartId : '';
    this.radius = this.numberProperty('radius', 36);
    this.bobPx = this.numberProperty('bobPx', 4);
    this.set_process(true);
  }

  get collected(): boolean {
    return this.taken;
  }

  override _enter_tree(): void {
    super._enter_tree();
    if (!this.heartId || this.heartId === UNASSIGNED_HEART_ID) {
      // The object scene's default; every placed heart overrides it with a unique ID.
      console.warn(`GooHeartScript '${this.runtimeId}' has no heartId; it cannot be collected.`);
      this.taken = true;
      return;
    }
    this.port = this.service<GooHeartPort>(GOO_HEART_SERVICE);
    if (this.port.isCollected(this.heartId)) this.vanish();
  }

  override _exit_tree(): void {
    this.port = undefined;
  }

  override _process(deltaSeconds: number): void {
    if (this.taken || !this.port) return;
    this.elapsed += deltaSeconds;
    this.bob();
    const parent = this.get_parent();
    const origin = parent instanceof Node2D ? parent.get_global_transform().position : undefined;
    const player = this.port.playerPosition();
    if (!origin || !player || Math.hypot(player.x - origin.x, player.y - origin.y) > this.radius) return;
    this.vanish();
    this.port.collect(this.heartId, origin);
    this.getSignal<GooHeartEvent>('collected')?.emit({ heartId: this.heartId });
  }

  private vanish(): void {
    this.taken = true;
    const visual = this.visual();
    if (visual) visual.visible = false;
  }

  private bob(): void {
    const visual = this.visual();
    if (!visual || typeof visual.visualOffset !== 'object') return;
    this.restOffset ??= visual.visualOffset;
    const { x, y } = this.restOffset;
    visual.visualOffset = { x, y: y + Math.round(Math.sin(this.elapsed * 3) * this.bobPx) };
  }

  private visual(): Partial<BobbingNode> | undefined {
    return this.getReference<Node>('visual')?.configuredTarget as Partial<BobbingNode> | undefined;
  }

  private numberProperty(key: string, fallback: number): number {
    const value = this.exportedProperties[key];
    return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : fallback;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): GooHeartScript {
    return new GooHeartScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
