import type { GameStateData } from '../../core/GameState';
import type { QuestState } from '../../content/quests/types';
import type { QuestState as LegacyQuestState } from '../../quests/Quest';
import { getQuestDefinition } from '../../content/quests/QuestCatalog';
import type { AreaId } from '../../world/Area';
import { createInitialRunState, initialLocation } from '../../content/initial-state/InitialRun';
import {
  SAVE_NAME_MAX_LENGTH,
  SAVE_SCHEMA_VERSION,
  isGameSaveData,
  isRecord,
  type GameSaveData,
  type CollectibleProgressStateData,
  type MapRuntimeStateData,
  type NamedSaveMetadata,
  type NamedSaveSnapshot,
  type ResourceProgressStateData,
  type SaveIndexEntry,
  type SaveValidationIssue,
  type StoredSave,
  type WorldProgressData,
} from './SaveSchema';
import { STORAGE_KEYS } from './storageKeys';
import { GAME_CONSTANTS } from '../../Constant';
import { migratePlayerProgression } from './PlayerProgressionMigration';

interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export class SaveRepositoryError extends Error {
  constructor(message: string, public readonly saveId?: string) {
    super(message);
    this.name = 'SaveRepositoryError';
  }
}

class SaveMigrationError extends Error {
  constructor(message: string) {
    super(`${message} The original save was left unchanged.`);
    this.name = 'SaveMigrationError';
  }
}

function storageOrNull(): StorageLike | null {
  try {
    return typeof localStorage === 'undefined' ? null : localStorage;
  } catch {
    return null;
  }
}

function clone<T>(value: T): T {
  return structuredClone(value);
}

function isAreaId(value: unknown): value is AreaId {
  return typeof value === 'string' && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(value);
}

function isString(value: unknown): value is string {
  return typeof value === 'string';
}

function isLegacyQuestState(value: unknown): value is LegacyQuestState {
  return isRecord(value)
    && typeof value.id === 'string'
    && (value.status === 'active' || value.status === 'completed')
    && isRecord(value.progress)
    && Object.values(value.progress).every((progress) => typeof progress === 'number' && Number.isFinite(progress));
}

function parseArray<T>(storage: StorageLike | null, key: string, guard: (value: unknown) => value is T): T[] {
  try {
    const raw = storage?.getItem(key);
    const values = raw ? JSON.parse(raw) as unknown : [];
    return Array.isArray(values) ? values.filter(guard) : [];
  } catch {
    return [];
  }
}

function emptyWorld(): WorldProgressData {
  return { discoveredAreas: [], defeatedBossIds: [], completedDungeonIds: [], maps: {} };
}

function isResourceState(value: unknown): value is ResourceProgressStateData {
  return isRecord(value)
    && ['node', 'destroyed', 'depleted'].includes(value.stage as string)
    && typeof value.value === 'number'
    && Number.isFinite(value.value)
    && value.value >= 0;
}

