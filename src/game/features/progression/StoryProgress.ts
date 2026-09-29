import { gameEvents } from '../../core/EventBus';
import type { StorySaveData } from '../../infrastructure/persistence/SaveSchema';

/**
 * Run-wide narrative facts earned through play: story flags, recipes the player
 * has learned, and NPCs they have spoken to. Quest rewards write here; quest
 * prerequisites, crafting, and world gates read from here.
 */
export class StoryProgress {
  private flags = new Set<string>();
  private learnedRecipes = new Set<string>();
  private talkedNpcs = new Set<string>();

  load(data: StorySaveData | undefined): void {
    this.flags = new Set(data?.worldFlags ?? []);
    this.learnedRecipes = new Set(data?.learnedRecipeIds ?? []);
    this.talkedNpcs = new Set(data?.talkedNpcIds ?? []);
    gameEvents.emit('story.changed', {});
  }

  serialize(): StorySaveData {
    return {
      worldFlags: [...this.flags],
      learnedRecipeIds: [...this.learnedRecipes],
      talkedNpcIds: [...this.talkedNpcs],
    };
  }

  hasFlag(flagId: string): boolean { return this.flags.has(flagId); }
  knowsRecipe(recipeId: string): boolean { return this.learnedRecipes.has(recipeId); }
  hasTalkedTo(npcId: string): boolean { return this.talkedNpcs.has(npcId); }

  setFlags(flagIds: readonly string[]): void { this.addAll(this.flags, flagIds); }
  learnRecipes(recipeIds: readonly string[]): void { this.addAll(this.learnedRecipes, recipeIds); }
  recordTalk(npcId: string): void { this.addAll(this.talkedNpcs, [npcId]); }

  private addAll(target: Set<string>, values: readonly string[]): void {
    const before = target.size;
    for (const value of values) target.add(value);
    if (target.size !== before) gameEvents.emit('story.changed', {});
  }
}

export const storyProgress = new StoryProgress();
