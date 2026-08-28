import rawConstants from './content/game-constants.json';
import { normalizeGameConstants } from './content/GameConstantsValidation';
import type { DeepReadonly, GameConstants } from './content/GameConstantsTypes';

export type {
  DeepReadonly,
  GameConstants,
  PlayerAttributeDefaults,
  PlayerLevelDefinition,
  PlayerLevelGains,
  PlayerProgressionDefinition,
} from './content/GameConstantsTypes';

function deepFreeze<T>(value: T): DeepReadonly<T> {
  if (value !== null && typeof value === 'object' && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value as DeepReadonly<T>;
}

export const GAME_CONSTANTS: DeepReadonly<GameConstants> = deepFreeze(normalizeGameConstants(rawConstants));
