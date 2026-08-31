import type { GameStateData } from '../../core/GameState';
import type { InventorySlot } from '../../core/types';
import type { QuestState } from '../../content/quests/types';
import type { AreaId } from '../../world/Area';
import type { MapId } from '../../content/maps/mapFormat';
import { GAME_CONSTANTS } from '../../Constant';

export const SAVE_SCHEMA_VERSION = 8;
export const SAVE_NAME_MAX_LENGTH = 32;

export type FacingDirection = 'up' | 'down' | 'left' | 'right';

export interface GameLocationData {
  readonly areaId: AreaId;
  readonly mapId: MapId;
  readonly x: number;
  readonly y: number;
  readonly facing: FacingDirection;
}

export interface ResourcePileProgressData {
  id: string;
  cellX: number;
  cellY: number;
  amount: number;
  offsetX?: number;
  offsetY?: number;
  objectId?: string;
  visualId?: string;
}

export interface ResourceProgressStateData {
  readonly stage: 'node' | 'destroyed' | 'depleted';
  readonly value: number;
  readonly piles?: readonly ResourcePileProgressData[];
}

export interface CollectibleProgressStateData {
  readonly remaining: number;
  readonly sourceResourceInstanceId?: string;
}

export interface MapRuntimeStateData {
  readonly resources: Record<string, ResourceProgressStateData>;
  readonly collectibles?: Record<string, CollectibleProgressStateData>;
  readonly completedEncounterIds: readonly string[];
  readonly openedRewardIds: readonly string[];
  readonly unlockedGateIds: readonly string[];
  readonly objectStates: Record<string, unknown>;
}

export interface WorldProgressData {
  readonly discoveredAreas: readonly AreaId[];
  readonly defeatedBossIds: readonly string[];
  readonly completedDungeonIds: readonly string[];
  readonly maps: Record<string, MapRuntimeStateData>;
  /** Supported only as an input to the v4 → v5 migration. */
  readonly resourceStates?: Record<string, ResourceProgressStateData>;
}

export interface InventorySaveData {
  readonly maxSlots: number;
  readonly slots: readonly InventorySlot[];
}

export interface GameSaveData {
  readonly player: GameStateData;
  readonly inventory: InventorySaveData;
  readonly quests: readonly QuestState[];
  readonly location: GameLocationData;
  readonly world: WorldProgressData;
  readonly playTimeMs: number;
}

export interface StoredSave {
  readonly schemaVersion: number;
  readonly savedAt: number;
  readonly data: GameSaveData;
}

export interface NamedSaveMetadata {
  readonly saveId: string;
  readonly name: string;
  readonly createdAt: number;
  readonly updatedAt: number;
  readonly schemaVersion: number;
  readonly currentMapId: string;
  readonly playerLevel: number;
  readonly playTimeMs: number;
}

export interface NamedSaveSnapshot extends NamedSaveMetadata {
  readonly data: GameSaveData;
}

export interface SaveIndexEntry {
  readonly saveId: string;
  readonly name: string;
  readonly createdAt: number;
  readonly updatedAt: number;
  readonly schemaVersion: number;
  readonly currentMapId: string;
  readonly playerLevel: number;
  readonly playTimeMs: number;
}

