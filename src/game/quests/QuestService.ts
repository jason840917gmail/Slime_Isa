import { gameEvents } from '../core/EventBus';
import { gameState } from '../core/GameState';
import { playerInventory } from '../systems/Inventory';
import { getQuestDefinitions } from '../content/quests/QuestCatalog';
import { validateQuestState } from '../content/quests/validateQuestCatalog';
import type {
  QuestConditionDefinition,
  QuestDefinition,
  QuestDomainEvents,
  QuestId,
  QuestInputEventName,
  QuestInputEvents,
  QuestRewards,
  QuestState,
  QuestStatus,
  QuestView,
  QuestOfferView,
} from '../content/quests/types';
import { matchObjective, type ObjectiveMatchContext } from './matchers/ObjectiveMatchers';
import { questReconciliationRegistry } from '../infrastructure/persistence/quests/QuestReconciliationRegistry';

export interface QuestClock {
  now(): number;
}

export interface QuestRewardPort {
  grant(questId: QuestId, rewards: QuestRewards): void;
}

export interface QuestConditionQueries {
  playerLevel(): number;
  inventoryCount(itemId: string): number;
  hasDiscoveredArea(areaId: string): boolean;
  hasWorldFlag(flagId: string): boolean;
  hasTalkedToNpc(npcId: string): boolean;
}

export interface QuestEventPort {
  emit<K extends keyof QuestDomainEvents>(event: K, payload: QuestDomainEvents[K]): void;
}

export interface QuestServiceDependencies {
  readonly catalog?: readonly QuestDefinition[];
  readonly clock?: QuestClock;
  readonly rewards?: QuestRewardPort;
  readonly conditions?: QuestConditionQueries;
  readonly events?: QuestEventPort;
}

export type QuestCommandCode =
  | 'unknown-quest'
  | 'invalid-status'
  | 'wrong-npc'
  | 'not-ready'
  | 'mandatory-quest'
  | 'retry-not-allowed'
  | 'invalid-state';

export type QuestCommandResult =
  | { readonly ok: true; readonly state: QuestState }
  | { readonly ok: false; readonly code: QuestCommandCode; readonly reason: string };

export class QuestLoadError extends Error {
  constructor(public readonly issues: readonly string[]) {
    super(`Quest state could not be loaded:\n  - ${issues.join('\n  - ')}`);
    this.name = 'QuestLoadError';
  }
}

const defaultClock: QuestClock = { now: () => Date.now() };
const defaultConditions: QuestConditionQueries = {
  playerLevel: () => gameState.level,
  inventoryCount: (itemId) => playerInventory.count(itemId),
  hasDiscoveredArea: () => false,
  hasWorldFlag: () => false,
  hasTalkedToNpc: () => false,
};
const defaultRewards: QuestRewardPort = {
  grant: (_questId, rewards) => {
    const additions = (rewards.items ?? []).map((reward) => ({ itemId: reward.itemId, count: reward.count }));
    if (additions.length > 0 && !playerInventory.transact([], additions)) {
      throw new Error(`Could not grant all reward items for quest '${_questId}'.`);
    }
    if (rewards.coins) gameState.addCoins(rewards.coins);
    if (rewards.xp) gameState.addXp(rewards.xp);
  },
};
const defaultEvents: QuestEventPort = {
  emit: (event, payload) => gameEvents.emit(event as never, payload as never),
};

interface MutableQuestState {
  questId: QuestId;
  definitionVersion: number;
  status: QuestStatus;
  activeStageId: string | null;
  progress: Record<string, number>;
  consumedFactIds: Record<string, readonly string[]>;
  acceptedAt?: number;
  completedAt?: number;
  failedAt?: number;
  failureReason?: string;
  abandonedAt?: number;
  resumeStageId?: string;
  rewardsGranted: boolean;
}

function cloneState(state: QuestState): QuestState {
  return {
    ...state,
    progress: { ...state.progress },
    ...(state.consumedFactIds
      ? { consumedFactIds: Object.fromEntries(Object.entries(state.consumedFactIds).map(([id, facts]) => [id, [...facts]])) }
      : {}),
  };
}

