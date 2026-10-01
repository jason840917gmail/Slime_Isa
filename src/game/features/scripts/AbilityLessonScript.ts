import { Node2D } from '../../runtime/scene/Node2D';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

export const ABILITY_LESSON_SERVICE = 'world.ability-lesson';

export interface AbilityLessonPort {
  playerPosition(): Readonly<{ x: number; y: number }> | undefined;
  knows(abilityId: string): boolean;
  /** Teaches the abilities (the learned banner and sound follow). */
  learn(abilityIds: readonly string[]): void;
}

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('AbilityLessonScript requires a registered script identity.');
  return context.scriptId;
}

/**
 * Teaches `abilityIds` once the player walks within `radius` (test areas such
 * as the playground's lash yard; the story teaches through quest rewards).
 * Emits `taught` the first time it teaches something new.
 */
export class AbilityLessonScript extends ScriptNode {
  readonly abilityIds: readonly string[];
  readonly radius: number;
  private port?: AbilityLessonPort;
  private done = false;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    const ids = context.properties.abilityIds;
    this.abilityIds = Array.isArray(ids) ? ids.filter((id): id is string => typeof id === 'string' && id.length > 0) : [];
    const radius = context.properties.radius;
    this.radius = typeof radius === 'number' && radius > 0 ? radius : 96;
    this.set_process(true);
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.port = this.service<AbilityLessonPort>(ABILITY_LESSON_SERVICE);
  }

  override _exit_tree(): void {
    this.port = undefined;
  }

  override _process(): void {
    const port = this.port;
    if (this.done || !port || this.abilityIds.length === 0) return;
    const player = port.playerPosition();
    const parent = this.get_parent();
    if (!player || !(parent instanceof Node2D)) return;
    const at = parent.get_global_transform().position;
    if (Math.hypot(player.x - at.x, player.y - at.y) > this.radius) return;
    this.done = true;
    const fresh = this.abilityIds.filter((abilityId) => !port.knows(abilityId));
    if (fresh.length === 0) return;
    port.learn(fresh);
    this.getSignal<{ abilityIds: readonly string[] }>('taught')?.emit({ abilityIds: fresh });
  }
}
