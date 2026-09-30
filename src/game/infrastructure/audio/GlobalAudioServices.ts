import type { AudioBus, AudioPreferences, AudioUnlockService } from '../phaser-nodes/AudioStreamPlayerNode';

interface UnlockableSoundManager {
  readonly locked?: boolean;
  on(event: 'unlocked', callback: () => void): unknown;
  off(event: 'unlocked', callback: () => void): unknown;
}

/** One audio gate and the bus mix (master × per-bus volume, mutes) for the active authored world. */
export class GlobalAudioServices implements AudioPreferences, AudioUnlockService {
  private master = 1;
  private masterMuted = false;
  private readonly volumes: Record<AudioBus, number> = { effects: 1, music: 1, ambience: 1 };
  private readonly mutedBuses: Record<AudioBus, boolean> = { effects: false, music: false, ambience: false };
  /** Temporary attenuation (music under a pause menu); not a player setting. */
  private readonly ducks: Record<AudioBus, number> = { effects: 1, music: 1, ambience: 1 };
  private readonly unlockCallbacks = new Set<() => void>();
  private listening = false;
  private disposed = false;

  constructor(private readonly sound: UnlockableSoundManager) {}

  /** Effective bus gain: the bus slider scaled by the master slider and any duck. */
  volume(bus: AudioBus): number { return this.volumes[bus] * this.master * this.ducks[bus]; }
  muted(bus: AudioBus): boolean { return this.masterMuted || this.mutedBuses[bus]; }
  busVolume(bus: AudioBus): number { return this.volumes[bus]; }
  masterVolume(): number { return this.master; }
  isMasterMuted(): boolean { return this.masterMuted; }

  setMasterVolume(volume: number): void {
    if (!Number.isFinite(volume) || volume < 0 || volume > 1) throw new Error('Master volume must be between 0 and 1');
    this.master = volume;
  }

  setMasterMuted(muted: boolean): void { this.masterMuted = muted; }

  setVolume(bus: AudioBus, volume: number): void {
    if (!Number.isFinite(volume) || volume < 0 || volume > 1) throw new Error('Audio bus volume must be between 0 and 1');
    this.volumes[bus] = volume;
  }

  setMuted(bus: AudioBus, muted: boolean): void { this.mutedBuses[bus] = muted; }

  /** Lowers a bus for a while without touching the player's volume settings (1 = no duck). */
  setDuck(bus: AudioBus, factor: number): void {
    this.ducks[bus] = Math.max(0, Math.min(1, Number.isFinite(factor) ? factor : 1));
  }
  isUnlocked(): boolean { return this.sound.locked !== true; }

  onUnlocked(callback: () => void): () => void {
    if (this.disposed) return () => undefined;
    if (this.isUnlocked()) {
      let cancelled = false;
      queueMicrotask(() => { if (!this.disposed && !cancelled) callback(); });
      return () => { cancelled = true; };
    }
    this.unlockCallbacks.add(callback);
    if (!this.listening) {
      this.sound.on('unlocked', this.flushUnlocked);
      this.listening = true;
    }
    return () => {
      this.unlockCallbacks.delete(callback);
      if (this.unlockCallbacks.size === 0) this.stopListening();
    };
  }

  destroy(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.unlockCallbacks.clear();
    this.stopListening();
  }

  private readonly flushUnlocked = (): void => {
    const callbacks = [...this.unlockCallbacks];
    this.unlockCallbacks.clear();
    this.stopListening();
    for (const callback of callbacks) callback();
  };

  private stopListening(): void {
    if (!this.listening) return;
    this.sound.off('unlocked', this.flushUnlocked);
    this.listening = false;
  }
}
