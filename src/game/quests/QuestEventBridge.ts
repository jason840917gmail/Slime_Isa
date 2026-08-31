import { gameEvents } from '../core/EventBus';
import type { QuestInputEvents } from '../content/quests/types';
import type { QuestService } from './QuestService';

export class QuestEventBridge {
  private started = false;

  constructor(private readonly service: QuestService) {}

  start(): void {
    if (this.started) return;
    this.started = true;
    gameEvents.on('collectible.collected', this.onCollectible, this);
    gameEvents.on('enemy.died', this.onEnemyDied, this);
    gameEvents.on('npc.talked', this.onNpcTalked, this);
    gameEvents.on('craft.completed', this.onCraftCompleted, this);
    gameEvents.on('escort.completed', this.onEscortCompleted, this);
    gameEvents.on('boss.defeated', this.onBossDefeated, this);
    gameEvents.on('object.activated', this.onObjectActivated, this);
    gameEvents.on('survival.completed', this.onSurvivalCompleted, this);
    gameEvents.on('area.enter', this.onAreaEnter, this);
  }

  dispose(): void {
    if (!this.started) return;
    this.started = false;
    gameEvents.off('collectible.collected', this.onCollectible, this);
    gameEvents.off('enemy.died', this.onEnemyDied, this);
    gameEvents.off('npc.talked', this.onNpcTalked, this);
    gameEvents.off('craft.completed', this.onCraftCompleted, this);
    gameEvents.off('escort.completed', this.onEscortCompleted, this);
    gameEvents.off('boss.defeated', this.onBossDefeated, this);
    gameEvents.off('object.activated', this.onObjectActivated, this);
    gameEvents.off('survival.completed', this.onSurvivalCompleted, this);
    gameEvents.off('area.enter', this.onAreaEnter, this);
  }

  private onCollectible = (payload: QuestInputEvents['collectible.collected']): void => {
    this.service.handleEvent('collectible.collected', payload);
  };

  private onEnemyDied = (payload: QuestInputEvents['enemy.died']): void => {
    this.service.handleEvent('enemy.died', payload);
  };

  private onNpcTalked = (payload: QuestInputEvents['npc.talked']): void => {
    this.service.handleEvent('npc.talked', payload);
  };

  private onCraftCompleted = (payload: QuestInputEvents['craft.completed']): void => {
    this.service.handleEvent('craft.completed', payload);
  };

  private onEscortCompleted = (payload: QuestInputEvents['escort.completed']): void => {
    this.service.handleEvent('escort.completed', payload);
  };

  private onBossDefeated = (payload: QuestInputEvents['boss.defeated']): void => {
    this.service.handleEvent('boss.defeated', payload);
  };

  private onObjectActivated = (payload: QuestInputEvents['object.activated']): void => {
    this.service.handleEvent('object.activated', payload);
  };

  private onSurvivalCompleted = (payload: QuestInputEvents['survival.completed']): void => {
    this.service.handleEvent('survival.completed', payload);
  };

  private onAreaEnter = (payload: QuestInputEvents['area.enter']): void => {
    this.service.handleEvent('area.enter', payload);
  };
}
