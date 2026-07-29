import type { EnemyConfig } from '../Enemy';
import type { AssetId } from '../../infrastructure/assets/manifest';
import { getEnemyGameplay, getEnemyPackages } from '../../content/characters/CharacterCatalog';

const enemyEntries = getEnemyPackages().map((entry) => {
  const gameplay = getEnemyGameplay(entry.character);
  return [entry.character.characterId, {
    id: entry.character.characterId,
    visualSetId: entry.character.visualSetId,
    maxHp: gameplay.maxHp,
    body: entry.character.body,
    ai: gameplay.ai,
    drop: gameplay.drop,
    projectile: gameplay.projectile
      ? {
        damage: gameplay.projectile.damage,
        ...(gameplay.projectile.projectileId ? { projectileId: gameplay.projectile.projectileId } : {}),
        ...(gameplay.projectile.assetId ? { assetId: gameplay.projectile.assetId as AssetId } : {}),
      }
      : undefined,
    impactEffect: gameplay.impactEffect,
  } satisfies EnemyConfig] as const;
});

export const ENEMY_CONFIGS = Object.fromEntries(enemyEntries) as Readonly<Record<string, EnemyConfig>>;
export type EnemyTypeId = keyof typeof ENEMY_CONFIGS;
export const ENEMY_TYPE_IDS = Object.keys(ENEMY_CONFIGS) as EnemyTypeId[];

export function getEnemyConfig(id: string): EnemyConfig {
  const config = ENEMY_CONFIGS[id];
  if (!config) throw new Error(`Unknown enemy type '${id}'. Expected one of: ${ENEMY_TYPE_IDS.join(', ')}`);
  return config;
}
