import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import { Node2D } from '../../runtime/scene/Node2D';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';
import { PLATE_WEIGHT_SERVICE, type PlateWeightPort } from './PressurePlateScript';
import { STORY_FLAG_SERVICE, type StoryFlagPort } from './StoryFlagScript';

export const GROUND_CRACK_SERVICE = 'world.ground-crack';

/** A Heavy slime's jump landing; `id` grows with every landing so each one counts once. */
export interface HeavyLanding {
  readonly x: number;
  readonly y: number;
  readonly id: number;
}

/** The world side of weak ground: Heavy landings in, presentation out. */
export interface GroundCrackPort {
  /** The moment the ground gives way (shake, dust, sound, message). */
  groundCracked(at: Readonly<{ x: number; y: number }>): void;
  /** Where the Heavy slime last landed a jump, if it ever has. */
  lastHeavyLanding?(): HeavyLanding | undefined;
  /** The Heavy slime stands on it without jumping: a hint that it creaks. */
  groundCreaks?(at: Readonly<{ x: number; y: number }>): void;
}

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('CrackedGroundScript requires a registered script identity.');
  return context.scriptId;
}

/**
 * Weak, cracked ground that only something heavy breaks: the Heavy Gulp form
 * has to land a jump on it (playtest 2026-09-30; with `requiresLanding` off,
 * standing on it is enough). Standing on it in Heavy form only makes it creak.
 * Breaking sets its story flag for good; pair it with a `game.story-variant` on
 * the same flag to swap the cracked patch for the hole (and the way down) it
 * hides.
 */
export class CrackedGroundScript extends ScriptNode {
  readonly flagId: string;
  readonly radius: number;
  readonly requiresLanding: boolean;
  private weights?: PlateWeightPort;
  /** The last landing already judged, so an old one never breaks newly loaded ground. */
  private seenLanding?: number;
  private flags?: StoryFlagPort;
  private crackFx?: GroundCrackPort;
  private broken = false;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    const flagId = context.properties.flagId;
    this.flagId = typeof flagId === 'string' ? flagId : '';
    const radius = context.properties.radius;
    this.radius = typeof radius === 'number' && Number.isFinite(radius) && radius > 0 ? radius : 48;
    this.requiresLanding = context.properties.requiresLanding !== false;
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
    this.seenLanding = this.crackFx.lastHeavyLanding?.()?.id;
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
    const within = (point: Readonly<{ x: number; y: number }>) => Math.hypot(point.x - origin.x, point.y - origin.y) <= this.radius;
    if (this.requiresLanding) {
      const landing = this.crackFx?.lastHeavyLanding?.();
      if (landing && landing.id !== this.seenLanding) {
        this.seenLanding = landing.id;
        if (within(landing)) { this.crack(origin); return; }
      }
      for (const weight of this.weights.weights()) if (within(weight)) { this.crackFx?.groundCreaks?.(origin); break; }
      return;
    }
    for (const weight of this.weights.weights()) if (within(weight)) { this.crack(origin); return; }
  }

  private crack(origin: Readonly<{ x: number; y: number }>): void {
    this.broken = true;
    this.flags?.setFlags([this.flagId]);
    this.crackFx?.groundCracked(origin);
    this.getSignal<{ flagId: string }>('cracked')?.emit({ flagId: this.flagId });
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
