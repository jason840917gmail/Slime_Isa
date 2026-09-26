import type { AssetId } from '../../infrastructure/assets/manifest';
import { parseTileSetResource } from '../scenes/resources/TileSetResource';
import type { TileSetResourceDocument } from '../scenes/resources/types';
import amberleafGround from '../scenes/authored/resources/terrain/amberleaf-ground.tile-set.resource.json';
import cavernFloor from '../scenes/authored/resources/terrain/cavern-floor.tile-set.resource.json';
import crystalFloor from '../scenes/authored/resources/terrain/crystal-floor.tile-set.resource.json';
import crystalWall from '../scenes/authored/resources/terrain/crystal-wall.tile-set.resource.json';
import deepWater from '../scenes/authored/resources/terrain/deep-water.tile-set.resource.json';
import forestFloor from '../scenes/authored/resources/terrain/forest-floor.tile-set.resource.json';
import forestMoss from '../scenes/authored/resources/terrain/forest-moss.tile-set.resource.json';
import frozenGround from '../scenes/authored/resources/terrain/frozen-ground.tile-set.resource.json';
import grassA from '../scenes/authored/resources/terrain/grass-a.tile-set.resource.json';
import grassB from '../scenes/authored/resources/terrain/grass-b.tile-set.resource.json';
import rockWall from '../scenes/authored/resources/terrain/rock-wall.tile-set.resource.json';
import sanddessertGround from '../scenes/authored/resources/terrain/sanddessert-ground.tile-set.resource.json';
import treeWall from '../scenes/authored/resources/terrain/tree-wall.tile-set.resource.json';
import water from '../scenes/authored/resources/terrain/water.tile-set.resource.json';

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

function tileFromResource(document: unknown, tileId: string): TileDefinition {
  const resource = parseTileSetResource(document as TileSetResourceDocument);
  const tile = resource.tiles[tileId];
  if (!tile) throw new Error(`Tile set '${resource.resourceId}' is missing '${tileId}'`);
  return {
    visual: { assetIds: tile.assetIds as AssetId[], selection: tile.selection },
    physics: tile.physics,
    allowsDecorations: tile.allowsDecorations,
    ...(tile.transition ? { transition: tile.transition as TileDefinition['transition'] } : {}),
    tags: tile.tags,
  };
}

// Scene Studio tile-set documents own the metadata; this API preserves stable map tile IDs.
export const TILE_CATALOG = {
  'grass-a': tileFromResource(grassA, 'grass-a'),
  'grass-b': tileFromResource(grassB, 'grass-b'),
  water: tileFromResource(water, 'water'),
  'rock-wall': tileFromResource(rockWall, 'rock-wall'),
  'forest-floor': tileFromResource(forestFloor, 'forest-floor'),
  'forest-moss': tileFromResource(forestMoss, 'forest-moss'),
  'tree-wall': tileFromResource(treeWall, 'tree-wall'),
  'cavern-floor': tileFromResource(cavernFloor, 'cavern-floor'),
  'crystal-floor': tileFromResource(crystalFloor, 'crystal-floor'),
  'crystal-wall': tileFromResource(crystalWall, 'crystal-wall'),
  'deep-water': tileFromResource(deepWater, 'deep-water'),
  'amberleaf-ground': tileFromResource(amberleafGround, 'amberleaf-ground'),
  'frozen-ground': tileFromResource(frozenGround, 'frozen-ground'),
  'sanddessert-ground': tileFromResource(sanddessertGround, 'sanddessert-ground'),
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
