import type Phaser from 'phaser';

import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import { Node, type NodeOptions } from '../../runtime/scene/Node';

export type AudioBus = 'effects' | 'music';

export interface AudioPreferences {
  volume(bus: AudioBus): number;
  muted(bus: AudioBus): boolean;
}

export interface AudioUnlockService {
  isUnlocked(): boolean;
  onUnlocked(callback: () => void): () => void;
}

export interface AudioStreamPlayerOptions extends NodeOptions {
  readonly scene: Phaser.Scene;
  readonly assetId: string;
  readonly bus?: AudioBus;
  readonly volume?: number;
  readonly pitch?: number;
  readonly loop?: boolean;
  readonly autoplay?: boolean;
  readonly preferences?: AudioPreferences;
  readonly unlock?: AudioUnlockService;
}

interface SoundHandle {
  play(config?: object): boolean;
  stop(): boolean;
  destroy(): void;
  once?(event: string, callback: () => void): unknown;
  off?(event: string, callback: () => void): unknown;
  setVolume?(volume: number): unknown;
  setRate?(rate: number): unknown;
  setPan?(pan: number): unknown;
}

const defaultPreferences: AudioPreferences = { volume: () => 1, muted: () => false };

function defaultUnlock(scene: Phaser.Scene): AudioUnlockService {
  const sound = scene.sound as unknown as { locked?: boolean; once?: (event: string, callback: () => void) => void; off?: (event: string, callback: () => void) => void };
  return {
    isUnlocked: () => sound.locked !== true,
    onUnlocked: (callback) => {
      if (!sound.once) return () => undefined;
      sound.once('unlocked', callback);
      return () => sound.off?.('unlocked', callback);
    },
  };
}

export class AudioPlaybackController {
  private sound?: SoundHandle;
  private cancelUnlock?: () => void;
  private desiredPlaying = false;
  private actualPlaying = false;
  private readonly preferences: AudioPreferences;
  private readonly unlock: AudioUnlockService;

  constructor(
    private readonly owner: Node,
    private readonly options: AudioStreamPlayerOptions,
    private readonly onFinished: () => void,
  ) {
    if (!options.assetId) throw new Error('AudioStreamPlayer requires an assetId');
    if (!Number.isFinite(options.volume ?? 1) || (options.volume ?? 1) < 0) throw new Error('Audio volume must be non-negative and finite');
    if (!Number.isFinite(options.pitch ?? 1) || (options.pitch ?? 1) <= 0) throw new Error('Audio pitch must be positive and finite');
    this.preferences = options.preferences ?? defaultPreferences;
    this.unlock = options.unlock ?? defaultUnlock(options.scene);
  }

  get playing(): boolean { return this.desiredPlaying; }

  enter(): void {
    const sound = this.options.scene.sound.add(this.options.assetId, { loop: this.options.loop ?? false, volume: 0, rate: this.options.pitch ?? 1 }) as unknown as SoundHandle;
    this.sound = sound;
    const complete = (): void => {
      if (this.options.loop) return;
      this.actualPlaying = false;
      this.desiredPlaying = false;
      this.onFinished();
    };
    sound.once?.('complete', complete);
    this.owner.entryDisposables.add(() => { sound.off?.('complete', complete); });
    this.owner.entryDisposables.add(() => {
      this.cancelPendingUnlock();
      sound.stop();
      const manager = this.options.scene.sound as unknown as { remove?: (candidate: SoundHandle) => boolean };
      if (!manager.remove?.(sound)) sound.destroy();
      if (this.sound === sound) this.sound = undefined;
      this.actualPlaying = false;
    });
    if (this.options.autoplay) this.desiredPlaying = true;
    this.synchronize();
    if (this.desiredPlaying) this.startWhenUnlocked();
  }

  exit(): void {
    if (!this.options.loop) this.desiredPlaying = false;
    this.cancelPendingUnlock();
    if (this.actualPlaying) this.sound?.stop();
    this.actualPlaying = false;
  }

  play(): void { this.desiredPlaying = true; this.startWhenUnlocked(); }

  stop(): void {
    this.desiredPlaying = false;
    this.cancelPendingUnlock();
    if (this.actualPlaying) this.sound?.stop();
    this.actualPlaying = false;
  }

  synchronize(pan?: number, attenuation = 1): void {
    const bus = this.options.bus ?? 'effects';
    const preferenceVolume = this.preferences.muted(bus) ? 0 : this.preferences.volume(bus);
    this.sound?.setVolume?.(Math.max(0, (this.options.volume ?? 1) * preferenceVolume * attenuation));
    this.sound?.setRate?.(this.options.pitch ?? 1);
    if (pan !== undefined) this.sound?.setPan?.(Math.max(-1, Math.min(1, pan)));
  }

  private startWhenUnlocked(): void {
    if (!this.desiredPlaying || !this.sound || this.actualPlaying) return;
    if (this.unlock.isUnlocked()) {
      this.cancelPendingUnlock();
      this.synchronize();
      this.actualPlaying = this.sound.play({ loop: this.options.loop ?? false, rate: this.options.pitch ?? 1 });
      return;
    }
    if (this.cancelUnlock) return;
    this.cancelUnlock = this.unlock.onUnlocked(() => {
      this.cancelUnlock = undefined;
      this.startWhenUnlocked();
    });
  }

  private cancelPendingUnlock(): void { this.cancelUnlock?.(); this.cancelUnlock = undefined; }
}

export class AudioStreamPlayerNode extends Node {
  readonly playbackFinished = this.createSignal<void>('playback_finished');
  private readonly playback: AudioPlaybackController;

  constructor(private readonly audioOptions: AudioStreamPlayerOptions) {
    super(audioOptions);
    this.playback = new AudioPlaybackController(this, audioOptions, () => this.playbackFinished.emit());
    this.set_process(true);
  }

  get playing(): boolean { return this.playback.playing; }
  play(): void { this.playback.play(); }
  stop(): void { this.playback.stop(); }
  override _enter_tree(): void { this.playback.enter(); }
  override _process(): void { this.playback.synchronize(); }
  override _exit_tree(): void { this.playback.exit(); }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): AudioStreamPlayerNode {
    return new AudioStreamPlayerNode({ ...this.audioOptions, runtimeId, name: this.name });
  }
}
