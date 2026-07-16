import { gameState, SAVE_SCHEMA_VERSION, type GameStateData } from './GameState';
import { gameEvents } from './EventBus';

/**
 * Versioned localStorage save system.
 *
 * Schema versioning keeps future migrations safe: load() validates the stored
 * version and can run migration steps before handing data to GameState.
 *
 * Phase 0: persists only GameState core fields. Later phases extend the schema
 * (hp, level, xp, abilities, weapons, inventory, quest flags, discovered areas).
 */

const DEFAULT_SLOT = 'slime-isa:save';

interface StoredEnvelope {
  schemaVersion: number;
  savedAt: number;
  data: GameStateData;
}

function readRaw(slot: string): StoredEnvelope | null {
  try {
    const raw = localStorage.getItem(slot);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as StoredEnvelope;
    if (!parsed || typeof parsed !== 'object') return null;
    if (typeof parsed.data !== 'object' || parsed.data === null) return null;
    return parsed;
  } catch {
    return null;
  }
}

function migrate(parsed: StoredEnvelope): StoredEnvelope {
  if (parsed.schemaVersion < SAVE_SCHEMA_VERSION) {
    // Future: per-version migration steps here.
    parsed = {
      ...parsed,
      schemaVersion: SAVE_SCHEMA_VERSION,
      data: { ...parsed.data, schemaVersion: SAVE_SCHEMA_VERSION },
    };
  }
  return parsed;
}

class SaveSystemImpl {
  save(slot: string = DEFAULT_SLOT): boolean {
    try {
      const envelope: StoredEnvelope = {
        schemaVersion: SAVE_SCHEMA_VERSION,
        savedAt: Date.now(),
        data: gameState.serialize(),
      };
      localStorage.setItem(slot, JSON.stringify(envelope));
      gameEvents.emit('save.done', { slot });
      return true;
    } catch {
      return false;
    }
  }

  load(slot: string = DEFAULT_SLOT): boolean {
    const parsed = readRaw(slot);
    if (!parsed) return false;

    const migrated = migrate(parsed);
    gameState.load(migrated.data);
    gameEvents.emit('save.loaded', { slot });
    return true;
  }

  hasSave(slot: string = DEFAULT_SLOT): boolean {
    return readRaw(slot) !== null;
  }

  deleteSave(slot: string = DEFAULT_SLOT): void {
    try {
      localStorage.removeItem(slot);
    } catch {
      // ignore
    }
  }

  savedAt(slot: string = DEFAULT_SLOT): number | null {
    const parsed = readRaw(slot);
    return parsed ? parsed.savedAt : null;
  }
}

export const saveSystem = new SaveSystemImpl();
export { DEFAULT_SLOT as DEFAULT_SAVE_SLOT };
