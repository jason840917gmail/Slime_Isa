export type QuestStatus = 'active' | 'completed';

interface QuestObjectiveBase {
  readonly id: string;
  readonly label: string;
  readonly target: number;
}

export type QuestObjectiveDef =
  | (QuestObjectiveBase & {
    readonly kind: 'collect';
    readonly itemIds: readonly string[];
  })
  | (QuestObjectiveBase & {
    readonly kind: 'kill';
  })
  | (QuestObjectiveBase & {
    readonly kind: 'discover-area';
    readonly areaId: string;
  });

export interface QuestDef {
  id: string;
  title: string;
  giver: string;
  area: string;
  description: string;
  objectives: readonly QuestObjectiveDef[];
  rewards: {
    coins?: number;
    xp?: number;
  };
}

export interface QuestState {
  id: string;
  status: QuestStatus;
  progress: Record<string, number>;
  completedAt?: number;
}

export const QUEST_DEFS: readonly QuestDef[] = [
  {
    id: 'first-steps',
    title: 'First Steps Beyond Home',
    giver: 'Village Elder Plop',
    area: 'Level 1',
    description: 'Prove you are ready to explore: gather supplies, defeat nearby threats, and find the forest path.',
    objectives: [
      {
        id: 'snacks',
        kind: 'collect',
        label: 'Collect meadow snacks',
        target: 3,
        itemIds: ['purple-berry-mat'],
      },
      { id: 'enemies', kind: 'kill', label: 'Defeat enemies', target: 3 },
      { id: 'forest', kind: 'discover-area', label: 'Discover Gloop Forest', target: 1, areaId: 'gloop-forest' },
    ],
    rewards: { coins: 75, xp: 80 },
  },
] as const;

export function getQuestDef(questId: string): QuestDef | undefined {
  return QUEST_DEFS.find((q) => q.id === questId);
}
