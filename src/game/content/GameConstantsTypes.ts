import type { GameConstantsDocument } from './GameConstantsDocument.generated';

export type DeepReadonly<T> = T extends (...args: never[]) => unknown
  ? T
  : T extends readonly (infer Item)[]
    ? readonly DeepReadonly<Item>[]
    : T extends object
      ? { readonly [Key in keyof T]: DeepReadonly<T[Key]> }
      : T;

export type GameConstants = DeepReadonly<GameConstantsDocument>;
export type PlayerAttributeDefaults = GameConstants['character']['player']['initialAttributes'];
export type PlayerProgressionDefinition = GameConstants['character']['player']['progression'];
export type PlayerLevelDefinition = PlayerProgressionDefinition['levels'][number];
export type PlayerLevelGains = PlayerLevelDefinition['gains'];