function cloneMutableState(state: MutableQuestState): MutableQuestState {
  return {
    ...(cloneState(state as QuestState) as MutableQuestState),
    consumedFactIds: Object.fromEntries(Object.entries(state.consumedFactIds ?? {})
      .map(([objectiveId, facts]) => [objectiveId, [...facts]])),
  };
}

function firstStage(definition: QuestDefinition): QuestDefinition['stages'][number] {
  return definition.stages[0];
}

function stageById(definition: QuestDefinition, stageId: string | null): QuestDefinition['stages'][number] | undefined {
  return definition.stages.find((stage) => stage.id === stageId);
}

function initializeProgress(state: MutableQuestState, stage: QuestDefinition['stages'][number]): void {
  for (const objective of stage.objectives) {
    if (state.progress[objective.id] === undefined) state.progress[objective.id] = 0;
  }
}

function clearProgress(state: MutableQuestState, definition: QuestDefinition): void {
  state.progress = {};
  state.consumedFactIds = {};
  initializeProgress(state, firstStage(definition));
  state.activeStageId = firstStage(definition).id;
}

export class QuestService {
  private readonly definitions: readonly QuestDefinition[];
  private readonly definitionById: ReadonlyMap<string, QuestDefinition>;
  private readonly clock: QuestClock;
  private readonly rewards: QuestRewardPort;
  private readonly conditions: QuestConditionQueries;
  private readonly events: QuestEventPort;
  private states = new Map<QuestId, MutableQuestState>();
  private readonly talkedNpcIds = new Set<string>();
  private readonly discoveredAreaIds = new Set<string>();
  private readonly worldFlagIds = new Set<string>();

  constructor(dependencies: QuestServiceDependencies = {}) {
    this.definitions = dependencies.catalog ?? getQuestDefinitions();
    this.definitionById = new Map(this.definitions.map((definition) => [definition.id, definition]));
    this.clock = dependencies.clock ?? defaultClock;
    this.rewards = dependencies.rewards ?? defaultRewards;
    this.conditions = dependencies.conditions ?? defaultConditions;
    this.events = dependencies.events ?? defaultEvents;
  }

  start(): void {
    if (this.states.size === 0) {
      for (const definition of this.definitions) {
        this.states.set(definition.id, this.createLockedState(definition));
      }
    }
    this.evaluatePrerequisites();
  }

  /** Restores persisted world facts used by prerequisite conditions. */
  restoreKnownFacts(facts: { readonly discoveredAreas?: readonly string[]; readonly defeatedBossIds?: readonly string[]; readonly talkedNpcIds?: readonly string[]; readonly worldFlags?: readonly string[] }): void {
    this.discoveredAreaIds.clear();
    this.worldFlagIds.clear();
    this.talkedNpcIds.clear();
    for (const areaId of facts.discoveredAreas ?? []) this.discoveredAreaIds.add(areaId);
    for (const bossId of facts.defeatedBossIds ?? []) this.worldFlagIds.add(`boss:${bossId}`);
    for (const npcId of facts.talkedNpcIds ?? []) this.talkedNpcIds.add(npcId);
    for (const flagId of facts.worldFlags ?? []) this.worldFlagIds.add(flagId);
  }

  load(states: readonly QuestState[]): void {
    const next = new Map<QuestId, MutableQuestState>();
    const issues: string[] = [];
    for (const state of states) {
      const definition = this.definitionById.get(state.questId);
      if (!definition) {
        issues.push(`quest '${state.questId}': unknown quest ID`);
        continue;
      }
      let reconciled: QuestState;
      try {
        reconciled = questReconciliationRegistry.reconcile(state, definition);
      } catch (error) {
        issues.push(`quest '${state.questId}': ${error instanceof Error ? error.message : String(error)}`);
        continue;
      }
      const stateIssues = validateQuestState(reconciled, definition);
      if (stateIssues.length > 0) {
        issues.push(...stateIssues.map((issue) => `quest '${state.questId}': ${issue}`));
        continue;
      }
      if (next.has(state.questId)) issues.push(`quest '${state.questId}': duplicate state`);
      next.set(reconciled.questId, cloneMutableState(reconciled as MutableQuestState));
    }
    if (issues.length > 0) throw new QuestLoadError(issues);
    for (const definition of this.definitions) {
      if (!next.has(definition.id)) next.set(definition.id, this.createLockedState(definition));
    }
    this.states = next;
    this.talkedNpcIds.clear();
    this.discoveredAreaIds.clear();
    this.worldFlagIds.clear();
  }

