import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import { Node2D } from '../../runtime/scene/Node2D';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

export const SPIDER_WEB_SERVICE = 'world.spider-web';

/** A web's catch zone in world space (a box centred on the web's root, above it). */
export interface SpiderWebZone {
  readonly x: number;
  readonly y: number;
  readonly halfWidth: number;
  readonly halfHeight: number;
}

export interface SpiderWebPort {
  playerPosition(): Readonly<{ x: number; y: number }> | undefined;
  /** True while the slime is in a form that crosses webs (Sticky). */
  playerCrossesWebs(): boolean;
  /** Catch the slime: stick it for a moment and set it back outside the web. */
  catchPlayer(zone: SpiderWebZone): void;
}

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('SpiderWebScript requires a registered script identity.');
  return context.scriptId;
}

/**
 * A spider-web barrier (Gulp, roadmap 7.2): a normal slime that walks into it is
 * caught, stuck for a moment and set back on the side it came from. The Sticky
 * form (silk) crosses it freely. The web has no collision body, so only the
 * catch decides who passes.
 */
export class SpiderWebScript extends ScriptNode {
  readonly width: number;
  readonly depth: number;
  private port?: SpiderWebPort;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    this.width = this.numberProperty('width', 200);
    this.depth = this.numberProperty('depth', 48);
    this.set_process(true);
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.port = this.service<SpiderWebPort>(SPIDER_WEB_SERVICE);
  }

  override _exit_tree(): void {
    this.port = undefined;
  }

  override _process(): void {
    const port = this.port;
    const player = port?.playerPosition();
    if (!port || !player) return;
    const zone = this.zone();
    if (!zone) return;
    if (Math.abs(player.x - zone.x) > zone.halfWidth || Math.abs(player.y - zone.y) > zone.halfHeight) return;
    if (port.playerCrossesWebs()) return;
    port.catchPlayer(zone);
    this.getSignal<SpiderWebZone>('caught')?.emit(zone);
  }

  /** The catch box: the web's width, `depth` deep, just above the root (where the strands hang). */
  zone(): SpiderWebZone | undefined {
    const parent = this.get_parent();
    if (!(parent instanceof Node2D)) return undefined;
    const origin = parent.get_global_transform().position;
    return { x: origin.x, y: origin.y - this.depth / 2, halfWidth: this.width / 2, halfHeight: this.depth / 2 };
  }

  private numberProperty(key: string, fallback: number): number {
    const value = this.exportedProperties[key];
    return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : fallback;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): SpiderWebScript {
    return new SpiderWebScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
