import { gameEvents } from './EventBus';
import { createInitialRunState } from '../content/initial-state/InitialRun';
import { GAME_CONSTANTS } from '../Constant';
import { PERK_BALANCE } from '../content/perks';
import { applyExperience, resolveLevelStats } from '../systems/PlayerProgression';
import type { CharacterAttributeSet } from '../content/characters/types';
import { WEAPON_HOTBAR_SLOT_COUNT } from './types';

/**
 * Single source of truth for persistent player state.
 *
 * Phase 0: coins + boostBonus.
 * Phase 1: hp, maxHp, level, xp, energy, maxEnergy, skillPoints, perks.
 * Future phases extend with abilities, weapons, inventory, discovered areas,
 * quest flags — all flowing through the same emit-on-change pipeline.
 */

const SAVE_SCHEMA_VERSION = 3;
const PROGRESSION = GAME_CONSTANTS.character.player.progression;

export interface GameStateData {
  schemaVersion: number;
  coins: number;
  boostBonus: number;
  totalFriends: number;
  level: number;
  currentXp: number;
  hp: number;
  energy: number;
  skillPoints: number;
  perks: Record<string, number>;
  attributes: CharacterAttributeSet;
  equipment: {
    weaponId: string | null;
    weaponSlots: Array<string | null>;
  };
}

function defaultData(): GameStateData {
  const initial = createInitialRunState().player;
  return {
    ...initial,
    schemaVersion: SAVE_STATE_SCHEMA_VERSION,
    perks: {},
    attributes: { ...initial.attributes },
    equipment: { ...initial.equipment, weaponSlots: [...initial.equipment.weaponSlots] },
  };
}

const SAVE_STATE_SCHEMA_VERSION = SAVE_SCHEMA_VERSION;

function normalizeWeaponSlots(value: unknown): Array<string | null> {
  const input = Array.isArray(value) ? value : defaultData().equipment.weaponSlots;
  return Array.from({ length: WEAPON_HOTBAR_SLOT_COUNT }, (_, index) => {
    const entry = input[index];
    return typeof entry === 'string' && entry.trim().length > 0 ? entry : null;
  });
}

function normalizeEquippedWeaponId(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : null;
}

class GameStateImpl {
  private data: GameStateData = defaultData();

  load(data: Partial<GameStateData>): void {
    const defaults = defaultData();
    this.data = {
      ...defaults,
      ...data,
      perks: { ...(data.perks ?? {}) },
      attributes: { ...defaults.attributes, ...(data.attributes ?? {}) },
      equipment: {
        ...defaults.equipment,
        ...(data.equipment ?? {}),
        weaponId: normalizeEquippedWeaponId(data.equipment?.weaponId),
        weaponSlots: normalizeWeaponSlots(data.equipment?.weaponSlots),
      },
      schemaVersion: SAVE_STATE_SCHEMA_VERSION,
    };
    this.data.hp = Math.min(this.data.hp, this.maxHp);
    this.data.energy = Math.min(this.data.energy, this.maxEnergy);

    gameEvents.emit('coins.changed', { coins: this.data.coins, delta: 0 });
    gameEvents.emit('boost.changed', { boostBonus: this.data.boostBonus, delta: 0 });
    gameEvents.emit('friend.count', { count: this.data.totalFriends });
    this.emitHp(0);
    this.emitEnergy(0);
    this.emitXp(0);
    gameEvents.emit('weapon.loadout.changed', { slots: [...this.data.equipment.weaponSlots] });
    gameEvents.emit('weapon.equipped', { weaponId: this.data.equipment.weaponId });
  }

  reset(): void {
    this.data = defaultData();
    gameEvents.emit('coins.changed', { coins: this.data.coins, delta: 0 });
    gameEvents.emit('boost.changed', { boostBonus: this.data.boostBonus, delta: 0 });
    gameEvents.emit('friend.count', { count: this.data.totalFriends });
    this.emitHp(0);
    this.emitEnergy(0);
    this.emitXp(0);
    gameEvents.emit('weapon.loadout.changed', { slots: [...this.data.equipment.weaponSlots] });
    gameEvents.emit('weapon.equipped', { weaponId: this.data.equipment.weaponId });
  }