function mapWorld(value: unknown, storage: StorageLike | null): WorldProgressData {
  if (!isRecord(value)) return { ...emptyWorld(), ...readLegacyWorld(storage) };
  const discoveredAreas = Array.isArray(value.discoveredAreas) ? value.discoveredAreas.filter(isAreaId) : [];
  const defeatedBossIds = Array.isArray(value.defeatedBossIds) ? value.defeatedBossIds.filter(isString) : [];
  const completedDungeonIds = Array.isArray(value.completedDungeonIds) ? value.completedDungeonIds.filter(isString) : [];
  const maps: Record<string, MapRuntimeStateData> = {};
  if (isRecord(value.maps)) {
    for (const [mapId, candidate] of Object.entries(value.maps)) {
      if (!isRecord(candidate)) continue;
      const resources: Record<string, ResourceProgressStateData> = {};
      if (isRecord(candidate.resources)) {
        for (const [instanceId, resource] of Object.entries(candidate.resources)) {
          if (isResourceState(resource)) resources[instanceId] = clone(resource);
        }
      }
      const collectibles: Record<string, CollectibleProgressStateData> = {};
      if (isRecord(candidate.collectibles)) {
        for (const [instanceId, collectible] of Object.entries(candidate.collectibles)) {
          if (isRecord(collectible)
            && typeof collectible.remaining === 'number'
            && Number.isFinite(collectible.remaining)
            && Number.isInteger(collectible.remaining)
            && collectible.remaining >= 0) {
            collectibles[instanceId] = {
              remaining: collectible.remaining,
              ...(typeof collectible.sourceResourceInstanceId === 'string'
                ? { sourceResourceInstanceId: collectible.sourceResourceInstanceId } : {}),
            };
          }
        }
      }
      maps[mapId] = {
        resources,
        collectibles,
        completedEncounterIds: Array.isArray(candidate.completedEncounterIds) ? candidate.completedEncounterIds.filter(isString) : [],
        openedRewardIds: Array.isArray(candidate.openedRewardIds) ? candidate.openedRewardIds.filter(isString) : [],
        unlockedGateIds: Array.isArray(candidate.unlockedGateIds) ? candidate.unlockedGateIds.filter(isString) : [],
        objectStates: isRecord(candidate.objectStates) ? clone(candidate.objectStates) : {},
      };
    }
  }
  if (isRecord(value.resourceStates)) {
    for (const [key, resource] of Object.entries(value.resourceStates)) {
      const divider = key.indexOf(':');
      if (divider <= 0 || divider === key.length - 1 || !isResourceState(resource)) continue;
      const mapId = key.slice(0, divider);
      const instanceId = key.slice(divider + 1);
      const map = maps[mapId] ?? {
        resources: {}, collectibles: {}, completedEncounterIds: [], openedRewardIds: [], unlockedGateIds: [], objectStates: {},
      };
      map.resources[instanceId] = clone(resource);
      maps[mapId] = map;
    }
  }
  return { discoveredAreas, defeatedBossIds, completedDungeonIds, maps };
}

function isRuntimeQuestState(value: unknown): value is QuestState {
  return isRecord(value)
    && typeof value.questId === 'string'
    && Number.isInteger(value.definitionVersion)
    && (value.definitionVersion as number) > 0
    && ['locked', 'available', 'active', 'completed', 'failed', 'abandoned'].includes(value.status as string)
    && (value.activeStageId === null || typeof value.activeStageId === 'string')
    && isRecord(value.progress)
    && Object.values(value.progress).every((progress) => typeof progress === 'number' && Number.isInteger(progress) && progress >= 0)
    && typeof value.rewardsGranted === 'boolean';
}

function migrateLegacyQuestState(state: LegacyQuestState): QuestState | undefined {
  const definition = getQuestDefinition(state.id);
  if (!definition) return undefined;
  const objectives = definition.stages.flatMap((stage) => stage.objectives);
  const knownObjectiveIds = new Set(objectives.map((objective) => objective.id));
  const progress = Object.fromEntries(Object.entries(state.progress)
    .filter(([objectiveId]) => knownObjectiveIds.has(objectiveId))
    .map(([objectiveId, value]) => [
      objectiveId,
      Math.min(objectives.find((objective) => objective.id === objectiveId)!.target, Math.max(0, Math.floor(value))),
    ]));
  const activeStageId = state.status === 'completed'
    ? null
    : definition.stages.find((stage) => stage.objectives.some((objective) => (progress[objective.id] ?? 0) < objective.target))?.id
      ?? definition.stages.at(-1)!.id;
  return {
    questId: state.id,
    definitionVersion: definition.definitionVersion,
    status: state.status,
    activeStageId,
    progress,
    consumedFactIds: {},
    ...(state.completedAt === undefined ? {} : { completedAt: state.completedAt }),
    rewardsGranted: state.status === 'completed',
  };
}

