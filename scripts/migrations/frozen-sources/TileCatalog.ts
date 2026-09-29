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
    visual: { assetIds: ['sheet.grounds.19x19.highland-green'], selection: 'sheet-wrap' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'highland', priority: 10, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'meadow', 'walkable'],
  },
  'grass-b': {
    visual: { assetIds: ['sheet.grounds.19x19.highland-green'], selection: 'sheet-wrap' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'highland', priority: 10, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'meadow', 'walkable'],
  },
  water: {
    visual: { assetIds: ['sheet.grounds.19x19.water'], selection: 'sheet-wrap' },
    physics: { body: 'static', inset: { left: 10, right: 10, top: 10, bottom: 10 }, layer: 'water' },
    allowsDecorations: false,
    transition: { group: 'natural-ground', material: 'water', priority: 5, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'water'],
  },
  'rock-wall': {
    visual: { assetIds: ['sheet.grounds.19x19.highland-green'], selection: 'sheet-wrap' },
    physics: { body: 'static', inset: { left: 4, right: 4, top: 6, bottom: 2 } },
    allowsDecorations: false,
    tags: ['legacy', 'wall'],
  },
  'forest-floor': {
    visual: { assetIds: ['sheet.grounds.19x19.forest-floor'], selection: 'sheet-wrap' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'forest-floor', priority: 10, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'forest', 'walkable'],
  },
  'forest-moss': {
    visual: { assetIds: ['sheet.grounds.19x19.forest-moss'], selection: 'sheet-wrap' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'forest-moss', priority: 20, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'forest', 'walkable'],
  },
  'cavern-floor': {
    visual: { assetIds: ['sheet.grounds.19x19.cavern-floor'], selection: 'sheet-wrap' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'cavern-floor', priority: 10, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'cavern', 'walkable'],
  },
  'crystal-floor': {
    visual: { assetIds: ['sheet.grounds.19x19.crystal-floor'], selection: 'sheet-wrap' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'crystal-floor', priority: 20, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'cavern', 'walkable'],
  },
  'deep-water': {
    visual: { assetIds: ['sheet.grounds.19x19.deep-water'], selection: 'sheet-wrap' },
    physics: { body: 'static', inset: { left: 10, right: 10, top: 10, bottom: 10 }, layer: 'water' },
    allowsDecorations: false,
    transition: { group: 'natural-ground', material: 'deep-water', priority: 4, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'water', 'deep'],
  },
  'amberleaf-ground': {
    visual: { assetIds: ['sheet.grounds.19x19.amberleaf'], selection: 'sheet-wrap' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'amberleaf', priority: 10, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'amberleaf', 'walkable'],
  },
  'frozen-ground': {
    visual: { assetIds: ['sheet.grounds.19x19.frozen'], selection: 'sheet-wrap' },
    physics: null,
    allowsDecorations: true,
    transition: { group: 'natural-ground', material: 'frozen', priority: 10, edgeWidth: 12, style: 'noisy-feather' },
    tags: ['ground', 'frozen', 'walkable'],
  },
  'sanddessert-ground': {
    visual: { assetIds: ['sheet.grounds.19x19.sanddessert'], selection: 'sheet-wrap' },
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