  serialize(): GameStateData {
    return {
      ...this.data,
      perks: { ...this.data.perks },
      attributes: { ...this.data.attributes },
      equipment: { ...this.data.equipment, weaponSlots: [...this.data.equipment.weaponSlots] },
    };
  }

  // ── Coins ──
  get coins(): number {
    return this.data.coins;
  }

  addCoins(amount: number): void {
    if (amount === 0) return;
    this.data.coins = Math.max(0, this.data.coins + amount);
    gameEvents.emit('coins.changed', { coins: this.data.coins, delta: amount });
  }

  spendCoins(amount: number): boolean {
    if (this.data.coins < amount) return false;
    this.data.coins -= amount;
    gameEvents.emit('coins.changed', { coins: this.data.coins, delta: -amount });
    return true;
  }

  // ── Boost ──
  get boostBonus(): number {
    return this.data.boostBonus;
  }

  addBoost(amount: number): void {
    if (amount === 0) return;
    this.data.boostBonus += amount;
    gameEvents.emit('boost.changed', { boostBonus: this.data.boostBonus, delta: amount });
  }

  // ── Friends ──
  get totalFriends(): number {
    return this.data.totalFriends;
  }

  setTotalFriends(count: number): void {
    if (this.data.totalFriends === count) return;
    this.data.totalFriends = count;
    gameEvents.emit('friend.count', { count });
  }

  // ── Level / XP ──
  get level(): number {
    return this.data.level;
  }

  get currentXp(): number {
    return this.data.currentXp;
  }

  get xpToNextLevel(): number | null {
    return PROGRESSION.levels[this.data.level - 1]?.xpToNextLevel ?? null;
  }

  get skillPoints(): number {
    return this.data.skillPoints;
  }

  addXp(amount: number): void {
    if (amount <= 0) return;
    const result = applyExperience(PROGRESSION, this.data.level, this.data.currentXp, amount);
    for (const entry of result.levelsGained) {
      this.data.level = entry.level;
      this.data.skillPoints += 1;
      gameEvents.emit('level.up', {
        level: this.data.level,
        skillPoints: 1,
      });
      gameEvents.emit('skillpoint.changed', { points: this.data.skillPoints });
    }
    this.data.currentXp = result.currentXp;
    const leveledUp = result.levelsGained.length > 0;
    if (leveledUp) {
      this.data.hp = this.maxHp;
      this.data.energy = this.maxEnergy;
    }
    this.emitXp(amount);
    if (leveledUp) {
      this.emitHp(0);
      this.emitEnergy(0);
    }
  }

  spendSkillPoint(perkId: string): boolean {
    if (this.data.skillPoints <= 0) return false;
    this.data.skillPoints -= 1;
    this.data.perks[perkId] = (this.data.perks[perkId] ?? 0) + 1;
    gameEvents.emit('skillpoint.changed', { points: this.data.skillPoints });
    gameEvents.emit('perk.taken', { perkId });
    this.emitHp(0);
    this.emitEnergy(0);
    return true;
  }

  perkRank(perkId: string): number {
    return this.data.perks[perkId] ?? 0;
  }

  get attributes(): CharacterAttributeSet {
    return { ...this.data.attributes };
  }

  addAttribute(attribute: keyof CharacterAttributeSet, amount: number): void {
    if (!Number.isFinite(amount) || amount === 0) return;
    this.data.attributes[attribute] = Math.max(0, this.data.attributes[attribute] + amount);
  }

  get equippedWeaponId(): string | null {
    return this.data.equipment.weaponId;
  }

  get weaponSlots(): readonly (string | null)[] {
    return [...this.data.equipment.weaponSlots];
  }

