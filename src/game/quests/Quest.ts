import { getQuestDefinition, getQuestDefinitions } from '../content/quests/QuestCatalog';

/** @deprecated Use QuestObjectiveDefinition from content/quests/types. */
interface QuestObjectiveBase {
  readonly id: string;
  readonly label: string;
  readonly target: number;
}

/** @deprecated Use the content quest catalog and QuestService. */
export type QuestObjectiveDef =
  | (QuestObjectiveBase & {
    readonly kind: 'collect';
    readonly itemIds: readonly string[];
  })
  | (QuestObjectiveBase & { readonly kind: 'kill' })
  | (QuestObjectiveBase & {
    readonly kind: 'discover-area';
    readonly areaId: string;
  });

/** @deprecated Compatibility view for existing tooling/tests. */
export interface QuestDef {
  id: string;
  title: string;
  giver: string;
  area: string;
  description: string;
  objectives: readonly QuestObjectiveDef[];
  rewards: { coins?: number; xp?: number };
}

/** @deprecated The runtime state is now content/quests/types QuestState. */
export interface QuestState {
  id: string;
  status: 'active' | 'completed';
  progress: Record<string, number>;
  completedAt?: number;
}

function legacyDefinition(questId: string): QuestDef | undefined {
  const definition = getQuestDefinition(questId);
  if (!definition) return undefined;
  const objectives: QuestObjectiveDef[] = definition.stages.flatMap((stage) => stage.objectives.map((objective) => {
    if (objective.kind === 'collect') return {
      id: objective.id,
      kind: 'collect' as const,
      label: objective.label,
      target: objective.target,
      itemIds: objective.itemIds,
    };
    if (objective.kind === 'discover-area') return {
      id: objective.id,
      kind: 'discover-area' as const,
      label: objective.label,
      target: objective.target,
      areaId: objective.areaIds[0],
    };
    return { id: objective.id, kind: 'kill' as const, label: objective.label, target: objective.target };
  }));
  return {
    id: definition.id,
    title: definition.title,
    giver: definition.completion.kind === 'npc-turn-in' ? definition.completion.npcIds[0] : '',
    area: '',
    description: definition.description,
    objectives,
    rewards: { coins: definition.rewards.coins, xp: definition.rewards.xp },
  };
}

export const QUEST_DEFS: readonly QuestDef[] = getQuestDefinitions().flatMap((quest) => {
  const definition = legacyDefinition(quest.id);
  return definition ? [definition] : [];
});

export function getQuestDef(questId: string): QuestDef | undefined {
  return legacyDefinition(questId);
}