export interface SaveValidationIssue {
  readonly saveId?: string;
  readonly reason: string;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function isNonNegativeNumber(value: unknown): value is number {
  return isFiniteNumber(value) && value >= 0;
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((entry) => typeof entry === 'string');
}

function isInventorySlots(value: unknown): value is InventorySlot[] {
  return Array.isArray(value) && value.every((entry) => {
    if (!isRecord(entry) || typeof entry.itemId !== 'string') return false;
    return typeof entry.count === 'number' && Number.isInteger(entry.count) && entry.count > 0;
  });
}

function isInventory(value: unknown): value is InventorySaveData {
  return isRecord(value)
    && Number.isInteger(value.maxSlots)
    && (value.maxSlots as number) > 0
    && isInventorySlots(value.slots)
    && value.slots.length <= (value.maxSlots as number);
}

function isQuests(value: unknown): value is QuestState[] {
  return Array.isArray(value) && value.every((entry) => {
    if (!isRecord(entry)
      || typeof entry.questId !== 'string'
      || !Number.isInteger(entry.definitionVersion)
      || (entry.definitionVersion as number) <= 0
      || !['locked', 'available', 'active', 'completed', 'failed', 'abandoned'].includes(entry.status as string)
      || !(entry.activeStageId === null || typeof entry.activeStageId === 'string')
      || !isRecord(entry.progress)
      || !Object.values(entry.progress).every((progress) => typeof progress === 'number' && Number.isInteger(progress) && progress >= 0)
      || typeof entry.rewardsGranted !== 'boolean'
      || entry.rewardsGranted !== (entry.status === 'completed')) return false;
    if (entry.consumedFactIds !== undefined && (!isRecord(entry.consumedFactIds)
      || !Object.values(entry.consumedFactIds).every((facts) => Array.isArray(facts) && facts.every((fact) => typeof fact === 'string')))) return false;
    return ['acceptedAt', 'completedAt', 'failedAt', 'abandonedAt'].every((field) => entry[field] === undefined || isFiniteNumber(entry[field]))
      && (entry.resumeStageId === undefined || typeof entry.resumeStageId === 'string');
  });
}

function isGameState(value: unknown): value is GameStateData {
  if (!isRecord(value)) return false;
  const equipment = value.equipment;
  const level = value.level;
  const levelEntry = Number.isInteger(level) && (level as number) >= 1 && (level as number) <= GAME_CONSTANTS.character.player.progression.maxLevel
    ? GAME_CONSTANTS.character.player.progression.levels[(level as number) - 1]
    : undefined;
  return value.schemaVersion === 3
    && isNonNegativeNumber(value.coins)
    && isFiniteNumber(value.boostBonus)
    && Number.isInteger(value.totalFriends)
    && levelEntry !== undefined
    && isNonNegativeNumber(value.currentXp)
    && (levelEntry.xpToNextLevel === null ? value.currentXp === 0 : (value.currentXp as number) < levelEntry.xpToNextLevel)
    && isNonNegativeNumber(value.hp)
    && isNonNegativeNumber(value.energy)
    && Number.isInteger(value.skillPoints)
    && isRecord(value.perks)
    && Object.values(value.perks).every((rank) => typeof rank === 'number' && Number.isInteger(rank) && rank >= 0)
    && isRecord(value.attributes)
    && Object.values(value.attributes).every((attribute) => isFiniteNumber(attribute) && attribute >= 0)
    && isRecord(equipment)
    && (equipment.weaponId === null || typeof equipment.weaponId === 'string')
    && Array.isArray(equipment.weaponSlots)
    && equipment.weaponSlots.length > 0
    && equipment.weaponSlots.every((slot) => slot === null || typeof slot === 'string');
}

function isResourceState(value: unknown): value is ResourceProgressStateData {
  if (!isRecord(value)) return false;
  if (!['node', 'destroyed', 'depleted'].includes(value.stage as string)) return false;
  if (!isNonNegativeNumber(value.value)) return false;
  if (value.piles === undefined) return true;
  return Array.isArray(value.piles) && value.piles.every((pile) => (
    isRecord(pile)
    && typeof pile.id === 'string'
    && Number.isInteger(pile.cellX)
    && Number.isInteger(pile.cellY)
    && isNonNegativeNumber(pile.amount)
    && (pile.offsetX === undefined || isFiniteNumber(pile.offsetX))
    && (pile.offsetY === undefined || isFiniteNumber(pile.offsetY))
    && (pile.objectId === undefined || typeof pile.objectId === 'string')
    && (pile.visualId === undefined || typeof pile.visualId === 'string')
  ));
}

function isMapRuntimeState(value: unknown): value is MapRuntimeStateData {
  return isRecord(value)
    && isRecord(value.resources)
    && Object.values(value.resources).every(isResourceState)
    && (value.collectibles === undefined || (isRecord(value.collectibles) && Object.values(value.collectibles).every((entry) => (
      isRecord(entry)
      && Number.isInteger(entry.remaining)
      && isNonNegativeNumber(entry.remaining)
      && (entry.sourceResourceInstanceId === undefined || typeof entry.sourceResourceInstanceId === 'string')
    ))))
    && isStringArray(value.completedEncounterIds)
    && isStringArray(value.openedRewardIds)
    && isStringArray(value.unlockedGateIds)
    && isRecord(value.objectStates);
}

export function isGameSaveData(value: unknown): value is GameSaveData {
  if (!isRecord(value) || !isGameState(value.player) || !isInventory(value.inventory) || !isQuests(value.quests)) {
    return false;
  }
  const location = value.location;
  const world = value.world;
  if (!isRecord(location) || typeof location.areaId !== 'string' || typeof location.mapId !== 'string'
    || !isFiniteNumber(location.x) || !isFiniteNumber(location.y)
    || !['up', 'down', 'left', 'right'].includes(location.facing as string)) return false;
  if (!isRecord(world) || !isStringArray(world.discoveredAreas)
    || !isStringArray(world.defeatedBossIds) || !isStringArray(world.completedDungeonIds)
    || !isRecord(world.maps) || !Object.values(world.maps).every(isMapRuntimeState)) return false;
  return isNonNegativeNumber(value.playTimeMs);
}
