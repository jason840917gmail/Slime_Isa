import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { Node } from '../../runtime/scene/Node';
import { Node2D } from '../../runtime/scene/Node2D';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';
import { STORY_FLAG_SERVICE, type StoryFlagPort } from './StoryFlagScript';

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
  /** The Sticky slime pushed through and tore the web open for good. */
  webTorn?(zone: SpiderWebZone): void;
}

interface HideableNode extends Node {
  visible: boolean;
}

/** Story flag that keeps a torn web open: `web-torn.<placement persistence key>`. */
export function tornWebFlag(webKey: string): string {
  return `web-torn.${webKey}`;
}

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('SpiderWebScript requires a registered script identity.');
  return context.scriptId;
}

/**
 * A spider-web barrier (Gulp, roadmap 7.2): a normal slime that walks into it is
 * caught, stuck for a moment and set back on the side it came from. The Sticky
 * form (silk) pushes through and tears it open for good (playtest 2026-09-30:
 * a form that wears off on the far side must never trap the slime), unless
 * `tearsWhenCrossed` is off. A torn web is remembered by a story flag named
 * after the web's placement. The web has no collision body, so only the catch
 * decides who passes.
 */
export class SpiderWebScript extends ScriptNode {
  readonly width: number;
  readonly depth: number;
  readonly tearsWhenCrossed: boolean;
  private port?: SpiderWebPort;
  private flags?: StoryFlagPort;
  private tornValue = false;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    this.width = this.numberProperty('width', 200);
    this.depth = this.numberProperty('depth', 48);
    this.tearsWhenCrossed = context.properties.tearsWhenCrossed !== false;
    this.set_process(true);
  }

  /** True once the Sticky slime has torn the web open. */
  get torn(): boolean {
    return this.tornValue;
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.port = this.service<SpiderWebPort>(SPIDER_WEB_SERVICE);
    try { this.flags = this.service<StoryFlagPort>(STORY_FLAG_SERVICE); } catch { this.flags = undefined; }
  }

  override _ready(): void {
    super._ready();
    if (this.flags?.hasFlag(tornWebFlag(this.webKey()))) this.showTorn();
  }

  override _exit_tree(): void {
    this.port = undefined;
    this.flags = undefined;
  }

  override _process(): void {
    const port = this.port;
    const player = port?.playerPosition();
    if (!port || !player || this.tornValue) return;
    const zone = this.zone();
    if (!zone) return;
    if (Math.abs(player.x - zone.x) > zone.halfWidth || Math.abs(player.y - zone.y) > zone.halfHeight) return;
    if (port.playerCrossesWebs()) {
      if (this.tearsWhenCrossed) this.tear(zone);
      return;
    }
    port.catchPlayer(zone);
    this.getSignal<SpiderWebZone>('caught')?.emit(zone);
  }

  private tear(zone: SpiderWebZone): void {
    this.showTorn();
    this.flags?.setFlags([tornWebFlag(this.webKey())]);
    this.port?.webTorn?.(zone);
    this.getSignal<SpiderWebZone>('torn')?.emit(zone);
  }

  private showTorn(): void {
    this.tornValue = true;
    const visual = this.getReference<Node>('visual')?.configuredTarget as Partial<HideableNode> | undefined;
    if (visual && typeof visual.visible === 'boolean') visual.visible = false;
  }

  /** The placement's persistence key (unique per map), or this node's id outside a world. */
  private webKey(): string {
    for (let node: Node | undefined = this; node; node = node.get_parent()) {
      const provenance = node.authoredInstanceProvenance;
      if (provenance) return provenance.persistenceKey ?? provenance.authoredInstanceId;
    }
    return String(this.runtimeId);
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
