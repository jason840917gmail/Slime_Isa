/**
 * Shared type definitions for Phase 1 systems.
 *
 * Kept in a standalone module so EventBus, GameState, StatusEffects and others
 * can reference them without circular imports.
 */

export type StatusKind =
  | 'burn'
  | 'poison'
  | 'slow'
  | 'sticky'
  | 'bouncy'
  | 'frenzy';

/** Weapons on the belt, switched with the mouse wheel (roadmap 4.10). */
export const WEAPON_HOTBAR_SLOT_COUNT = 3;

export type ItemCategory = 'consumable' | 'material' | 'key' | 'collectible' | 'weapon' | 'tool' | 'furniture';

export interface ItemDef {
  id: string;
  name: string;
  category: ItemCategory;
  /** Texture key from BootScene. */
  icon: string;
  /** Optional spritesheet frame for content sheets that contain multiple icons. */
  iconFrame?: number;
  description: string;
  /** Max stack size; 1 = unique. */
  maxStack: number;
  /** For consumables: effect on use. */
  use?: ItemUse;
  /** Equipment items resolve to a reusable weapon definition at runtime. */
  equipment?: {
    weaponId: string;
  };
  /**
   * Furniture the player can place in the world from the inventory. The first
   * scene is the default; the mouse wheel cycles the others while placing (e.g. facing variants).
   */
  placeable?: {
    sceneIds: string[];
  };
  /** Explicit catalog presentation used when this item is dropped into the world. */
  worldDrop?: {
    objectId: string;
    visualId: string;
  };
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
