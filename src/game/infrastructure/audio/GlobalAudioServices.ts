import type { AudioBus, AudioPreferences, AudioUnlockService } from '../phaser-nodes/AudioStreamPlayerNode';

interface UnlockableSoundManager {
  readonly locked?: boolean;
  on(event: 'unlocked', callback: () => void): unknown;
  off(event: 'unlocked', callback: () => void): unknown;
}

/** One audio gate and one pair of bus preferences for the active authored world. */
export class GlobalAudioServices implements AudioPreferences, AudioUnlockService {
  private readonly volumes: Record<AudioBus, number> = { effects: 1, music: 1 };
  private readonly mutedBuses: Record<AudioBus, boolean> = { effects: false, music: false };
  private readonly unlockCallbacks = new Set<() => void>();
  private listening = false;
  private disposed = false;

  constructor(private readonly sound: UnlockableSoundManager) {}

  volume(bus: AudioBus): number { return this.volumes[bus]; }
  muted(bus: AudioBus): boolean { return this.mutedBuses[bus]; }

  setVolume(bus: AudioBus, volume: number): void {
    if (!Number.isFinite(volume) || volume < 0 || volume > 1) throw new Error('Audio bus volume must be between 0 and 1');
    this.volumes[bus] = volume;
  }

  setMuted(bus: AudioBus, muted: boolean): void { this.mutedBuses[bus] = muted; }
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
