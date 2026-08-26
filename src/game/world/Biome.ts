export type BiomeId = 'icege' | 'meadow' | 'gloop-forest' | 'crystal-caverns';

export interface BiomeDef {
  id: BiomeId;
  name: string;
  titleColor: string;
  ambientTint: number;
  decorationBias: number;
}

export const BIOMES: Readonly<Record<BiomeId, BiomeDef>> = {
  icege: {
    id: 'icege',
    name: 'Icege',
    titleColor: '#bcecff',
    ambientTint: 0xe5f5ff,
    decorationBias: 0.8,
  },
  meadow: {
    id: 'meadow',
    name: 'Meadow',
    titleColor: '#a3f0c0',
    ambientTint: 0xffffff,
    decorationBias: 1,
  },
  'gloop-forest': {
    id: 'gloop-forest',
    name: 'Gloop Forest',
    titleColor: '#8cff9a',
    ambientTint: 0xd8ffd8,
    decorationBias: 1.2,
  },
  'crystal-caverns': {
    id: 'crystal-caverns',
    name: 'Crystal Caverns',
    titleColor: '#9ad8ff',
    ambientTint: 0xddeaff,
    decorationBias: 0.7,
  },
};
