import { STORAGE_KEYS } from './storageKeys';

/**
 * Per-device sound preferences. Deliberately separate from save slots: loading
 * a different save or resetting a run must not change how loud the game is.
 */
export interface AudioSettings {
  readonly master: number;
  readonly effects: number;
  readonly music: number;
  readonly muted: boolean;
}

export const DEFAULT_AUDIO_SETTINGS: AudioSettings = Object.freeze({ master: 0.8, effects: 1, music: 0.7, muted: false });

interface StoredAudioSettings extends AudioSettings { readonly version: 1 }

const unitInterval = (value: unknown, fallback: number): number =>
  (typeof value === 'number' && Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : fallback);

export function loadAudioSettings(): AudioSettings {
  try {
    const raw = localStorage.getItem(STORAGE_KEYS.audioSettings);
    if (!raw) return DEFAULT_AUDIO_SETTINGS;
    const parsed = JSON.parse(raw) as Partial<StoredAudioSettings>;
    if (parsed.version !== 1) return DEFAULT_AUDIO_SETTINGS;
    return {
      master: unitInterval(parsed.master, DEFAULT_AUDIO_SETTINGS.master),
      effects: unitInterval(parsed.effects, DEFAULT_AUDIO_SETTINGS.effects),
      music: unitInterval(parsed.music, DEFAULT_AUDIO_SETTINGS.music),
      muted: parsed.muted === true,
    };
  } catch {
    return DEFAULT_AUDIO_SETTINGS;
  }
}

export function saveAudioSettings(settings: AudioSettings): void {
  try {
    const stored: StoredAudioSettings = { version: 1, ...settings };
    localStorage.setItem(STORAGE_KEYS.audioSettings, JSON.stringify(stored));
  } catch {
    // Private mode or blocked storage: settings still apply for this session.
  }
}
