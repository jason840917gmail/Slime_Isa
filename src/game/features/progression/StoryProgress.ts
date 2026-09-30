import { gameEvents } from '../../core/EventBus';
import type { StorySaveData } from '../../infrastructure/persistence/SaveSchema';

/**
 * Run-wide narrative facts earned through play: story flags, recipes and
 * abilities the player has learned, and NPCs they have spoken to. Quest rewards
 * write here; quest prerequisites, crafting, abilities and world gates read
 * from here.
 */
export class StoryProgress {
  private flags = new Set<string>();
  private learnedRecipes = new Set<string>();
  private learnedAbilities = new Set<string>();
  private talkedNpcs = new Set<string>();

  load(data: StorySaveData | undefined): void {
    this.flags = new Set(data?.worldFlags ?? []);
    this.learnedRecipes = new Set(data?.learnedRecipeIds ?? []);
    this.learnedAbilities = new Set(data?.learnedAbilityIds ?? []);
    this.talkedNpcs = new Set(data?.talkedNpcIds ?? []);
    gameEvents.emit('story.changed', {});
  }

  serialize(): StorySaveData {
    return {
      worldFlags: [...this.flags],
      learnedRecipeIds: [...this.learnedRecipes],
      learnedAbilityIds: [...this.learnedAbilities],
      talkedNpcIds: [...this.talkedNpcs],
    };
  }

  hasFlag(flagId: string): boolean { return this.flags.has(flagId); }
  knowsRecipe(recipeId: string): boolean { return this.learnedRecipes.has(recipeId); }
  knowsAbility(abilityId: string): boolean { return this.learnedAbilities.has(abilityId); }
  hasTalkedTo(npcId: string): boolean { return this.talkedNpcs.has(npcId); }

  setFlags(flagIds: readonly string[]): void { this.addAll(this.flags, flagIds); }
  learnRecipes(recipeIds: readonly string[]): void { this.addAll(this.learnedRecipes, recipeIds); }

  /** Teaches abilities; each newly learned one is announced with `ability.learned`. */
  learnAbilities(abilityIds: readonly string[]): void {
    const fresh = abilityIds.filter((abilityId) => !this.learnedAbilities.has(abilityId));
    this.addAll(this.learnedAbilities, fresh);
    for (const abilityId of fresh) gameEvents.emit('ability.learned', { abilityId });
  }
  recordTalk(npcId: string): void { this.addAll(this.talkedNpcs, [npcId]); }

  private addAll(target: Set<string>, values: readonly string[]): void {
    const before = target.size;
    for (const value of values) target.add(value);
    if (target.size !== before) gameEvents.emit('story.changed', {});
  }
}

export const storyProgress = new StoryProgress();
