import { getQuestDefinition } from '../content/quests/QuestCatalog';
import type { QuestState as RuntimeQuestState } from '../content/quests/types';
import { QuestEventBridge } from './QuestEventBridge';
import { questService } from './QuestService';
import type { QuestState as LegacyQuestState } from './Quest';

function isRuntimeState(state: RuntimeQuestState | LegacyQuestState): state is RuntimeQuestState {
  return 'questId' in state;
}

function migrateLegacyState(state: LegacyQuestState): RuntimeQuestState {
  const definition = getQuestDefinition(state.id);
  if (!definition) throw new Error(`Unknown legacy quest '${state.id}'.`);
  const objectives = definition.stages.flatMap((stage) => stage.objectives);
  const progress = Object.fromEntries(Object.entries(state.progress)
    .filter(([objectiveId]) => objectives.some((objective) => objective.id === objectiveId))
    .map(([objectiveId, value]) => [objectiveId, Math.min(
      objectives.find((objective) => objective.id === objectiveId)!.target,
      Math.max(0, Math.floor(value)),
    )]));
  const activeStageId = state.status === 'completed'
    ? null
    : definition.stages.find((stage) => stage.objectives.some((objective) => (progress[objective.id] ?? 0) < objective.target))?.id
      ?? definition.stages.at(-1)!.id;
  return {
    questId: state.id,
    definitionVersion: definition.definitionVersion,
    status: state.status,
    activeStageId,
    progress,
    consumedFactIds: {},
    ...(state.completedAt === undefined ? {} : { completedAt: state.completedAt }),
    rewardsGranted: state.status === 'completed',
  };
}

class QuestTrackerImpl {
  private readonly bridge = new QuestEventBridge(questService);

  start(): void {
    questService.start();
    this.bridge.start();
  }

  dispose(): void {
    this.bridge.dispose();
  }

  active(): readonly RuntimeQuestState[] {
    return questService.list('active').map((quest) => this.snapshot(quest));
  }

  completed(): readonly RuntimeQuestState[] {
    return questService.list('completed').map((quest) => this.snapshot(quest));
  }

  byStatus(status: RuntimeQuestState['status']): readonly RuntimeQuestState[] {
    return questService.list(status).map((quest) => this.snapshot(quest));
  }

  all(): readonly RuntimeQuestState[] {
    return questService.serialize();
  }

  progress(questId: string, objectiveId: string): number {
    return questService.get(questId)?.progress[objectiveId] ?? 0;
  }

  serialize(): readonly RuntimeQuestState[] {
    return questService.serialize();
  }

  evaluatePrerequisites(): void {
    questService.evaluatePrerequisites();
  }

  restoreKnownFacts(facts: Parameters<typeof questService.restoreKnownFacts>[0]): void {
    questService.restoreKnownFacts(facts);
  }

  load(states: readonly (RuntimeQuestState | LegacyQuestState)[]): void {
    questService.load(states.map((state) => isRuntimeState(state) ? state : migrateLegacyState(state)));
  }

  private snapshot(quest: ReturnType<typeof questService.get>): RuntimeQuestState {
    if (!quest) throw new Error('Quest snapshot was unexpectedly unavailable.');
    const {
      definition: _definition,
      visibleStages: _visibleStages,
      readyToTurnIn: _readyToTurnIn,
      ...state
    } = quest;
    return state;
  }
}

export const questTracker = new QuestTrackerImpl();
