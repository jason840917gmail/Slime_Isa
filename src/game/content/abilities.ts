/**
 * The slime's abilities. The story teaches them (quest and boss rewards, like
 * recipes); there are no levels. Balance and presentation live with the player
 * feature (`features/player/PlayerAbilityDefinitions.ts`).
 */
export type PlayerAbilityId = 'jump' | 'dodge' | 'teleport' | 'squash-slam' | 'stretch-lash';

export const PLAYER_ABILITY_IDS: readonly PlayerAbilityId[] = ['jump', 'dodge', 'teleport', 'squash-slam', 'stretch-lash'];

export function isPlayerAbilityId(value: string): value is PlayerAbilityId {
  return (PLAYER_ABILITY_IDS as readonly string[]).includes(value);
}

/** Passive abilities: always on once learned, with no key and no ability-bar slot. */
export type PassiveAbilityId = 'goo-trail';

export const PASSIVE_ABILITY_IDS: readonly PassiveAbilityId[] = ['goo-trail'];

export function isPassiveAbilityId(value: string): value is PassiveAbilityId {
  return (PASSIVE_ABILITY_IDS as readonly string[]).includes(value);
}

/** Anything a quest reward can teach (`QuestRewards.abilityIds`). */
export function isLearnableAbilityId(value: string): value is PlayerAbilityId | PassiveAbilityId {
  return isPlayerAbilityId(value) || isPassiveAbilityId(value);
}