function migrateLegacyInventory(value: unknown): Array<{ itemId: string; count: number }> | undefined {
  if (!Array.isArray(value)) return undefined;
  return value.map((slot, index) => {
    const label = `Inventory slot ${index + 1} was rejected`;
    if (!isRecord(slot)) throw new SaveMigrationError(`${label}: expected an item object.`);
    if (typeof slot.itemId !== 'string' || slot.itemId.length === 0) {
      throw new SaveMigrationError(`${label}: "itemId" must be a non-empty string.`);
    }
    if (typeof slot.count !== 'number' || !Number.isFinite(slot.count) || !Number.isInteger(slot.count) || slot.count <= 0) {
      throw new SaveMigrationError(`${label}: "count" must be a positive whole number.`);
    }
    return { itemId: slot.itemId, count: slot.count };
  });
}

function migrateData(value: unknown, storage: StorageLike | null): GameSaveData | null {
  if (!isRecord(value)) return null;
  const initial = createInitialRunState();
  const player = isRecord(value.player) ? value.player as Partial<GameStateData> : value as Partial<GameStateData>;
  if (!isRecord(player) || typeof player.level !== 'number') return null;
  let progression: { level: number; currentXp: number };
  try {
    progression = 'currentXp' in player
      ? { level: player.level, currentXp: player.currentXp as number }
      : migratePlayerProgression(GAME_CONSTANTS.character.player.progression, player.level, (player as Record<string, unknown>).xp);
  } catch {
    return null;
  }
  const { xp: _xp, maxHpBonus: _maxHpBonus, maxEnergyBonus: _maxEnergyBonus, ...playerWithoutLegacyProgression } = player as Record<string, unknown>;
  const legacySlots = migrateLegacyInventory(value.inventory);
  const candidate: GameSaveData = {
    player: clone({ ...initial.player, ...playerWithoutLegacyProgression, ...progression, schemaVersion: 3 } as unknown as GameStateData),
    inventory: legacySlots
      ? { maxSlots: Math.max(initial.inventory.maxSlots, legacySlots.length), slots: clone(legacySlots) }
      : isRecord(value.inventory) ? clone(value.inventory) as unknown as GameSaveData['inventory'] : initial.inventory,
    quests: Array.isArray(value.quests)
      ? value.quests.flatMap((quest) => {
          if (isRuntimeQuestState(quest)) return [clone(quest)];
          if (isLegacyQuestState(quest)) {
            const migrated = migrateLegacyQuestState(quest);
            if (!migrated) throw new SaveMigrationError(`Quest '${quest.id}' is no longer present in the authored catalog.`);
            return [migrated];
          }
          throw new SaveMigrationError('A saved quest entry has an unsupported shape.');
        })
      : initial.quests,
    location: isRecord(value.location)
      && typeof value.location.areaId === 'string'
      && typeof value.location.mapId === 'string'
      && typeof value.location.x === 'number'
      && typeof value.location.y === 'number'
      && ['up', 'down', 'left', 'right'].includes(value.location.facing as string)
      ? {
          areaId: value.location.areaId,
          mapId: value.location.mapId,
          x: value.location.x,
          y: value.location.y,
          facing: value.location.facing as 'up' | 'down' | 'left' | 'right',
        }
      : initialLocation(),
    world: mapWorld(value.world, storage),
    playTimeMs: typeof value.playTimeMs === 'number' && Number.isFinite(value.playTimeMs) ? Math.max(0, value.playTimeMs) : 0,
  };
  return isGameSaveData(candidate) ? candidate : null;
}

function readLegacyWorld(storage: StorageLike | null): WorldProgressData {
  return {
    discoveredAreas: parseArray(storage, STORAGE_KEYS.legacyDiscoveredAreas, isAreaId),
    defeatedBossIds: parseArray(storage, STORAGE_KEYS.legacyDefeatedBosses, isString),
    completedDungeonIds: parseArray(storage, STORAGE_KEYS.legacyCompletedDungeons, isString),
    maps: {},
  };
}

