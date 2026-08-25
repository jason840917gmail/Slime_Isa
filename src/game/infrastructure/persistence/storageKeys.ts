const STORAGE_PREFIX = 'slime-isa';

export const STORAGE_KEYS = {
  saveIndex: `${STORAGE_PREFIX}:save-index:v1`,
  saveRecordPrefix: `${STORAGE_PREFIX}:save:`,
  recovery: `${STORAGE_PREFIX}:recovery`,
  migrationComplete: `${STORAGE_PREFIX}:migration:v1:complete`,
  legacySave: `${STORAGE_PREFIX}:save`,
  save: `${STORAGE_PREFIX}:save`,
  legacyQuests: `${STORAGE_PREFIX}:quests`,
  legacyDiscoveredAreas: `${STORAGE_PREFIX}:discovered-areas`,
  legacyDefeatedBosses: `${STORAGE_PREFIX}:defeated-bosses`,
  legacyCompletedDungeons: `${STORAGE_PREFIX}:dungeon-completed`,
  areaTransition: `${STORAGE_PREFIX}:area-transition`,
} as const;
