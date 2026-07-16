import { biomeSample } from './terrainNoise';
import type { BiomeId } from './world/Biome';

type TileInset = {
  left: number;
  right: number;
  top: number;
  bottom: number;
};

const DEFAULT_SOLID_INSET: TileInset = {
  left: 6,
  right: 6,
  top: 8,
  bottom: 8,
};

export type TileCollisionRule = {
  kind: 'solid';
  inset?: Partial<TileInset>;
};

export type WorldTileId =
  | 'grass-a'
  | 'grass-b'
  | 'water'
  | 'rock-wall'
  | 'forest-floor'
  | 'forest-moss'
  | 'tree-wall'
  | 'cavern-floor'
  | 'crystal-floor'
  | 'crystal-wall'
  | 'deep-water';

export interface WorldTileRule {
  texture: string;
  textureVariants?: readonly string[];
  collision?: TileCollisionRule;
  allowsDecorations?: boolean;
}

export const WORLD_TILE_RULES: Readonly<Record<WorldTileId, WorldTileRule>> = {
  'grass-a': {
    texture: 'grass-a',
    textureVariants: ['grass-a', 'grass-a-1', 'grass-a-2'],
    allowsDecorations: true,
  },
  'grass-b': {
    texture: 'grass-b',
    textureVariants: ['grass-b', 'grass-b-1', 'grass-b-2'],
    allowsDecorations: true,
  },
  water: {
    texture: 'water',
    textureVariants: ['water', 'water-1', 'water-2'],
  },
  'rock-wall': {
    texture: 'rock-wall',
    textureVariants: ['rock-wall', 'rock-wall-1', 'rock-wall-2'],
    collision: {
      kind: 'solid',
      inset: {
        left: 4,
        right: 4,
        top: 6,
        bottom: 2,
      },
    },
  },
  'forest-floor': {
    texture: 'forest-floor',
    allowsDecorations: true,
  },
  'forest-moss': {
    texture: 'forest-moss',
    allowsDecorations: true,
  },
  'tree-wall': {
    texture: 'tree-wall',
    collision: {
      kind: 'solid',
      inset: { left: 8, right: 8, top: 8, bottom: 4 },
    },
  },
  'cavern-floor': {
    texture: 'cavern-floor',
    allowsDecorations: true,
  },
  'crystal-floor': {
    texture: 'crystal-floor',
    allowsDecorations: true,
  },
  'crystal-wall': {
    texture: 'crystal-wall',
    collision: {
      kind: 'solid',
      inset: { left: 5, right: 5, top: 7, bottom: 3 },
    },
  },
  'deep-water': {
    texture: 'deep-water',
  },
} as const;

export function resolveWorldTile(tileX: number, tileY: number, biome: BiomeId = 'meadow', seed = 0): WorldTileId {
  const edgeLane = tileX < 6 || tileX > 47 || tileY < 6 || tileY > 47;
  const noise = biomeSample(tileX, tileY, seed);
  const ridge = biomeSample(tileX - 13, tileY + 17, seed);
  const shelf = biomeSample(tileX + 7, tileY - 19, seed);

  if (biome === 'gloop-forest') {
    if (edgeLane) return 'forest-floor';
    if (ridge > 0.78 && shelf > 0.48) return 'tree-wall';
    if (noise > 0.78) return 'deep-water';
    return noise > 0.42 ? 'forest-moss' : 'forest-floor';
  }

  if (biome === 'crystal-caverns') {
    if (edgeLane) return 'cavern-floor';
    if (ridge > 0.7 || shelf > 0.84) return 'crystal-wall';
    if (noise > 0.76) return 'deep-water';
    return noise > 0.46 ? 'crystal-floor' : 'cavern-floor';
  }

  if (noise > 0.73) {
    return 'water';
  }

  return noise > 0.38 ? 'grass-b' : 'grass-a';
}

export function resolveWorldTileTexture(tileId: WorldTileId, tileX: number, tileY: number, seed = 0): string {
  const rule = WORLD_TILE_RULES[tileId];
  const variants = rule.textureVariants;

  if (!variants || variants.length === 0) {
    return rule.texture;
  }

  const hash = Math.imul(tileX + seed * 17, 374761393) ^ Math.imul(tileY - seed * 31, 668265263);
  const index = Math.abs(hash) % variants.length;

  return variants[index];
}

export function isTileCollidable(tileId: WorldTileId): boolean {
  return Boolean(WORLD_TILE_RULES[tileId].collision);
}

export function getTileBodyBounds(tileId: WorldTileId, tileSize: number): {
  width: number;
  height: number;
  offsetX: number;
  offsetY: number;
} | null {
  const collision = WORLD_TILE_RULES[tileId].collision;

  if (!collision || collision.kind !== 'solid') {
    return null;
  }

  const inset = {
    ...DEFAULT_SOLID_INSET,
    ...collision.inset,
  };

  return {
    width: tileSize - inset.left - inset.right,
    height: tileSize - inset.top - inset.bottom,
    offsetX: inset.left,
    offsetY: inset.top,
  };
}
