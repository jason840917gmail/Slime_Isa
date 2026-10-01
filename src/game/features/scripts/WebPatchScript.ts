import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { Node } from '../../runtime/scene/Node';
import { Node2D } from '../../runtime/scene/Node2D';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';
import { SPIDER_WEB_SERVICE, type SpiderWebPort, type SpiderWebZone } from './SpiderWebScript';

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('WebPatchScript requires a registered script identity.');
  return context.scriptId;
}

interface HideableNode extends Node {
  visible: boolean;
}

/**
 * A web lying on the ground (the Matron's volley, roadmap 8.7): a round patch
 * that catches a normal slime walking onto it, like the spider-web barrier
 * (stuck for a moment and set back outside), while the Sticky form walks
 * through and tears it (quietly: a volley leaves several, so the barrier's
 * "The web tears open!" message is not repeated). Unlike the barrier it is not
 * remembered: the effect that owns it fades after its lifetime.
 */
export class WebPatchScript extends ScriptNode {
  readonly radius: number;
  private port?: SpiderWebPort;
  private tornValue = false;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    const radius = context.properties.radius;
    this.radius = typeof radius === 'number' && Number.isFinite(radius) && radius > 0 ? radius : 48;
    this.set_process(true);
  }

  get torn(): boolean {
    return this.tornValue;
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
    if (!port || !player || this.tornValue) return;
    const zone = this.zone();
    if (!zone || Math.hypot(player.x - zone.x, player.y - zone.y) > this.radius) return;
    if (port.playerCrossesWebs()) {
      this.tornValue = true;
      const visual = this.getReference<Node>('visual')?.configuredTarget as Partial<HideableNode> | undefined;
      if (visual && typeof visual.visible === 'boolean') visual.visible = false;
      this.getSignal<SpiderWebZone>('torn')?.emit(zone);
      return;
    }
    port.catchPlayer(zone);
    this.getSignal<SpiderWebZone>('caught')?.emit(zone);
  }

  /** The catch box around the patch centre (the barrier's catch sets the slime back above or below it). */
  zone(): SpiderWebZone | undefined {
    const parent = this.get_parent();
    if (!(parent instanceof Node2D)) return undefined;
    const origin = parent.get_global_transform().position;
    return { x: origin.x, y: origin.y, halfWidth: this.radius, halfHeight: this.radius };
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): WebPatchScript {
    return new WebPatchScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
