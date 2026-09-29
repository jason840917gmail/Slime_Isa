import type { AssetId } from '../../infrastructure/assets/manifest';
import { parseTileSetResource } from '../scenes/resources/TileSetResource';
import type { TileSetResourceDocument } from '../scenes/resources/types';
import terrainTiles from '../scenes/authored/resources/terrain/terrain.tile-set.resource.json';

type TileInset = {
  readonly left: number;
  readonly right: number;
  readonly top: number;
  readonly bottom: number;
};

export interface TileDefinition {
  readonly visual: {
    readonly assetIds: readonly AssetId[];
    readonly selection: 'seeded-hash' | 'ground-sheet-region' | 'sheet-order' | 'sheet-wrap';
  };
  readonly physics: null | {
    readonly body: 'static';
    readonly inset?: Partial<TileInset>;
    /** Named collision layer for this tile's bodies (default `world`). */
    readonly layer?: string;
  };
  readonly allowsDecorations: boolean;
  /**
   * Visual-only derived blending (see features/world/TerrainBlendField). Tiles
   * of different materials in the same group blend into organic regions;
   * priority decides which material edges into the other. `edgeWidth` and
   * `style` are retained data from the earlier per-edge feathering and no
   * longer drive rendering. Never affects physics or map data.
   */
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

const TERRAIN_TILE_SET = parseTileSetResource(terrainTiles as unknown as TileSetResourceDocument);

function tileFromResource(tileId: string): TileDefinition {
  const resource = TERRAIN_TILE_SET;
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

// The shared terrain TileSet (Scene Studio resource `terrain.tiles`) owns the
// metadata; this API preserves the stable map tile IDs.
export const TILE_CATALOG = {
  'grass-a': tileFromResource('grass-a'),
  'grass-b': tileFromResource('grass-b'),
  water: tileFromResource('water'),
  'rock-wall': tileFromResource('rock-wall'),
  'forest-floor': tileFromResource('forest-floor'),
  'forest-moss': tileFromResource('forest-moss'),
  'cavern-floor': tileFromResource('cavern-floor'),
  'crystal-floor': tileFromResource('crystal-floor'),
  'deep-water': tileFromResource('deep-water'),
  'amberleaf-ground': tileFromResource('amberleaf-ground'),
  'frozen-ground': tileFromResource('frozen-ground'),
  'sanddessert-ground': tileFromResource('sanddessert-ground'),
  'wood-floor': tileFromResource('wood-floor'),
  'mushroom-earth-floor': tileFromResource('mushroom-earth-floor'),
  'mushroom-clover-floor': tileFromResource('mushroom-clover-floor'),
  'mushroom-plain-floor': tileFromResource('mushroom-plain-floor'),
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
