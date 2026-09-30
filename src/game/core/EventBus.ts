import Phaser from 'phaser';
import type { StatusKind } from './types';
import type { QuestDomainEvents, QuestInputEvents } from '../content/quests/types';

/**
 * Central typed event bus. Singleton so any system can emit/subscribe without
 * holding scene references. Wraps a Phaser.Events.EventEmitter.
 *
 * Keep the event map exhaustive so callers get autocompletion + compile-time
 * safety on payloads.
 */

/** Where restored HP came from; omitted for ordinary heals (potions, abilities). */
export type HealSource = 'rest';

export type GameEvents = {
  'coins.changed': { coins: number; delta: number };
  'boost.changed': { boostBonus: number; delta: number };
  'collectible.collected': CollectibleCollectedPayload;
  'player.action': { anim: string };
  'area.enter': { areaId: string };
  'enemy.died': { enemyId: number; areaId: string; kind: string };
  'save.done': { slot: string };
  'save.loaded': { slot: string };
  'persistence.modal': { open: boolean };
  'world.progress.changed': {};

  // ── Phase 1: health / leveling / inventory ──
  'hp.changed': { hp: number; maxHp: number; delta: number };
  'player.damage': { amount: number; source?: string; crit: boolean };
  /** `source: 'rest'` marks slow sleep healing, which stays silent. */
  'player.heal': { amount: number; source?: HealSource };
  /** The player fell asleep in a bed or woke up. */
  'player.sleep': { asleep: boolean };
  /** HP reached full while sleeping. */
  'player.rested': {};
  /** The player's critical attack connected with a creature (sounds a crit on top of the hit). */
  'weapon.critical-hit': {};
  /** A boss fight began (the boss spawned in its arena). */
  'boss.engaged': { campId: string; bossId: string };
  /** A boss fight ended: the boss was defeated, or the fight reset (defeat, leaving the arena). */
  'boss.disengaged': { campId: string; defeated: boolean };
  /** The slime took a Gulp form (`formId`) or lost it (`formId: null`, with why). */
  'gulp.changed': { formId: string | null; reason: 'started' | 'refreshed' | 'burp' | 'expired' | 'switched' | 'cleared' };
  /** Player-placed furniture went back into the inventory (`furniture.placed` is declared with the quest inputs). */
  'furniture.picked-up': { mapId: string; placementId: string; itemId: string };
  /** A crafting station was opened; `placementId` is set for player-placed stations. */
  'workbench.opened': { mapId: string; placementId?: string; context: string };
  'player.death': {};
  'player.respawn': {};
  'energy.changed': { energy: number; maxEnergy: number; delta: number };
  /** A quest or boss taught the slime an ability (story unlock). */
  'ability.learned': { abilityId: string };
  /** A ruined building was paid for and restored (`object.activated` reports it to quests). */
  'building.restored': { objectId: string; instanceId: string; x: number; y: number };
  /** F at a ruined building did nothing: `missing-materials`, or `locked` (its quest is not active). */
  'building.restore-refused': { objectId: string; reason: 'missing-materials' | 'locked' };
  /** The Sticky slime tore a spider web open for good. */
  'web.torn': { x: number; y: number };
  /** Weak ground broke under the Heavy Gulp form. */
  'ground.cracked': { x: number; y: number };
  /** Craft was pressed but refused (missing materials, full inventory, ...). */
  'craft.failed': { recipeId: string; reason: string };
  /** A Goo Heart was collected; max HP is now `maxHp`. */
  'goo-heart.collected': { heartId: string; maxHp: number };
  'status.added': { kind: StatusKind; stacks: number };
  'status.removed': { kind: StatusKind };
  'inventory.changed': {};
  'weapon.loadout.changed': { slots: readonly (string | null)[] };
  'weapon.equipped': { weaponId: string | null };
} & QuestDomainEvents & QuestInputEvents;

export interface CollectibleCollectedPayload {
  readonly mapId: string;
  readonly instanceId: string;
  readonly objectId: string;
  readonly itemId: string;
  readonly quantity: number;
}

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