  setWeaponSlots(slots: readonly (string | null)[]): void {
    const normalized = normalizeWeaponSlots(slots);
    if (normalized.every((entry, index) => entry === this.data.equipment.weaponSlots[index])) return;
    this.data.equipment.weaponSlots = normalized;
    gameEvents.emit('weapon.loadout.changed', { slots: [...normalized] });
  }

  equipWeapon(weaponId: string | null): boolean {
    const normalized = normalizeEquippedWeaponId(weaponId);
    if (normalized === this.data.equipment.weaponId) return false;
    this.data.equipment.weaponId = normalized;
    gameEvents.emit('weapon.equipped', { weaponId: normalized });
    return true;
  }

  // ── HP ──
  get maxHp(): number {
    return resolveLevelStats(PROGRESSION, this.data.level).maxHp
      + this.perkRank('tanky-goo') * PERK_BALANCE.maxHpPerTankyGooRank;
  }

  get hp(): number {
    return this.data.hp;
  }

  set hp(value: number) {
    const clamped = Math.max(0, Math.min(this.maxHp, value));
    const delta = clamped - this.data.hp;
    this.data.hp = clamped;
    this.emitHp(delta);
  }

  damage(amount: number, source?: string): number {
    if (amount <= 0 || this.data.hp <= 0) return 0;
    const newHp = Math.max(0, this.data.hp - amount);
    const actualHpLost = this.data.hp - newHp;
    this.data.hp = newHp;
    gameEvents.emit('player.damage', { amount: actualHpLost, source, crit: false });
    this.emitHp(-actualHpLost);
    if (this.data.hp <= 0) {
      gameEvents.emit('player.death', {});
    }
    return actualHpLost;
  }

  heal(amount: number): number {
    if (amount <= 0 || this.data.hp <= 0) return 0;
    const newHp = Math.min(this.maxHp, this.data.hp + amount);
    const healed = newHp - this.data.hp;
    this.data.hp = newHp;
    if (healed > 0) gameEvents.emit('player.heal', { amount: healed });
    this.emitHp(healed);
    return healed;
  }

  revive(): void {
    this.data.hp = this.maxHp;
    this.data.energy = this.maxEnergy;
    gameEvents.emit('player.respawn', {});
    this.emitHp(this.maxHp);
    this.emitEnergy(this.maxEnergy);
  }

  isDead(): boolean {
    return this.data.hp <= 0;
  }

  // ── Energy ──
  get maxEnergy(): number {
    return resolveLevelStats(PROGRESSION, this.data.level).maxEnergy
      + this.perkRank('deep-well') * PERK_BALANCE.maxEnergyPerDeepWellRank;
  }

  get energy(): number {
    return this.data.energy;
  }

  useEnergy(amount: number): boolean {
    if (this.data.energy < amount) return false;
    this.data.energy -= amount;
    this.emitEnergy(-amount);
    return true;
  }

  regenEnergy(amount: number): void {
    if (amount <= 0) return;
    const newE = Math.min(this.maxEnergy, this.data.energy + amount);
    const delta = newE - this.data.energy;
    this.data.energy = newE;
    this.emitEnergy(delta);
  }

  // ── Derived stat helpers (full table lives in PlayerStats) ──
  get attackBase(): number {
    return resolveLevelStats(PROGRESSION, this.data.level).attack;
  }

  get defenseBase(): number {
    return resolveLevelStats(PROGRESSION, this.data.level).defense;
  }

  private emitHp(delta: number): void {
    gameEvents.emit('hp.changed', { hp: this.data.hp, maxHp: this.maxHp, delta });
  }

  private emitEnergy(delta: number): void {
    gameEvents.emit('energy.changed', { energy: this.data.energy, maxEnergy: this.maxEnergy, delta });
  }

  private emitXp(delta: number): void {
    const level = this.data.level;
    gameEvents.emit('xp.changed', {
      currentXp: this.data.currentXp,
      xpToNextLevel: this.xpToNextLevel,
      level,
      delta,
    });
  }
}

export const gameState = new GameStateImpl();
export { SAVE_SCHEMA_VERSION };
