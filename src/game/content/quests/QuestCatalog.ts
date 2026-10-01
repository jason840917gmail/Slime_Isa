import { validateQuestCatalog } from './validateQuestCatalog';
import type { QuestDefinition, QuestState } from './types';
import { CHAPTER_ONE_QUESTS } from './quests/chapterOne';
import { CHAPTER_TWO_QUESTS } from './quests/chapterTwo';

export const QUEST_DEFINITIONS: readonly QuestDefinition[] = [
  ...CHAPTER_ONE_QUESTS,
  ...CHAPTER_TWO_QUESTS,
];

validateQuestCatalog(QUEST_DEFINITIONS);

/**
 * Quests removed from the catalog. Saved states for these IDs are dropped on load
 * instead of rejecting the whole save; never reuse one of these IDs.
 */
export const RETIRED_QUEST_IDS: ReadonlySet<string> = new Set<string>([
  // Replaced by Chapter 1 ('a-place-to-work' onward).
  'gather-building-materials',
]);

const QUEST_BY_ID = new Map(QUEST_DEFINITIONS.map((definition) => [definition.id, definition]));

export function getQuestDefinition(questId: string): QuestDefinition | undefined {
  return QUEST_BY_ID.get(questId);
}

export function getQuestDefinitions(): readonly QuestDefinition[] {
  return QUEST_DEFINITIONS;
}

export function createInitialQuestState(definition: QuestDefinition): QuestState {
  return {
    questId: definition.id,
    definitionVersion: definition.definitionVersion,
    status: 'locked',
    activeStageId: null,
    progress: {},
    rewardsGranted: false,
  };
}

export function createInitialQuestStates(): readonly QuestState[] {
  // Initial saves contain neutral states. QuestService.start() performs the
  // lifecycle transition after presentation listeners exist, so automatic
  // starts and NPC availability emit their normal domain events.
  return QUEST_DEFINITIONS.map(createInitialQuestState);
}
