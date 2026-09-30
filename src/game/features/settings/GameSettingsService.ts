import { DEFAULT_GAME_SETTINGS, loadGameSettings, saveGameSettings, type GameSettings } from '../../infrastructure/persistence/GameSettingsStore';

export type { GameSettings };
export { DEFAULT_GAME_SETTINGS };

export interface GameSettingsStorage {
  load(): GameSettings;
  save(settings: GameSettings): void;
}

/**
 * The one place gameplay reads player preferences (sound mix, screen shake,
 * reduce motion). Loaded once per page, saved on every change, and observable
 * so the mixer and effects follow edits live.
 */
export class GameSettingsService {
  private current: GameSettings;
  private readonly listeners = new Set<(settings: GameSettings) => void>();

  constructor(private readonly storage: GameSettingsStorage) {
    this.current = storage.load();
  }

  get settings(): GameSettings { return this.current; }

  /** Screen-shake multiplier: the slider, or 0 with reduce motion. */
  get shakeScale(): number { return this.current.reduceMotion ? 0 : this.current.screenShake; }

  update(change: Partial<GameSettings>): void {
    this.current = { ...this.current, ...change };
    this.storage.save(this.current);
    for (const listener of [...this.listeners]) listener(this.current);
  }

  /** Calls `listener` now and on every change; returns the unsubscribe. */
  observe(listener: (settings: GameSettings) => void): () => void {
    this.listeners.add(listener);
    listener(this.current);
    return () => { this.listeners.delete(listener); };
  }
}

export const gameSettings = new GameSettingsService({ load: loadGameSettings, save: saveGameSettings });
