import { validateQuestCatalog } from './validateQuestCatalog';
import type { QuestDefinition, QuestState } from './types';
import { gatherBuildingMaterials } from './quests/gatherBuildingMaterials';

export const QUEST_DEFINITIONS: readonly QuestDefinition[] = [
  gatherBuildingMaterials,
];

validateQuestCatalog(QUEST_DEFINITIONS);

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
