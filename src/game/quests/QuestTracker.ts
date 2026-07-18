import { gameEvents } from '../core/EventBus';
import { gameState } from '../core/GameState';
import { QUEST_DEFS, getQuestDef, type QuestState } from './Quest';
import { saveRepository } from '../infrastructure/persistence/SaveRepository';

class QuestTrackerImpl {
  private states = new Map<string, QuestState>();
  private started = false;

  start(): void {
    if (this.started) return;
    this.started = true;
    const saved = saveRepository.read();
    this.load(saved?.data.quests ?? saveRepository.readLegacyQuests());
    this.ensureStarterQuests();

    gameEvents.on('player.collect', this.onCollect, this);
    gameEvents.on('enemy.died', this.onEnemyDied, this);
    gameEvents.on('area.enter', this.onAreaEnter, this);
  }

  active(): QuestState[] {
    return [...this.states.values()].filter((q) => q.status === 'active');
  }

  completed(): QuestState[] {
    return [...this.states.values()].filter((q) => q.status === 'completed');
  }

  all(): QuestState[] {
    return [...this.active(), ...this.completed()];
  }

  progress(questId: string, objectiveId: string): number {
    return this.states.get(questId)?.progress[objectiveId] ?? 0;
  }

  serialize(): QuestState[] {
    return [...this.states.values()].map((state) => ({
      ...state,
      progress: { ...state.progress },
    }));
  }

  load(states: QuestState[]): void {
    this.states = new Map(states.map((state) => [state.id, {
      ...state,
      progress: { ...state.progress },
    }]));
  }

  private ensureStarterQuests(): void {
    for (const def of QUEST_DEFS) {
      if (!this.states.has(def.id)) {
        const progress = Object.fromEntries(def.objectives.map((o) => [o.id, 0]));
        this.states.set(def.id, { id: def.id, status: 'active', progress });
        gameEvents.emit('quest.changed', { questId: def.id });
      }
    }
  }

  private onCollect = (payload: { kind: 'berry' | 'chip'; value: number }): void => {
    for (const state of this.active()) {
      const def = getQuestDef(state.id);
      if (!def) continue;
      for (const obj of def.objectives) {
        if (obj.kind !== 'collect') continue;
        if (obj.collectKind && obj.collectKind !== payload.kind) continue;
        this.increment(state, obj.id, 1, obj.target);
      }
    }
  };

  private onEnemyDied = (_payload: { enemyId: number; areaId: string; kind: string }): void => {
    for (const state of this.active()) {
      const def = getQuestDef(state.id);
      if (!def) continue;
      for (const obj of def.objectives) {
        if (obj.kind === 'kill') this.increment(state, obj.id, 1, obj.target);
      }
    }
  };

  private onAreaEnter = (payload: { areaId: string }): void => {
    for (const state of this.active()) {
      const def = getQuestDef(state.id);
      if (!def) continue;
      for (const obj of def.objectives) {
        if (obj.kind === 'discover-area' && obj.areaId === payload.areaId) {
          this.increment(state, obj.id, 1, obj.target);
        }
      }
    }
  };

  private increment(state: QuestState, objectiveId: string, amount: number, target: number): void {
    const before = state.progress[objectiveId] ?? 0;
    const after = Math.min(target, before + amount);
    if (after === before) return;
    state.progress[objectiveId] = after;
    this.tryComplete(state);
    gameEvents.emit('quest.changed', { questId: state.id });
  }

  private tryComplete(state: QuestState): void {
    const def = getQuestDef(state.id);
    if (!def || state.status === 'completed') return;
    const complete = def.objectives.every((obj) => (state.progress[obj.id] ?? 0) >= obj.target);
    if (!complete) return;

    state.status = 'completed';
    state.completedAt = Date.now();
    if (def.rewards.coins) gameState.addCoins(def.rewards.coins);
    if (def.rewards.xp) gameState.addXp(def.rewards.xp);
    gameEvents.emit('quest.completed', { questId: def.id, title: def.title, rewards: def.rewards });
  }

}

export const questTracker = new QuestTrackerImpl();
