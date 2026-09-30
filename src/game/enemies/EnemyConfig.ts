import type { AssetId } from '../infrastructure/assets/manifest';
import type { EnemyEffectImmunity } from '../content/enemies/EnemyEffects';
import type { EnemyAIConfig } from './EnemyAI';

export interface EnemyItemDrop {
  itemId: string;
  chance: number;
  count?: number;
}

export interface EnemyDrop {
  coins: number;
  items?: readonly EnemyItemDrop[];
}

export interface EnemyConfig {
  id: string;
  visualSetId: string;
  maxHp: number;
  effectImmunities?: readonly EnemyEffectImmunity[];
  body: {
    shape?: 'rectangle' | 'circle' | 'ellipse';
    width: number;
    height: number;
    radius?: number;
    radiusX?: number;
    radiusY?: number;
    centerOffsetX: number;
    centerOffsetY: number;
  };
  ai: EnemyAIConfig;
  drop: EnemyDrop;
  projectile?: {
    projectileId?: string;
    assetId?: AssetId;
    damage: number;
  };
  impactEffect?: {
    visualSetId: string;
    clipId: string;
    distance: number;
  };
}
