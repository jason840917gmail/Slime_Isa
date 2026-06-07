import { sample } from './terrainNoise';

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

export type WorldTileId = 'grass-a' | 'grass-b' | 'water' | 'rock-wall';

export interface WorldTileRule {
  texture: string;
  collision?: TileCollisionRule;
  allowsDecorations?: boolean;
}

export const WORLD_TILE_RULES: Readonly<Record<WorldTileId, WorldTileRule>> = {
  'grass-a': {
    texture: 'grass-a',
    allowsDecorations: true,
  },
  'grass-b': {
    texture: 'grass-b',
    allowsDecorations: true,
  },
  water: {
    texture: 'water',
  },
  'rock-wall': {
    texture: 'rock-wall',
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
} as const;

export function resolveWorldTile(tileX: number, tileY: number): WorldTileId {
  const noise = sample(tileX, tileY);
  const ridge = sample(tileX - 13, tileY + 17);
  const shelf = sample(tileX + 7, tileY - 19);

  if (ridge > 0.82 && shelf > 0.58) {
    return 'rock-wall';
  }

  if (noise > 0.73) {
    return 'water';
  }

  return noise > 0.38 ? 'grass-b' : 'grass-a';
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