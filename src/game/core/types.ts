/**
 * Shared type definitions for Phase 1 systems.
 *
 * Kept in a standalone module so EventBus, GameState, StatusEffects, LevelUpModal
 * and others can reference them without circular imports.
 */

export type StatusKind =
  | 'burn'
  | 'poison'
  | 'slow'
  | 'sticky'
  | 'bouncy'
  | 'frenzy';

export interface PerkChoice {
  id: string;
  title: string;
  description: string;
  /** Optional icon texture key generated in BootScene. */
  icon?: string;
}

export type ItemCategory = 'consumable' | 'material' | 'key' | 'collectible';

export interface ItemDef {
  id: string;
  name: string;
  category: ItemCategory;
  /** Texture key from BootScene. */
  icon: string;
  description: string;
  /** Max stack size; 1 = unique. */
  maxStack: number;
  /** For consumables: effect on use. */
  use?: ItemUse;
}

export interface ItemUse {
  healHp?: number;
  healEnergy?: number;
  cureStatus?: StatusKind[];
}

export interface InventorySlot {
  itemId: string;
  count: number;
}
