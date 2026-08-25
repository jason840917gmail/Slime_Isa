import type { GameStateData } from '../../core/GameState';
import type { QuestState } from '../../quests/Quest';
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

function isQuestState(value: unknown): value is QuestState {
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
    && ['node', 'pile', 'destroyed', 'depleted'].includes(value.stage as string)
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

function migrateData(value: unknown, storage: StorageLike | null): GameSaveData | null {
  if (!isRecord(value)) return null;
  const initial = createInitialRunState();
  const player = isRecord(value.player) ? value.player as Partial<GameStateData> : value as Partial<GameStateData>;
  if (!isRecord(player) || typeof player.level !== 'number') return null;
  const candidate: GameSaveData = {
    player: clone({ ...initial.player, ...player } as GameStateData),
    inventory: Array.isArray(value.inventory)
      ? clone(value.inventory.filter((slot): slot is { itemId: string; count: number } => (
          isRecord(slot) && typeof slot.itemId === 'string'
          && typeof slot.count === 'number' && Number.isInteger(slot.count) && slot.count > 0
        )))
      : initial.inventory,
    quests: Array.isArray(value.quests) ? clone(value.quests.filter(isQuestState)) : initial.quests,
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
    && value.schemaVersion === SAVE_SCHEMA_VERSION
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
      if (!isRecord(parsed) || parsed.saveId !== saveId || !isMetadata(parsed) || !isGameSaveData(parsed.data)) {
        this.issues.push({ saveId, reason: 'The snapshot failed schema validation.' });
        return null;
      }
      return clone(parsed) as unknown as NamedSaveSnapshot;
    } catch {
      this.issues.push({ saveId, reason: 'The snapshot contains invalid JSON.' });
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
    const recovery = this.readStoredEnvelope(STORAGE_KEYS.recovery);
    if (recovery) return recovery.data;
    const migrated = this.readLegacyEnvelope();
    if (!migrated) return null;
    return this.writeRecovery(migrated.data) ? migrated.data : null;
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
    } catch {
      return null;
    }
  }

  readLegacyQuests(): QuestState[] {
    return parseArray(this.storage, STORAGE_KEYS.legacyQuests, isQuestState);
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
      if (!isRecord(parsed) || !isGameSaveData(parsed.data)) {
        this.issues.push({ reason: 'The recovery record failed schema validation.' });
        return null;
      }
      return { schemaVersion: SAVE_SCHEMA_VERSION, savedAt: Date.now(), data: clone(parsed.data) };
    } catch {
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
