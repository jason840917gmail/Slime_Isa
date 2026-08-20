import type { GameStateData } from '../../core/GameState';
import type { InventorySlot } from '../../core/types';
import type { QuestState } from '../../quests/Quest';
import type { AreaId } from '../../world/Area';

export const SAVE_SCHEMA_VERSION = 4;

export interface ResourcePileProgressData {
  id: string;
  cellX: number;
  cellY: number;
  amount: number;
}

export interface ResourceProgressStateData {
  stage: 'node' | 'pile' | 'destroyed' | 'depleted';
  value: number;
  piles?: ResourcePileProgressData[];
}

export interface WorldProgressData {
  discoveredAreas: AreaId[];
  defeatedBossIds: string[];
  completedDungeonIds: string[];
  resourceStates?: Record<string, ResourceProgressStateData>;
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