  serialize(): readonly QuestState[] {
    return [...this.states.values()].map((state) => cloneState(state));
  }

  get(questId: QuestId): QuestView | undefined {
    const state = this.states.get(questId);
    const definition = this.definitionById.get(questId);
    if (!state || !definition) return undefined;
    return this.view(state, definition);
  }

  list(status?: QuestStatus): readonly QuestView[] {
    return [...this.states.values()]
      .filter((state) => status === undefined || state.status === status)
      .map((state) => this.view(state, this.definitionById.get(state.questId)!));
  }

  offersForNpc(npcId: string): readonly QuestOfferView[] {
    return this.list('available')
      .filter((quest) => quest.definition.acquisition.kind === 'npc' && quest.definition.acquisition.npcIds.includes(npcId))
      .map((quest) => ({ quest, npcId }));
  }

  reoffersForNpc(npcId: string): readonly QuestOfferView[] {
    return this.list('abandoned')
      .filter((quest) => quest.definition.acquisition.kind === 'npc'
        && quest.definition.acquisition.npcIds.includes(npcId)
        && quest.definition.abandonmentPolicy.kind === 'retryable')
      .map((quest) => ({ quest, npcId }));
  }

  turnInsForNpc(npcId: string): readonly QuestView[] {
    return this.list('active').filter((quest) => (
      quest.readyToTurnIn
      && quest.definition.completion.kind === 'npc-turn-in'
      && quest.definition.completion.npcIds.includes(npcId)
    ));
  }

  isReadyToTurnIn(questId: QuestId): boolean {
    return this.get(questId)?.readyToTurnIn ?? false;
  }

  accept(questId: QuestId, npcId: string): QuestCommandResult {
    const state = this.states.get(questId);
    const definition = this.definitionById.get(questId);
    if (!state || !definition) return this.failure('unknown-quest', `Unknown quest '${questId}'.`);
    if (state.status === 'active') return this.success(state);
    if (state.status !== 'available' || definition.acquisition.kind !== 'npc' || !definition.acquisition.npcIds.includes(npcId)) {
      return this.failure('invalid-status', `Quest '${questId}' is not available from NPC '${npcId}'.`);
    }
    this.activate(state, definition, 'npc');
    return this.success(state);
  }

  decline(questId: QuestId, npcId: string): QuestCommandResult {
    const state = this.states.get(questId);
    const definition = this.definitionById.get(questId);
    if (!state || !definition) return this.failure('unknown-quest', `Unknown quest '${questId}'.`);
    if (state.status !== 'available' || definition.acquisition.kind !== 'npc' || !definition.acquisition.npcIds.includes(npcId)) {
      return this.failure('invalid-status', `Quest '${questId}' is not available from NPC '${npcId}'.`);
    }
    return this.success(state);
  }

  turnIn(questId: QuestId, npcId: string): QuestCommandResult {
    const state = this.states.get(questId);
    const definition = this.definitionById.get(questId);
    if (!state || !definition) return this.failure('unknown-quest', `Unknown quest '${questId}'.`);
    if (state.status !== 'active' || definition.completion.kind !== 'npc-turn-in' || !definition.completion.npcIds.includes(npcId)) {
      return this.failure('wrong-npc', `Quest '${questId}' cannot be turned in to NPC '${npcId}'.`);
    }
    if (!this.isReadyToTurnIn(questId)) return this.failure('not-ready', `Quest '${questId}' is not ready to turn in.`);
    this.complete(state, definition);
    return this.success(state);
  }

  abandon(questId: QuestId): QuestCommandResult {
    const state = this.states.get(questId);
    const definition = this.definitionById.get(questId);
    if (!state || !definition) return this.failure('unknown-quest', `Unknown quest '${questId}'.`);
    if (state.status !== 'active') return this.failure('invalid-status', `Quest '${questId}' is not active.`);
    if (definition.category === 'mandatory' || definition.abandonmentPolicy.kind === 'forbidden') {
      return this.failure('mandatory-quest', `Quest '${questId}' cannot be abandoned.`);
    }
    state.status = 'abandoned';
    state.resumeStageId = state.activeStageId ?? undefined;
    state.activeStageId = null;
    state.abandonedAt = this.clock.now();
    this.events.emit('quest.abandoned', { questId });
    this.changed(state);
    return this.success(state);
  }

