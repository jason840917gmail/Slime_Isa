import type { BiomeId } from './Biome';

export type AreaId = 'meadow-crossing' | 'gloop-forest' | 'crystal-caverns';
export type Direction = 'north' | 'east' | 'south' | 'west';

export interface AreaDef {
  id: AreaId;
  name: string;
  biome: BiomeId;
  seed: number;
  mapX: number;
  mapY: number;
  hasPlayerHome?: boolean;
  neighbors: Partial<Record<Direction, AreaId>>;
}

export const AREAS: Readonly<Record<AreaId, AreaDef>> = {
  'meadow-crossing': {
    id: 'meadow-crossing',
    name: 'Sunbell Meadow',
    biome: 'meadow',
    seed: 0,
    mapX: 0,
    mapY: 0,
    hasPlayerHome: true,
    neighbors: {
      east: 'gloop-forest',
    },
  },
  'gloop-forest': {
    id: 'gloop-forest',
    name: 'Gloop Forest',
    biome: 'gloop-forest',
    seed: 37,
    mapX: 1,
    mapY: 0,
    neighbors: {
      west: 'meadow-crossing',
      east: 'crystal-caverns',
    },
  },
  'crystal-caverns': {
    id: 'crystal-caverns',
    name: 'Crystal Caverns',
    biome: 'crystal-caverns',
    seed: 81,
    mapX: 2,
    mapY: 0,
    neighbors: {
      west: 'gloop-forest',
    },
  },
};

export function oppositeDirection(direction: Direction): Direction {
  switch (direction) {
    case 'north': return 'south';
    case 'east': return 'west';
    case 'south': return 'north';
    case 'west': return 'east';
  }
}
