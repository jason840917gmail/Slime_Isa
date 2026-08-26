import { gameEvents } from './EventBus';
import { PLAYER_CONFIG } from '../content/player';
import { createInitialRunState } from '../content/initial-state/InitialRun';
import { PERK_BALANCE } from '../content/perks';
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

const SAVE_SCHEMA_VERSION = 2;

// ── Level curve ──
// xpForLevel(n) = total XP required to REACH level n from level 1.
// XP to go from level n → n+1 = xpForLevel(n+1) - xpForLevel(n).
export function xpForLevel(level: number): number {
  if (level <= 1) return 0;
  let total = 0;
  for (let n = 2; n <= level; n += 1) {
    total += Math.round(80 * Math.pow(n - 1, 1.5));
  }
  return total;
}

export function xpForNext(level: number): number {
  return xpForLevel(level + 1) - xpForLevel(level);
}

// ── Stat growth per level ──
const HP_PER_LEVEL = PLAYER_CONFIG.progression.hpPerLevel;
const ATK_PER_LEVEL = PLAYER_CONFIG.progression.attackPerLevel;
const DEF_PER_LEVEL = PLAYER_CONFIG.progression.defensePerLevel;
const ENERGY_PER_LEVEL = PLAYER_CONFIG.progression.energyPerLevel;
const BASE_MAX_HP = PLAYER_CONFIG.progression.baseMaxHp;
const BASE_MAX_ENERGY = PLAYER_CONFIG.progression.baseMaxEnergy;

export interface GameStateData {
  schemaVersion: number;
  coins: number;
  boostBonus: number;
  totalFriends: number;
  level: number;
  xp: number;
  hp: number;
  maxHpBonus: number;
  energy: number;
  maxEnergyBonus: number;
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

  get xp(): number {
    return this.data.xp;
  }

  get skillPoints(): number {
    return this.data.skillPoints;
  }

  addXp(amount: number): void {
    if (amount <= 0) return;
    this.data.xp += amount;
    let leveledUp = false;
    while (this.data.xp >= xpForLevel(this.data.level + 1)) {
      this.data.level += 1;
      this.data.skillPoints += 1;
      this.data.maxHpBonus += HP_PER_LEVEL;
      this.data.maxEnergyBonus += ENERGY_PER_LEVEL;
      this.data.hp = this.maxHp;
      this.data.energy = this.maxEnergy;
      gameEvents.emit('level.up', {
        level: this.data.level,
        skillPoints: 1,
      });
      gameEvents.emit('skillpoint.changed', { points: this.data.skillPoints });
      leveledUp = true;
    }
    this.emitXp(amount);
    if (leveledUp) this.emitHp(0);
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
    return BASE_MAX_HP
      + this.data.maxHpBonus
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
    return BASE_MAX_ENERGY
      + this.data.maxEnergyBonus
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
    return 10 + (this.data.level - 1) * ATK_PER_LEVEL;
  }

  get defenseBase(): number {
    return 2 + (this.data.level - 1) * DEF_PER_LEVEL;
  }

  private emitHp(delta: number): void {
    gameEvents.emit('hp.changed', { hp: this.data.hp, maxHp: this.maxHp, delta });
  }

  private emitEnergy(delta: number): void {
    gameEvents.emit('energy.changed', { energy: this.data.energy, maxEnergy: this.maxEnergy, delta });
  }

  private emitXp(delta: number): void {
    const level = this.data.level;
    const xpInto = this.data.xp - xpForLevel(level);
    const need = xpForNext(level);
    gameEvents.emit('xp.changed', {
      xp: this.data.xp,
      xpIntoLevel: Math.max(0, xpInto),
      xpForNext: need,
      level,
      delta,
    });
  }
}

export const gameState = new GameStateImpl();
export { SAVE_SCHEMA_VERSION, BASE_MAX_HP, BASE_MAX_ENERGY, HP_PER_LEVEL, ATK_PER_LEVEL, DEF_PER_LEVEL, ENERGY_PER_LEVEL };