  reoffer(questId: QuestId, npcId: string): QuestCommandResult {
    const state = this.states.get(questId);
    const definition = this.definitionById.get(questId);
    if (!state || !definition) return this.failure('unknown-quest', `Unknown quest '${questId}'.`);
    if (state.status !== 'abandoned' || definition.acquisition.kind !== 'npc' || !definition.acquisition.npcIds.includes(npcId)) {
      return this.failure('invalid-status', `Quest '${questId}' cannot be re-offered by NPC '${npcId}'.`);
    }
    if (definition.abandonmentPolicy.kind !== 'retryable') return this.failure('retry-not-allowed', `Quest '${questId}' cannot be retried after abandonment.`);
    this.resetForRetry(state, definition, definition.abandonmentPolicy.reset);
    state.status = 'available';
    state.activeStageId = null;
    this.events.emit('quest.available', { questId, source: 'npc' });
    this.changed(state);
    return this.success(state);
  }

  retryFailed(questId: QuestId): QuestCommandResult {
    const state = this.states.get(questId);
    const definition = this.definitionById.get(questId);
    if (!state || !definition) return this.failure('unknown-quest', `Unknown quest '${questId}'.`);
    if (state.status !== 'failed' || definition.failurePolicy.kind !== 'retryable') return this.failure('retry-not-allowed', `Quest '${questId}' cannot be retried.`);
    this.resetForRetry(state, definition, definition.failurePolicy.reset);
    this.activate(state, definition, definition.acquisition.kind === 'npc' ? 'npc' : 'automatic');
    return this.success(state);
  }

  retryAbandonedAutomatic(questId: QuestId): QuestCommandResult {
    const state = this.states.get(questId);
    const definition = this.definitionById.get(questId);
    if (!state || !definition) return this.failure('unknown-quest', `Unknown quest '${questId}'.`);
    if (state.status !== 'abandoned' || definition.acquisition.kind !== 'automatic') return this.failure('invalid-status', `Quest '${questId}' is not an abandoned automatic quest.`);
    if (definition.abandonmentPolicy.kind !== 'retryable') return this.failure('retry-not-allowed', `Quest '${questId}' cannot be retried after abandonment.`);
    this.resetForRetry(state, definition, definition.abandonmentPolicy.reset);
    state.status = 'locked';
    state.activeStageId = null;
    this.changed(state);
    this.evaluatePrerequisites();
    return this.success(state);
  }

  fail(questId: QuestId, reason: string): QuestCommandResult {
    const state = this.states.get(questId);
    const definition = this.definitionById.get(questId);
    if (!state || !definition) return this.failure('unknown-quest', `Unknown quest '${questId}'.`);
    if (state.status !== 'active') return this.success(state);
    const normalizedReason = reason.trim();
    if (!normalizedReason) return this.failure('invalid-state', `Quest '${questId}' requires a failure reason.`);
    state.status = 'failed';
    state.resumeStageId = state.activeStageId ?? undefined;
    state.activeStageId = null;
    state.failedAt = this.clock.now();
    state.failureReason = normalizedReason;
    this.events.emit('quest.failed', { questId, reason: normalizedReason });
    this.changed(state);
    return this.success(state);
  }

  handleEvent<K extends QuestInputEventName>(event: K, payload: QuestInputEvents[K]): void {
    if (event === 'npc.talked') this.talkedNpcIds.add((payload as QuestInputEvents['npc.talked']).npcId);
    if (event === 'area.enter') this.discoveredAreaIds.add((payload as QuestInputEvents['area.enter']).areaId);
    if (event === 'boss.defeated') {
      const boss = payload as QuestInputEvents['boss.defeated'];
      this.worldFlagIds.add(`boss:${boss.bossId}`);
    }
    this.evaluatePrerequisites();
    const activeStates = [...this.states.values()].filter((state) => state.status === 'active');
    for (const state of activeStates) {
      const definition = this.definitionById.get(state.questId);
      const stage = definition ? stageById(definition, state.activeStageId) : undefined;
      if (!definition || !stage) continue;
      const stageId = stage.id;
      let stageProgressed = false;
      for (const objective of stage.objectives) {
        const context: ObjectiveMatchContext = {
          isFactConsumed: (objectiveId, factId) => state.consumedFactIds?.[objectiveId]?.includes(factId) ?? false,
        };
        const result = matchObjective(objective, event, payload, context);
        if (!result.matched || result.amount <= 0) continue;
        if (result.factId) {
          const consumed = state.consumedFactIds ?? (state.consumedFactIds = {});
          const facts = consumed[objective.id] ?? [];
          if (facts.includes(result.factId)) continue;
          consumed[objective.id] = [...facts, result.factId];
        }
        stageProgressed = this.increment(state, definition, stageId, objective.id, result.amount) || stageProgressed;
      }
      if (stageProgressed) this.tryCompleteStage(state, definition, stageId);
    }
    this.evaluatePrerequisites();
  }