function isMetadata(value: unknown): value is NamedSaveMetadata {
  return isRecord(value)
    && typeof value.saveId === 'string'
    && typeof value.name === 'string'
    && value.name.trim().length > 0
    && typeof value.createdAt === 'number'
    && Number.isFinite(value.createdAt)
    && typeof value.updatedAt === 'number'
    && Number.isFinite(value.updatedAt)
    && Number.isInteger(value.schemaVersion)
    && (value.schemaVersion as number) > 0
    && (value.schemaVersion as number) <= SAVE_SCHEMA_VERSION
    && typeof value.currentMapId === 'string'
    && Number.isInteger(value.playerLevel)
    && typeof value.playTimeMs === 'number'
    && Number.isFinite(value.playTimeMs);
}

function readIndex(storage: StorageLike | null): SaveIndexEntry[] {
  if (!storage) return [];
  try {
    const raw = storage.getItem(STORAGE_KEYS.saveIndex);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as unknown;
    const values = Array.isArray(parsed) ? parsed : isRecord(parsed) && Array.isArray(parsed.saves) ? parsed.saves : [];
    return values.filter(isMetadata).map((entry) => ({ ...entry }));
  } catch {
    return [];
  }
}

export class SaveRepository {
  private readonly storage: StorageLike | null;
  private issues: SaveValidationIssue[] = [];

  constructor(storage: StorageLike | null = storageOrNull()) {
    this.storage = storage;
  }

  list(): readonly NamedSaveMetadata[] {
    this.issues = [];
    const records: NamedSaveMetadata[] = [];
    for (const indexEntry of readIndex(this.storage)) {
      const snapshot = this.read(indexEntry.saveId);
      if (!snapshot) continue;
      records.push({
        saveId: snapshot.saveId,
        name: snapshot.name,
        createdAt: snapshot.createdAt,
        updatedAt: snapshot.updatedAt,
        schemaVersion: snapshot.schemaVersion,
        currentMapId: snapshot.currentMapId,
        playerLevel: snapshot.playerLevel,
        playTimeMs: snapshot.playTimeMs,
      });
    }
    return records.sort((a, b) => b.updatedAt - a.updatedAt);
  }

  validationIssues(): readonly SaveValidationIssue[] {
    return [...this.issues];
  }

  create(name: string, data: GameSaveData): NamedSaveMetadata {
    const normalizedName = this.validateName(name);
    this.assertData(data);
    const existing = this.list().find((entry) => entry.name.toLocaleLowerCase() === normalizedName.toLocaleLowerCase());
    if (existing) throw new SaveRepositoryError(`A save named '${existing.name}' already exists.`, existing.saveId);
    const now = Date.now();
    const metadata: NamedSaveMetadata = {
      saveId: this.newId(), name: normalizedName, createdAt: now, updatedAt: now,
      schemaVersion: SAVE_SCHEMA_VERSION, currentMapId: data.location.mapId,
      playerLevel: data.player.level, playTimeMs: data.playTimeMs,
    };
    const snapshot: NamedSaveSnapshot = { ...metadata, data: clone(data) };
    const key = this.recordKey(metadata.saveId);
    if (!this.storage) throw new SaveRepositoryError('Browser storage is unavailable.');
    try {
      this.storage.setItem(key, JSON.stringify(snapshot));
      this.writeIndex([...readIndex(this.storage), metadata]);
      return metadata;
    } catch (error) {
      try { this.storage.removeItem(key); } catch { /* best effort rollback */ }
      if (error instanceof SaveRepositoryError) throw error;
      throw new SaveRepositoryError('The new save could not be written.');
    }
  }

  overwrite(saveId: string, data: GameSaveData): NamedSaveMetadata {
    this.assertData(data);
    const previous = this.read(saveId);
    if (!previous) throw new SaveRepositoryError(`Save '${saveId}' could not be read.`, saveId);
    if (!this.storage) throw new SaveRepositoryError('Browser storage is unavailable.', saveId);
    const metadata: NamedSaveMetadata = {
      saveId: previous.saveId,
      name: previous.name,
      createdAt: previous.createdAt,
      updatedAt: Date.now(),
      schemaVersion: previous.schemaVersion,
      currentMapId: data.location.mapId,
      playerLevel: data.player.level, playTimeMs: data.playTimeMs,
    };
    const key = this.recordKey(saveId);
    const oldRaw = this.storage.getItem(key);
    try {
      this.storage.setItem(key, JSON.stringify({ ...metadata, data: clone(data) } satisfies NamedSaveSnapshot));
      this.writeIndex(readIndex(this.storage).map((entry) => entry.saveId === saveId ? metadata : entry));
      return metadata;
    } catch (error) {
      try {
        if (oldRaw === null) this.storage.removeItem(key);
        else this.storage.setItem(key, oldRaw);
      } catch { /* best effort rollback */ }
      if (error instanceof SaveRepositoryError) throw error;
      throw new SaveRepositoryError('The existing save could not be overwritten.', saveId);
    }
  }

