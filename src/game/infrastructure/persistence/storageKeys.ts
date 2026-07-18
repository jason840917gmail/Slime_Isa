const STORAGE_PREFIX = 'slime-isa';

export const STORAGE_KEYS = {
  save: `${STORAGE_PREFIX}:save`,
  legacyQuests: `${STORAGE_PREFIX}:quests`,
  legacyDiscoveredAreas: `${STORAGE_PREFIX}:discovered-areas`,
  legacyDefeatedBosses: `${STORAGE_PREFIX}:defeated-bosses`,
  legacyCompletedDungeons: `${STORAGE_PREFIX}:dungeon-completed`,
  areaTransition: `${STORAGE_PREFIX}:area-transition`,
} as const;