  evaluatePrerequisites(): void {
    for (const definition of this.definitions) {
      const state = this.states.get(definition.id);
      if (!state || state.status !== 'locked' || !this.prerequisitesSatisfied(definition)) continue;
      if (definition.acquisition.kind === 'automatic') this.activate(state, definition, 'automatic');
      else {
        state.status = 'available';
        this.events.emit('quest.available', { questId: definition.id, source: 'condition' });
        this.changed(state);
      }
    }
  }

  private createLockedState(definition: QuestDefinition): MutableQuestState {
    return {
      questId: definition.id,
      definitionVersion: definition.definitionVersion,
      status: 'locked',
      activeStageId: null,
      progress: {},
      consumedFactIds: {},
      rewardsGranted: false,
    };
  }

  private prerequisitesSatisfied(definition: QuestDefinition): boolean {
    return definition.prerequisites.every((condition) => this.conditionSatisfied(condition));
  }

  private conditionSatisfied(condition: QuestConditionDefinition): boolean {
    switch (condition.kind) {
      case 'quest-status':
        return this.states.get(condition.questId)?.status === condition.status;
      case 'area-entered':
        return condition.areaIds.some((areaId) => this.discoveredAreaIds.has(areaId) || this.conditions.hasDiscoveredArea(areaId));
      case 'player-level':
        return this.conditions.playerLevel() >= condition.minimumLevel;
      case 'inventory-count':
        return this.conditions.inventoryCount(condition.itemId) >= condition.minimumCount;
      case 'world-flag':
        return this.worldFlagIds.has(condition.flagId) || this.conditions.hasWorldFlag(condition.flagId);
      case 'npc-talked':
        return condition.npcIds.some((npcId) => this.talkedNpcIds.has(npcId) || this.conditions.hasTalkedToNpc(npcId));
    }
  }

  private activate(state: MutableQuestState, definition: QuestDefinition, source: 'npc' | 'automatic'): void {
    state.status = 'active';
    state.activeStageId = firstStage(definition).id;
    state.acceptedAt = this.clock.now();
    initializeProgress(state, firstStage(definition));
    this.events.emit('quest.accepted', { questId: definition.id, source });
    this.changed(state);
    this.applyKnownFacts(state, definition);
  }

  private applyKnownFacts(state: MutableQuestState, definition: QuestDefinition): void {
    const stage = stageById(definition, state.activeStageId);
    if (!stage) return;
    for (const objective of stage.objectives) {
      const factIds = objective.kind === 'discover-area'
        ? objective.areaIds.filter((areaId) => this.discoveredAreaIds.has(areaId))
        : objective.kind === 'talk-to-npc'
          ? objective.npcIds.filter((npcId) => this.talkedNpcIds.has(npcId))
          : objective.kind === 'defeat-boss'
            ? objective.bossIds.filter((bossId) => this.worldFlagIds.has(`boss:${bossId}`))
            : [];
      for (const factId of factIds) {
        const consumed = state.consumedFactIds[objective.id] ?? [];
        if (consumed.includes(factId)) continue;
        state.consumedFactIds[objective.id] = [...consumed, factId];
        this.increment(state, definition, stage.id, objective.id, 1);
      }
    }
    this.tryCompleteStage(state, definition, stage.id);
  }

