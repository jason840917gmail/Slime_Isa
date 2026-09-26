import type { AssetId } from '../../infrastructure/assets/manifest';

type TileInset = {
  readonly left: number;
  readonly right: number;
  readonly top: number;
  readonly bottom: number;
};

export interface TileDefinition {
  readonly visual: {
    readonly assetIds: readonly AssetId[];
    readonly selection: 'seeded-hash' | 'ground-sheet-region' | 'sheet-order';
  };
  readonly physics: null | {
    readonly body: 'static';
    readonly inset?: Partial<TileInset>;
  };
  readonly allowsDecorations: boolean;
  /** Visual-only derived edge blending. Never affects physics or map data. */
  readonly transition?: {
    readonly group: 'natural-ground';
    /** Same material means no transition even when logical tile IDs differ. */
    readonly material: string;
    /** Higher-priority material feathers into lower-priority material. */
    readonly priority: number;
    readonly edgeWidth: number;
    readonly style: 'noisy-feather';
  };
  readonly tags: readonly string[];
}

export const TILE_CATALOG = {
  'grass-a': {
    visual: { assetIds: ['sheet.grounds.19x19.highland-green'], selection: 'sheet-order' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'highland', priority: 10, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'meadow', 'walkable'],
  },
  'grass-b': {
    visual: { assetIds: ['sheet.grounds.19x19.highland-green'], selection: 'sheet-order' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'highland', priority: 10, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'meadow', 'walkable'],
  },
  water: {
    visual: { assetIds: ['terrain.water.0', 'terrain.water.1', 'terrain.water.2'], selection: 'seeded-hash' },
    physics: null,
    allowsDecorations: false,
    tags: ['ground', 'water'],
  },
  'rock-wall': {
    visual: { assetIds: ['sheet.grounds.19x19.highland-green'], selection: 'sheet-order' },
    physics: { body: 'static', inset: { left: 4, right: 4, top: 6, bottom: 2 } },
    allowsDecorations: false,
    tags: ['legacy', 'wall'],
  },
  'forest-floor': {
    visual: { assetIds: ['terrain.forest.floor'], selection: 'seeded-hash' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'forest-floor', priority: 10, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'forest', 'walkable'],
  },
  'forest-moss': {
    visual: { assetIds: ['terrain.forest.moss'], selection: 'seeded-hash' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'forest-moss', priority: 20, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'forest', 'walkable'],
  },
  'tree-wall': {
    visual: { assetIds: ['terrain.forest.tree-wall'], selection: 'seeded-hash' },
    physics: { body: 'static', inset: { left: 8, right: 8, top: 8, bottom: 4 } },
    allowsDecorations: false,
    tags: ['terrain', 'forest', 'wall'],
  },
  'cavern-floor': {
    visual: { assetIds: ['terrain.cavern.floor'], selection: 'seeded-hash' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'cavern-floor', priority: 10, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'cavern', 'walkable'],
  },
  'crystal-floor': {
    visual: { assetIds: ['terrain.cavern.crystal-floor'], selection: 'seeded-hash' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'crystal-floor', priority: 20, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'cavern', 'walkable'],
  },
  'crystal-wall': {
    visual: { assetIds: ['terrain.cavern.crystal-wall'], selection: 'seeded-hash' },
    physics: { body: 'static', inset: { left: 5, right: 5, top: 7, bottom: 3 } },
    allowsDecorations: false,
    tags: ['terrain', 'cavern', 'wall'],
  },
  'deep-water': {
    visual: { assetIds: ['terrain.deep-water'], selection: 'seeded-hash' },
    physics: null,
    allowsDecorations: false,
    tags: ['ground', 'water', 'deep'],
  },
  'amberleaf-ground': {
    visual: { assetIds: ['sheet.grounds.19x19.amberleaf'], selection: 'sheet-order' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'amberleaf', priority: 10, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'amberleaf', 'walkable'],
  },
  'frozen-ground': {
    visual: { assetIds: ['sheet.grounds.19x19.frozen'], selection: 'sheet-order' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'frozen', priority: 10, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'frozen', 'walkable'],
  },
  'sanddessert-ground': {
    visual: { assetIds: ['sheet.grounds.19x19.sanddessert'], selection: 'sheet-order' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'sanddessert', priority: 10, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'sanddessert', 'walkable'],
  },
} as const satisfies Readonly<Record<string, TileDefinition>>;

export type WorldTileId = keyof typeof TILE_CATALOG;

export function getTileDefinition(tileId: WorldTileId): TileDefinition {
  return TILE_CATALOG[tileId];
}

export function isWorldTileId(value: string): value is WorldTileId {
  return value in TILE_CATALOG;
}

export function getTileIds(): readonly WorldTileId[] {
  return Object.keys(TILE_CATALOG) as WorldTileId[];
}

export function isTileCollidable(tileId: WorldTileId): boolean {
  return TILE_CATALOG[tileId].physics !== null;
}

export function getTileBodyBounds(tileId: WorldTileId, tileSize: number): {
  width: number;
  height: number;
  offsetX: number;
  offsetY: number;
} | null {
  const physics = TILE_CATALOG[tileId].physics;
  if (!physics) return null;
  const configuredInset: Partial<TileInset> = physics.inset ?? {};

  const inset = {
    left: 6,
    right: 6,
    top: 8,
    bottom: 8,
    ...configuredInset,
  };

  return {
    width: tileSize - inset.left - inset.right,
    height: tileSize - inset.top - inset.bottom,
    offsetX: inset.left,
    offsetY: inset.top,
  };
}
