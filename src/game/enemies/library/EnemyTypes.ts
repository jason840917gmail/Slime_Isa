import enemyTypesJson from '../../content/enemies/enemy-types.json';
import type { EnemyConfig } from '../Enemy';

export type EnemyTypeId = keyof typeof enemyTypesJson.types;

/** The only active enemy catalog. Maps and the editor persist these IDs. */
export const ENEMY_CONFIGS = enemyTypesJson.types as unknown as Readonly<
  Record<EnemyTypeId, EnemyConfig>
>;

export const ENEMY_TYPE_IDS = Object.keys(ENEMY_CONFIGS) as EnemyTypeId[];

export function getEnemyConfig(id: string): EnemyConfig {
  const config = (ENEMY_CONFIGS as Readonly<Record<string, EnemyConfig | undefined>>)[id];
  if (!config) {
    throw new Error(`Unknown enemy type '${id}'. Expected one of: ${ENEMY_TYPE_IDS.join(', ')}`);
  }
  return config;
}
