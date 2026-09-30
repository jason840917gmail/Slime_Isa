import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import { Node2D } from '../../runtime/scene/Node2D';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';
import { PLATE_WEIGHT_SERVICE, type PlateWeightPort } from './PressurePlateScript';
import { STORY_FLAG_SERVICE, type StoryFlagPort } from './StoryFlagScript';

export const GROUND_CRACK_SERVICE = 'world.ground-crack';

/** Presentation for the moment the ground gives way (shake, dust, sound, message). */
export interface GroundCrackPort {
  groundCracked(at: Readonly<{ x: number; y: number }>): void;
}

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('CrackedGroundScript requires a registered script identity.');
  return context.scriptId;
}

/**
 * Weak, cracked ground that only something heavy (the Heavy Gulp form) breaks.
 * Standing on it in Heavy form sets its story flag for good; pair it with a
 * `game.story-variant` on the same flag to swap the cracked patch for the hole
 * (and the way down) it hides.
 */
export class CrackedGroundScript extends ScriptNode {
  readonly flagId: string;
  readonly radius: number;
  private weights?: PlateWeightPort;
  private flags?: StoryFlagPort;
  private crackFx?: GroundCrackPort;
  private broken = false;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    const flagId = context.properties.flagId;
    this.flagId = typeof flagId === 'string' ? flagId : '';
    const radius = context.properties.radius;
    this.radius = typeof radius === 'number' && Number.isFinite(radius) && radius > 0 ? radius : 48;
    this.set_process(true);
  }

  get isBroken(): boolean {
    return this.broken;
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.weights = this.service<PlateWeightPort>(PLATE_WEIGHT_SERVICE);
    this.flags = this.service<StoryFlagPort>(STORY_FLAG_SERVICE);
    this.crackFx = this.service<GroundCrackPort>(GROUND_CRACK_SERVICE);
    this.broken = !!this.flagId && this.flags.hasFlag(this.flagId);
  }

  override _exit_tree(): void {
    this.weights = undefined;
    this.flags = undefined;
    this.crackFx = undefined;
  }

  override _process(): void {
    if (this.broken || !this.flagId || !this.weights || !this.flags) return;
    const parent = this.get_parent();
    if (!(parent instanceof Node2D)) return;
    const origin = parent.get_global_transform().position;
    for (const weight of this.weights.weights()) {
      if (Math.hypot(weight.x - origin.x, weight.y - origin.y) > this.radius) continue;
      this.broken = true;
      this.flags.setFlags([this.flagId]);
      this.crackFx?.groundCracked(origin);
      this.getSignal<{ flagId: string }>('cracked')?.emit({ flagId: this.flagId });
      return;
    }
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): CrackedGroundScript {
    return new CrackedGroundScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
