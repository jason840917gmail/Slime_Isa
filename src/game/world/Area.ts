import type { BiomeId } from './Biome';
import type { MapId } from '../content/maps/mapFormat';

export type AreaId = string;
export type Direction = 'north' | 'east' | 'south' | 'west';

export interface AreaDef {
  id: AreaId;
  name: string;
  biome: BiomeId;
  seed: number;
  mapX: number;
  mapY: number;
  /** Authored map to load for this area. Distinct from AreaId so interiors
   *  and alternate maps can exist later; mapId === area.id in v1. */
  mapId: MapId;
  hasPlayerHome?: boolean;
  neighbors: Partial<Record<Direction, AreaId>>;
}

export const AREAS: Readonly<Record<string, AreaDef>> = {
  icege: {
    id: 'icege',
    name: 'Icege',
    biome: 'icege',
    seed: 113,
    mapX: -1,
    mapY: 0,
    mapId: 'icege',
    neighbors: {
      east: 'meadow-crossing',
    },
  },
  'meadow-crossing': {
    id: 'meadow-crossing',
    name: 'Sunbell Meadow',
    biome: 'meadow',
    seed: 0,
    mapX: 0,
    mapY: 0,
    mapId: 'meadow-crossing',
    hasPlayerHome: true,
    neighbors: {
      west: 'icege',
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
    mapId: 'gloop-forest',
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
    mapId: 'crystal-caverns',
    neighbors: {
      west: 'gloop-forest',
    },
  },
};

/** Lets newly authored maps participate in navigation before bespoke world-map
 * metadata is assigned. Known production areas still use their curated data. */
export function getAreaDefinition(areaId: AreaId): AreaDef {
  return AREAS[areaId] ?? {
    id: areaId,
    name: areaId.split('-').map((part) => `${part[0]?.toUpperCase() ?? ''}${part.slice(1)}`).join(' '),
    biome: 'meadow',
    seed: [...areaId].reduce((hash, character) => ((hash * 31) + character.charCodeAt(0)) >>> 0, 0),
    mapX: 0,
    mapY: 0,
    mapId: areaId,
    neighbors: {},
  };
}
