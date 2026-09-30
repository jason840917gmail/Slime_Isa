/**
 * The slime's abilities. The story teaches them (quest and boss rewards, like
 * recipes); there are no levels. Balance and presentation live with the player
 * feature (`features/player/PlayerAbilityDefinitions.ts`).
 */
export type PlayerAbilityId = 'jump' | 'teleport' | 'squash-slam' | 'stretch-lash';

export const PLAYER_ABILITY_IDS: readonly PlayerAbilityId[] = ['jump', 'teleport', 'squash-slam', 'stretch-lash'];

export function isPlayerAbilityId(value: string): value is PlayerAbilityId {
  return (PLAYER_ABILITY_IDS as readonly string[]).includes(value);
}
