import type { GameStateData } from '../../core/GameState';
import type { QuestState } from '../../quests/Quest';
import { AREAS, type AreaId } from '../../world/Area';
import { SAVE_SCHEMA_VERSION, type GameSaveData, type StoredSave, type WorldProgressData } from './SaveSchema';
import { STORAGE_KEYS } from './storageKeys';

type LegacySave = {
  schemaVersion?: number;
  savedAt?: number;
  data?: GameStateData | GameSaveData;
};

function parseArray<T>(key: string, guard: (value: unknown) => value is T): T[] {
  try {
    const raw = localStorage.getItem(key);
    const values = raw ? JSON.parse(raw) as unknown : [];
    return Array.isArray(values) ? values.filter(guard) : [];
  } catch {
    return [];
  }
}

function isAreaId(value: unknown): value is AreaId {
  return typeof value === 'string' && value in AREAS;
}

function isString(value: unknown): value is string {
  return typeof value === 'string';
}

function isQuestState(value: unknown): value is QuestState {
  if (!value || typeof value !== 'object') return false;
  const candidate = value as Partial<QuestState>;
  return typeof candidate.id === 'string'
    && (candidate.status === 'active' || candidate.status === 'completed')
    && !!candidate.progress
    && typeof candidate.progress === 'object';
}

class SaveRepository {
  read(slot = STORAGE_KEYS.save): StoredSave | null {
    try {
      const raw = localStorage.getItem(slot);
      if (!raw) return null;
      const parsed = JSON.parse(raw) as LegacySave;
      if (!parsed?.data || typeof parsed.data !== 'object') return null;

      if ('player' in parsed.data) {
        return {
          schemaVersion: SAVE_SCHEMA_VERSION,
          savedAt: parsed.savedAt ?? Date.now(),
          data: parsed.data as GameSaveData,
        };
      }

      return {
        schemaVersion: SAVE_SCHEMA_VERSION,
        savedAt: parsed.savedAt ?? Date.now(),
        data: {
          player: parsed.data,
          inventory: [],
          quests: this.readLegacyQuests(),
          world: this.readLegacyWorld(),
        },
      };
    } catch {
      return null;
    }
  }

  write(data: GameSaveData, slot = STORAGE_KEYS.save): boolean {
    try {
      const envelope: StoredSave = {
        schemaVersion: SAVE_SCHEMA_VERSION,
        savedAt: Date.now(),
        data,
      };
      localStorage.setItem(slot, JSON.stringify(envelope));
      return true;
    } catch {
      return false;
    }
  }

  patch(patch: Partial<GameSaveData>, slot = STORAGE_KEYS.save): boolean {
    const current = this.read(slot);
    if (!current) return false;
    return this.write({ ...current.data, ...patch }, slot);
  }

  remove(slot = STORAGE_KEYS.save): void {
    try {
      localStorage.removeItem(slot);
    } catch {
      // Storage may be disabled; deletion is best effort.
    }
  }

  readLegacyQuests(): QuestState[] {
    return parseArray(STORAGE_KEYS.legacyQuests, isQuestState);
  }

  readLegacyWorld(): WorldProgressData {
    return {
      discoveredAreas: parseArray(STORAGE_KEYS.legacyDiscoveredAreas, isAreaId),
      defeatedBossIds: parseArray(STORAGE_KEYS.legacyDefeatedBosses, isString),
      completedDungeonIds: parseArray(STORAGE_KEYS.legacyCompletedDungeons, isString),
    };
  }
}

export const saveRepository = new SaveRepository();