  read(saveId: string): NamedSaveSnapshot | null {
    if (!this.storage) return null;
    const raw = this.storage.getItem(this.recordKey(saveId));
    if (!raw) return null;
    try {
      const parsed = JSON.parse(raw) as unknown;
      if (!isRecord(parsed) || parsed.saveId !== saveId || !isMetadata(parsed)) {
        this.issues.push({ saveId, reason: 'The snapshot failed schema validation.' });
        return null;
      }
      const data = isGameSaveData(parsed.data) ? clone(parsed.data) : migrateData(parsed.data, this.storage);
      if (!data) {
        this.issues.push({ saveId, reason: 'The snapshot failed schema validation.' });
        return null;
      }
      return {
        saveId,
        name: parsed.name as string,
        createdAt: parsed.createdAt as number,
        updatedAt: parsed.updatedAt as number,
        schemaVersion: SAVE_SCHEMA_VERSION,
        currentMapId: data.location.mapId,
        playerLevel: data.player.level,
        playTimeMs: data.playTimeMs,
        data,
      };
    } catch (error) {
      this.issues.push({
        saveId,
        reason: error instanceof SaveMigrationError
          ? error.message
          : 'The snapshot contains invalid JSON.',
      });
      return null;
    }
  }

  delete(saveId: string): boolean {
    if (!this.storage) return false;
    const index = readIndex(this.storage);
    if (!index.some((entry) => entry.saveId === saveId)) return false;
    const key = this.recordKey(saveId);
    const oldRaw = this.storage.getItem(key);
    try {
      this.storage.removeItem(key);
      this.writeIndex(index.filter((entry) => entry.saveId !== saveId));
      return true;
    } catch {
      try { if (oldRaw !== null) this.storage.setItem(key, oldRaw); } catch { /* best effort rollback */ }
      return false;
    }
  }

  readRecovery(): GameSaveData | null {
    this.issues = this.issues.filter((issue) => issue.saveId !== undefined);
    if (this.storage?.getItem(STORAGE_KEYS.recovery) !== null) {
      return this.readStoredEnvelope(STORAGE_KEYS.recovery)?.data ?? null;
    }
    const migrated = this.readLegacyEnvelope();
    if (!migrated) return null;
    return this.writeRecovery(migrated.data) ? migrated.data : null;
  }

  hasRecovery(): boolean {
    try {
      if (!this.storage) return false;
      return this.storage.getItem(STORAGE_KEYS.recovery) !== null
        || this.storage.getItem(STORAGE_KEYS.legacySave) !== null;
    } catch {
      return false;
    }
  }

  writeRecovery(data: GameSaveData): boolean {
    try {
      this.assertData(data);
      if (!this.storage) return false;
      this.storage.setItem(STORAGE_KEYS.recovery, JSON.stringify({
        schemaVersion: SAVE_SCHEMA_VERSION, savedAt: Date.now(), data: clone(data),
      } satisfies StoredSave));
      return true;
    } catch {
      return false;
    }
  }

  clearRecovery(): void {
    try { this.storage?.removeItem(STORAGE_KEYS.recovery); } catch { /* best effort */ }
  }

  markLegacyMigrationComplete(): void {
    try {
      if (!this.storage) return;
      this.storage.setItem(STORAGE_KEYS.migrationComplete, '1');
      this.storage.removeItem(STORAGE_KEYS.legacySave);
    } catch {
      // Keep legacy data when cleanup cannot be completed.
    }
  }

