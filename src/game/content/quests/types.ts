export type QuestId = string;

export type QuestStatus =
  | 'locked'
  | 'available'
  | 'active'
  | 'completed'
  | 'failed'
  | 'abandoned';

export interface QuestRewardItem {
  readonly itemId: string;
  readonly count: number;
}

export interface QuestRewards {
  readonly coins?: number;
  readonly xp?: number;
  readonly items?: readonly QuestRewardItem[];
}

interface QuestObjectiveBase {
  readonly id: string;
  readonly kind: QuestObjectiveKind;
  readonly label: string;
  readonly target: number;
}

export interface CollectObjective extends QuestObjectiveBase {
  readonly kind: 'collect';
  readonly itemIds: readonly string[];
}

export interface KillObjective extends QuestObjectiveBase {
  readonly kind: 'kill';
  readonly enemyKinds?: readonly string[];
  readonly areaIds?: readonly string[];
  readonly enemyTags?: readonly string[];
}

export interface TalkToNpcObjective extends QuestObjectiveBase {
  readonly kind: 'talk-to-npc';
  readonly npcIds: readonly string[];
}

export interface CraftItemObjective extends QuestObjectiveBase {
  readonly kind: 'craft-item';
  readonly itemIds: readonly string[];
  readonly recipeIds?: readonly string[];
}

export interface EscortCharacterObjective extends QuestObjectiveBase {
  readonly kind: 'escort-character';
  readonly escortIds?: readonly string[];
  readonly characterIds?: readonly string[];
  readonly destinationIds?: readonly string[];
}

export interface DefeatBossObjective extends QuestObjectiveBase {
  readonly kind: 'defeat-boss';
  readonly bossIds: readonly string[];
}

export interface ActivateObjectObjective extends QuestObjectiveBase {
  readonly kind: 'activate-object';
  readonly objectIds?: readonly string[];
  readonly instanceIds?: readonly string[];
  readonly areaIds?: readonly string[];
}

export interface SurviveDurationObjective extends QuestObjectiveBase {
  readonly kind: 'survive-duration';
  readonly encounterIds: readonly string[];
  readonly requiredDurationMs: number;
}

export interface DiscoverAreaObjective extends QuestObjectiveBase {
  readonly kind: 'discover-area';
  readonly areaIds: readonly string[];
}

export type QuestObjectiveDefinition =
  | CollectObjective
  | KillObjective
  | TalkToNpcObjective
  | CraftItemObjective
  | EscortCharacterObjective
  | DefeatBossObjective
  | ActivateObjectObjective
  | SurviveDurationObjective
  | DiscoverAreaObjective;

export type QuestObjectiveKind = QuestObjectiveDefinition['kind'];

export type QuestConditionDefinition =
  | {
    readonly kind: 'quest-status';
    readonly questId: QuestId;
    readonly status: QuestStatus;
  }
  | {
    readonly kind: 'area-entered';
    readonly areaIds: readonly string[];
  }
  | {
    readonly kind: 'player-level';
    readonly minimumLevel: number;
  }
  | {
    readonly kind: 'inventory-count';
    readonly itemId: string;
    readonly minimumCount: number;
  }
  | {
    readonly kind: 'world-flag';
    readonly flagId: string;
  }
  | {
    readonly kind: 'npc-talked';
    readonly npcIds: readonly string[];
  };

export type QuestAcquisitionDefinition =
  | { readonly kind: 'npc'; readonly npcIds: readonly string[] }
  | { readonly kind: 'automatic' };

export type QuestCompletionDefinition =
  | { readonly kind: 'automatic' }
  | { readonly kind: 'npc-turn-in'; readonly npcIds: readonly string[] };

export type QuestFailurePolicy =
  | { readonly kind: 'permanent' }
  | { readonly kind: 'retryable'; readonly reset: 'quest' | 'current-stage' };

export type QuestAbandonmentPolicy =
  | { readonly kind: 'forbidden' }
  | { readonly kind: 'retryable'; readonly reset: 'quest' | 'current-stage' };

export interface QuestStageDefinition {
  readonly id: string;
  readonly title: string;
  readonly description: string;
  readonly objectives: readonly QuestObjectiveDefinition[];
}

export interface QuestDefinition {
  readonly id: QuestId;
  readonly definitionVersion: number;
  readonly title: string;
  readonly description: string;
  readonly category: 'mandatory' | 'optional';
  readonly prerequisites: readonly QuestConditionDefinition[];
  readonly acquisition: QuestAcquisitionDefinition;
  readonly stages: readonly QuestStageDefinition[];
  readonly completion: QuestCompletionDefinition;
  readonly failurePolicy: QuestFailurePolicy;
  readonly abandonmentPolicy: QuestAbandonmentPolicy;
  readonly rewards: QuestRewards;
}

export interface QuestState {
  readonly questId: QuestId;
  readonly definitionVersion: number;
  readonly status: QuestStatus;
  readonly activeStageId: string | null;
  readonly progress: Readonly<Record<string, number>>;
  readonly consumedFactIds?: Readonly<Record<string, readonly string[]>>;
  readonly acceptedAt?: number;
  readonly completedAt?: number;
  readonly failedAt?: number;
  readonly failureReason?: string;
  readonly abandonedAt?: number;
  /** Stage to resume when a retryable failure/abandonment returns to play. */
  readonly resumeStageId?: string;
  readonly rewardsGranted: boolean;
}

export interface QuestView extends QuestState {
  readonly definition: QuestDefinition;
  readonly visibleStages: readonly QuestStageDefinition[];
  readonly readyToTurnIn: boolean;
}

export interface QuestOfferView {
  readonly quest: QuestView;
  readonly npcId: string;
}

export type QuestInputEvents = {
  'collectible.collected': {
    readonly mapId: string;
    readonly instanceId: string;
    readonly objectId: string;
    readonly itemId: string;
    readonly quantity: number;
  };
  'enemy.died': {
    readonly enemyId: number;
    readonly areaId: string;
    readonly kind: string;
    readonly tags?: readonly string[];
  };
  'npc.talked': {
    readonly npcId: string;
    readonly conversationId?: string;
  };
  'craft.completed': {
    readonly recipeId: string;
    readonly itemId: string;
    readonly quantity: number;
  };
  'escort.completed': {
    readonly escortId: string;
    readonly characterId: string;
    readonly destinationId?: string;
    readonly runId?: string;
  };
  'boss.defeated': {
    readonly bossId: string;
    readonly factId?: string;
  };
  'object.activated': {
    readonly objectId: string;
    readonly instanceId: string;
    readonly areaId: string;
  };
  'survival.completed': {
    readonly encounterId: string;
    readonly durationMs: number;
    readonly factId?: string;
  };
  'area.enter': {
    readonly areaId: string;
  };
};

export type QuestInputEventName = keyof QuestInputEvents;

export type QuestDomainEvents = {
  'quest.available': { readonly questId: QuestId; readonly source: 'npc' | 'condition' };
  'quest.accepted': { readonly questId: QuestId; readonly source: 'npc' | 'automatic' };
  'quest.progressed': {
    readonly questId: QuestId;
    readonly stageId: string;
    readonly objectiveId: string;
    readonly before: number;
    readonly after: number;
  };
  'quest.stage-completed': { readonly questId: QuestId; readonly stageId: string };
  'quest.completed': { readonly questId: QuestId; readonly title: string; readonly rewards: QuestRewards };
  'quest.failed': { readonly questId: QuestId; readonly reason: string };
  'quest.abandoned': { readonly questId: QuestId };
  'quest.changed': { readonly questId: QuestId };
};
