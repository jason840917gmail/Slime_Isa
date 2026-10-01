import { STORAGE_KEYS } from './storageKeys';

/**
 * Per-device preferences. Deliberately separate from save slots: loading a
 * different save or starting a new game never changes how loud the game is or
 * how much the screen moves.
 */
export interface GameSettings {
  /** Sound mix; every volume is in [0, 1]. Ambience follows `effects`. */
  readonly master: number;
  readonly effects: number;
  readonly music: number;
  readonly muted: boolean;
  /** Screen-shake strength in [0, 1]; 0 turns shake off. */
  readonly screenShake: number;
  /** Turns off shake, hit-stop and other strong motion, and softens squash and stretch. */
  readonly reduceMotion: boolean;
  /**
   * Where a left click swings: toward the pointer or the way the slime last
   * moved. Under test (roadmap 4.10); only the development panel changes it.
   */
  readonly attackAim: AttackAim;
}

export type AttackAim = 'pointer' | 'facing';

export const DEFAULT_GAME_SETTINGS: GameSettings = Object.freeze({
  master: 0.8,
  effects: 1,
  music: 0.7,
  muted: false,
  screenShake: 1,
  reduceMotion: false,
  attackAim: 'pointer',
});

interface StoredGameSettings extends GameSettings { readonly version: 1 }

const unitInterval = (value: unknown, fallback: number): number =>
  (typeof value === 'number' && Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : fallback);

function parse(value: Partial<GameSettings>): GameSettings {
  return {
    master: unitInterval(value.master, DEFAULT_GAME_SETTINGS.master),
    effects: unitInterval(value.effects, DEFAULT_GAME_SETTINGS.effects),
    music: unitInterval(value.music, DEFAULT_GAME_SETTINGS.music),
    muted: value.muted === true,
    screenShake: unitInterval(value.screenShake, DEFAULT_GAME_SETTINGS.screenShake),
    reduceMotion: value.reduceMotion === true,
    attackAim: value.attackAim === 'facing' ? 'facing' : 'pointer',
  };
}

/** Reads the settings; sound preferences saved before settings existed carry over. */
export function loadGameSettings(): GameSettings {
  try {
    const raw = localStorage.getItem(STORAGE_KEYS.gameSettings);
    if (raw) {
      const parsed = JSON.parse(raw) as Partial<StoredGameSettings>;
      return parsed.version === 1 ? parse(parsed) : DEFAULT_GAME_SETTINGS;
    }
    const legacyAudio = localStorage.getItem(STORAGE_KEYS.audioSettings);
    if (legacyAudio) {
      const parsed = JSON.parse(legacyAudio) as Partial<GameSettings> & { readonly version?: number };
      if (parsed.version === 1) return parse({ ...parsed, screenShake: undefined, reduceMotion: undefined });
    }
  } catch {
    // Unreadable storage: defaults.
  }
  return DEFAULT_GAME_SETTINGS;
}

export function saveGameSettings(settings: GameSettings): void {
  try {
    const stored: StoredGameSettings = { version: 1, ...settings };
    localStorage.setItem(STORAGE_KEYS.gameSettings, JSON.stringify(stored));
  } catch {
    // Private mode or blocked storage: settings still apply for this session.
  }
}