  readLegacyEnvelope(): StoredSave | null {
    if (!this.storage) return null;
    try {
      const raw = this.storage.getItem(STORAGE_KEYS.legacySave);
      if (!raw) return null;
      const parsed = JSON.parse(raw) as unknown;
      if (!isRecord(parsed) || !isRecord(parsed.data)) return null;
      const data = migrateData(parsed.data, this.storage);
      return data ? {
        schemaVersion: SAVE_SCHEMA_VERSION,
        savedAt: typeof parsed.savedAt === 'number' ? parsed.savedAt : Date.now(),
        data,
      } : null;
    } catch (error) {
      if (error instanceof SaveMigrationError) this.issues.push({ reason: error.message });
      return null;
    }
  }

  readLegacyQuests(): LegacyQuestState[] {
    return parseArray(this.storage, STORAGE_KEYS.legacyQuests, isLegacyQuestState);
  }

  readLegacyWorld(): WorldProgressData {
    return readLegacyWorld(this.storage);
  }

  write(data: GameSaveData, slot = STORAGE_KEYS.legacySave): boolean {
    try {
      this.assertData(data);
      if (!this.storage) return false;
      this.storage.setItem(slot, JSON.stringify({ schemaVersion: SAVE_SCHEMA_VERSION, savedAt: Date.now(), data: clone(data) } satisfies StoredSave));
      return true;
    } catch {
      return false;
    }
  }

  readLegacy(slot = STORAGE_KEYS.legacySave): StoredSave | null {
    if (slot !== STORAGE_KEYS.legacySave) return null;
    return this.readLegacyEnvelope();
  }

  remove(slot = STORAGE_KEYS.legacySave): void {
    try { this.storage?.removeItem(slot); } catch { /* best effort */ }
  }

  patch(patch: Partial<GameSaveData>, slot = STORAGE_KEYS.legacySave): boolean {
    const current = this.readLegacy(slot);
    if (!current) return false;
    return this.write({ ...current.data, ...patch }, slot);
  }

  private readStoredEnvelope(key: string): StoredSave | null {
    if (!this.storage) return null;
    try {
      const raw = this.storage.getItem(key);
      if (!raw) return null;
      const parsed = JSON.parse(raw) as unknown;
      if (!isRecord(parsed)) {
        this.issues.push({ reason: 'The recovery record failed schema validation.' });
        return null;
      }
      const data = isGameSaveData(parsed.data) ? clone(parsed.data) : migrateData(parsed.data, this.storage);
      if (!data) {
        this.issues.push({ reason: 'The recovery record failed schema validation.' });
        return null;
      }
      return {
        schemaVersion: SAVE_SCHEMA_VERSION,
        savedAt: typeof parsed.savedAt === 'number' ? parsed.savedAt : Date.now(),
        data,
      };
    } catch (error) {
      this.issues.push({
        reason: error instanceof SaveMigrationError
          ? error.message
          : 'The recovery record contains invalid JSON.',
      });
      return null;
    }
  }

  private validateName(name: string): string {
    const normalized = name.trim();
    if (!normalized) throw new SaveRepositoryError('Enter a name for this save.');
    if (normalized.length > SAVE_NAME_MAX_LENGTH) throw new SaveRepositoryError(`Save names must be ${SAVE_NAME_MAX_LENGTH} characters or fewer.`);
    return normalized;
  }

  private assertData(data: GameSaveData): void {
    if (!isGameSaveData(data)) throw new SaveRepositoryError('The current run could not be validated.');
  }

  private recordKey(saveId: string): string {
    return `${STORAGE_KEYS.saveRecordPrefix}${saveId}`;
  }

  private writeIndex(entries: readonly SaveIndexEntry[]): void {
    if (!this.storage) throw new SaveRepositoryError('Browser storage is unavailable.');
    this.storage.setItem(STORAGE_KEYS.saveIndex, JSON.stringify({ version: 1, saves: entries }));
  }

  private newId(): string {
    try {
      if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
    } catch { /* use fallback */ }
    return `save-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
  }
}

export const saveRepository = new SaveRepository();
