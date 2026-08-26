import Phaser from 'phaser';
import type { PerkChoice, StatusKind } from './types';

/**
 * Central typed event bus. Singleton so any system can emit/subscribe without
 * holding scene references. Wraps a Phaser.Events.EventEmitter.
 *
 * Keep the event map exhaustive so callers get autocompletion + compile-time
 * safety on payloads.
 */

export type GameEvents = {
  'coins.changed': { coins: number; delta: number };
  'boost.changed': { boostBonus: number; delta: number };
  'friend.count': { count: number };
  'player.collect': { kind: 'berry' | 'chip'; value: number };
  'collectible.collected': { mapId: string; instanceId: string; objectId: string; itemId: string; quantity: number };
  'player.action': { anim: string };
  'house.enter': { houseId: number };
  'house.leave': {};
  'house.sleep': { coinsGained: number };
  'area.enter': { areaId: string };
  'enemy.died': { enemyId: number; areaId: string; kind: string };
  'save.done': { slot: string };
  'save.loaded': { slot: string };
  'persistence.modal': { open: boolean };
  'world.progress.changed': {};

  // ── Phase 5: quests / journal ──
  'quest.changed': { questId: string };
  'quest.completed': { questId: string; title: string; rewards: { coins?: number; xp?: number } };

  // ── Phase 1: health / leveling / inventory ──
  'hp.changed': { hp: number; maxHp: number; delta: number };
  'player.damage': { amount: number; source?: string; crit: boolean };
  'player.heal': { amount: number };
  'player.death': {};
  'player.respawn': {};
  'xp.changed': { xp: number; xpIntoLevel: number; xpForNext: number; level: number; delta: number };
  'level.up': { level: number; skillPoints: number };
  'energy.changed': { energy: number; maxEnergy: number; delta: number };
  'skillpoint.changed': { points: number };
  'perk.taken': { perkId: string };
  'status.added': { kind: StatusKind; stacks: number };
  'status.removed': { kind: StatusKind };
  'inventory.changed': {};
  'weapon.loadout.changed': { slots: readonly (string | null)[] };
  'weapon.equipped': { weaponId: string | null };
  'levelup.modal.open': { choices: PerkChoice[] };
  'levelup.modal.close': { pickedPerkId: string | null };
};

type Handler<T extends keyof GameEvents> = (payload: GameEvents[T]) => void;

class EventBusImpl {
  private emitter = new Phaser.Events.EventEmitter();

  on<T extends keyof GameEvents>(event: T, fn: Handler<T>, context?: unknown): this {
    this.emitter.on(event, fn, context);
    return this;
  }

  once<T extends keyof GameEvents>(event: T, fn: Handler<T>, context?: unknown): this {
    this.emitter.once(event, fn, context);
    return this;
  }

  off<T extends keyof GameEvents>(event: T, fn: Handler<T>, context?: unknown): this {
    this.emitter.off(event, fn, context);
    return this;
  }

  emit<T extends keyof GameEvents>(event: T, payload: GameEvents[T]): this {
    this.emitter.emit(event, payload);
    return this;
  }

  removeAllListeners(event?: keyof GameEvents): this {
    this.emitter.removeAllListeners(event);
    return this;
  }

  listenerCount(event: keyof GameEvents): number {
    return this.emitter.listenerCount(event);
  }
}

export const gameEvents = new EventBusImpl();
