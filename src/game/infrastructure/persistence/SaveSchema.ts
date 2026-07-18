import type { GameStateData } from '../../core/GameState';
import type { InventorySlot } from '../../core/types';
import type { QuestState } from '../../quests/Quest';
import type { AreaId } from '../../world/Area';

export const SAVE_SCHEMA_VERSION = 2;

export interface WorldProgressData {
  discoveredAreas: AreaId[];
  defeatedBossIds: string[];
  completedDungeonIds: string[];
}

export interface GameSaveData {
  player: GameStateData;
  inventory: InventorySlot[];
  quests: QuestState[];
  world: WorldProgressData;
}

export interface StoredSave {
  schemaVersion: number;
  savedAt: number;
  data: GameSaveData;
}