  private increment(state: MutableQuestState, definition: QuestDefinition, stageId: string, objectiveId: string, amount: number): boolean {
    const objective = stageById(definition, stageId)?.objectives.find((entry) => entry.id === objectiveId);
    if (!objective) return false;
    const before = state.progress[objectiveId] ?? 0;
    const after = Math.min(objective.target, before + Math.floor(amount));
    if (after <= before) return false;
    state.progress[objectiveId] = after;
    this.events.emit('quest.progressed', { questId: state.questId, stageId, objectiveId, before, after });
    this.changed(state);
    return true;
  }

  private tryCompleteStage(state: MutableQuestState, definition: QuestDefinition, stageId: string): void {
    if (state.status !== 'active' || state.activeStageId !== stageId) return;
    const stage = stageById(definition, stageId);
    if (!stage || !stage.objectives.every((objective) => (state.progress[objective.id] ?? 0) >= objective.target)) return;
    this.events.emit('quest.stage-completed', { questId: state.questId, stageId });
    const index = definition.stages.findIndex((candidate) => candidate.id === stageId);
    if (index < 0 || index === definition.stages.length - 1) {
      if (definition.completion.kind === 'automatic') this.complete(state, definition);
      else this.changed(state);
      return;
    }
    const next = definition.stages[index + 1];
    state.activeStageId = next.id;
    initializeProgress(state, next);
    this.changed(state);
  }

  private complete(state: MutableQuestState, definition: QuestDefinition): void {
    if (state.status === 'completed') return;
    if (!state.rewardsGranted) {
      this.rewards.grant(definition.id, definition.rewards);
      state.rewardsGranted = true;
    }
    state.status = 'completed';
    state.activeStageId = null;
    state.completedAt = this.clock.now();
    this.events.emit('quest.completed', { questId: definition.id, title: definition.title, rewards: definition.rewards });
    this.changed(state);
    // Completion may unlock a derived quest chain immediately; no synthetic
    // sequence entity or extra player action is required.
    this.evaluatePrerequisites();
  }

  private resetForRetry(state: MutableQuestState, definition: QuestDefinition, reset: 'quest' | 'current-stage'): void {
    if (reset === 'quest') clearProgress(state, definition);
    else {
      const stageId = state.resumeStageId
        ?? definition.stages.find((candidate) => candidate.objectives.some((objective) => (state.progress[objective.id] ?? 0) < objective.target))?.id
        ?? firstStage(definition).id;
      const stage = stageById(definition, stageId) ?? firstStage(definition);
      const resetObjectiveIds = new Set(stage.objectives.map((objective) => objective.id));
      state.progress = Object.fromEntries(Object.entries(state.progress).filter(([objectiveId]) => !resetObjectiveIds.has(objectiveId)));
      state.consumedFactIds = Object.fromEntries(Object.entries(state.consumedFactIds).filter(([objectiveId]) => !resetObjectiveIds.has(objectiveId)));
      state.activeStageId = stage.id;
      initializeProgress(state, stage);
    }
    state.failedAt = undefined;
    state.failureReason = undefined;
    state.abandonedAt = undefined;
    state.completedAt = undefined;
    state.rewardsGranted = false;
    state.resumeStageId = undefined;
  }

  private view(state: MutableQuestState, definition: QuestDefinition): QuestView {
    const activeIndex = state.activeStageId === null
      ? state.status === 'completed' ? definition.stages.length - 1
        : state.resumeStageId ? definition.stages.findIndex((stage) => stage.id === state.resumeStageId) : -1
      : definition.stages.findIndex((stage) => stage.id === state.activeStageId);
    const visibleStages = definition.stages.slice(0, Math.max(0, activeIndex + 1));
    const readyToTurnIn = definition.completion.kind === 'npc-turn-in'
      && state.status === 'active'
      && activeIndex === definition.stages.length - 1
      && definition.stages.at(-1)!.objectives.every((objective) => (state.progress[objective.id] ?? 0) >= objective.target);
    return { ...cloneState(state), definition, visibleStages, readyToTurnIn };
  }

  private success(state: MutableQuestState): QuestCommandResult {
    return { ok: true, state: cloneState(state) };
  }

  private failure(code: QuestCommandCode, reason: string): QuestCommandResult {
    return { ok: false, code, reason };
  }

  private changed(state: MutableQuestState): void {
    this.events.emit('quest.changed', { questId: state.questId });
  }
}

export const questService = new QuestService();
