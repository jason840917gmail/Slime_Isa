import { gameEvents, type HealSource } from './EventBus';
import { createInitialRunState } from '../content/initial-state/InitialRun';
import { GAME_CONSTANTS } from '../Constant';
import type { CharacterAttributeSet } from '../content/characters/types';
import { WEAPON_HOTBAR_SLOT_COUNT } from './types';

/**
 * Single source of truth for persistent player state: coins, HP, energy, Goo
 * Hearts, attributes and equipment. The slime grows through gear, Goo Hearts
 * and story-taught abilities, never through experience (see GAME_GUIDELINES).
 */

const SAVE_SCHEMA_VERSION = 5;
const STATS = GAME_CONSTANTS.character.player.stats;
const GOO_HEART = GAME_CONSTANTS.character.player.gooHeart;

export interface GameStateData {
  schemaVersion: number;
  coins: number;
  boostBonus: number;
  hp: number;
  energy: number;
  /** Goo Hearts collected this run; each one raises max HP for good. */
  gooHearts: number;
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
      schemaVersion: SAVE_STATE_SCHEMA_VERSION,
      coins: data.coins ?? defaults.coins,
      boostBonus: data.boostBonus ?? defaults.boostBonus,
      hp: data.hp ?? defaults.hp,
      energy: data.energy ?? defaults.energy,
      gooHearts: data.gooHearts ?? defaults.gooHearts,
      attributes: { ...defaults.attributes, ...(data.attributes ?? {}) },
      equipment: {
        ...defaults.equipment,
        ...(data.equipment ?? {}),
        weaponId: normalizeEquippedWeaponId(data.equipment?.weaponId),
        weaponSlots: normalizeWeaponSlots(data.equipment?.weaponSlots),
      },
    };
    this.data.hp = Math.min(this.data.hp, this.maxHp);
    this.data.energy = Math.min(this.data.energy, this.maxEnergy);

    gameEvents.emit('coins.changed', { coins: this.data.coins, delta: 0 });
    gameEvents.emit('boost.changed', { boostBonus: this.data.boostBonus, delta: 0 });
    this.emitHp(0);
    this.emitEnergy(0);
    gameEvents.emit('weapon.loadout.changed', { slots: [...this.data.equipment.weaponSlots] });
    gameEvents.emit('weapon.equipped', { weaponId: this.data.equipment.weaponId });
  }

  reset(): void {
    this.data = defaultData();
    gameEvents.emit('coins.changed', { coins: this.data.coins, delta: 0 });
    gameEvents.emit('boost.changed', { boostBonus: this.data.boostBonus, delta: 0 });
    this.emitHp(0);
    this.emitEnergy(0);
    gameEvents.emit('weapon.loadout.changed', { slots: [...this.data.equipment.weaponSlots] });
    gameEvents.emit('weapon.equipped', { weaponId: this.data.equipment.weaponId });
  }

  serialize(): GameStateData {
    return {
      ...this.data,
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

  // ── Goo Hearts ──
  get gooHearts(): number {
    return this.data.gooHearts;
  }

  /** A collected Goo Heart raises max HP for the rest of the run and fills HP. */
  addGooHeart(): void {
    this.data.gooHearts += 1;
    const healed = this.maxHp - this.data.hp;
    this.data.hp = this.maxHp;
    this.emitHp(healed);
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
    return STATS.maxHp + this.data.gooHearts * GOO_HEART.maxHpBonus;
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

  heal(amount: number, source?: HealSource): number {
    if (amount <= 0 || this.data.hp <= 0) return 0;
    const newHp = Math.min(this.maxHp, this.data.hp + amount);
    const healed = newHp - this.data.hp;
    this.data.hp = newHp;
    if (healed > 0) gameEvents.emit('player.heal', source ? { amount: healed, source } : { amount: healed });
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
    return STATS.maxEnergy;
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

  private emitHp(delta: number): void {
    gameEvents.emit('hp.changed', { hp: this.data.hp, maxHp: this.maxHp, delta });
  }

  private emitEnergy(delta: number): void {
    gameEvents.emit('energy.changed', { energy: this.data.energy, maxEnergy: this.maxEnergy, delta });
  }
}

export const gameState = new GameStateImpl();
export { SAVE_SCHEMA_VERSION };
