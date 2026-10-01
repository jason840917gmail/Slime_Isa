import type Phaser from 'phaser';

import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import { Node, type NodeOptions } from '../../runtime/scene/Node';

export type AudioBus = 'effects' | 'music' | 'ambience';

export const AUDIO_BUSES: readonly AudioBus[] = ['effects', 'music', 'ambience'];

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
  /** Primary sound cache key. */
  readonly assetId: string;
  /** Extra interchangeable takes; one-shot plays pick randomly among assetId and these. */
  readonly variantAssetIds?: readonly string[];
  readonly bus?: AudioBus;
  readonly volume?: number;
  readonly pitch?: number;
  /** One-shot plays scale pitch by a uniform random factor in [1 - pitchRandomness, 1 + pitchRandomness]. */
  readonly pitchRandomness?: number;
  /** Maximum overlapping one-shot voices; the oldest voice is restarted when exceeded. */
  readonly polyphony?: number;
  /** Plays requested sooner than this after the previous accepted play are dropped. */
  readonly minIntervalMs?: number;
  /** One-shot voices keep playing to completion after the node leaves the tree. */
  readonly detached?: boolean;
  readonly loop?: boolean;
  readonly autoplay?: boolean;
  readonly preferences?: AudioPreferences;
  readonly unlock?: AudioUnlockService;
  /** "field=value|value" test applied to signal payloads routed to the play/stop handlers. */
  readonly payloadFilter?: string;
  /** Injectable randomness and clock for deterministic tests. */
  readonly random?: () => number;
  readonly now?: () => number;
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

interface Voice {
  readonly assetId: string;
  readonly handle: SoundHandle;
  rate: number;
  playing: boolean;
  startedAt: number;
  readonly complete: () => void;
}

/** Stand-in for a sound whose asset did not load (no Web Audio, missing file): plays nothing, never throws. */
function silentHandle(): SoundHandle {
  return { play: () => false, stop: () => false, destroy: () => undefined };
}

/**
 * Compiles a "field.path=value|value" payload filter. Empty or absent filters
 * accept everything; non-object payloads never match a non-empty filter.
 */
export function compilePayloadFilter(filter: string | undefined): (payload: unknown) => boolean {
  if (!filter) return () => true;
  const separator = filter.indexOf('=');
  if (separator <= 0) throw new Error(`Audio payloadFilter '${filter}' must look like field=value|value`);
  const path = filter.slice(0, separator).split('.');
  const accepted = new Set(filter.slice(separator + 1).split('|'));
  return (payload) => {
    let current: unknown = payload;
    for (const key of path) {
      if (typeof current !== 'object' || current === null) return false;
      current = (current as Record<string, unknown>)[key];
    }
    return (typeof current === 'string' || typeof current === 'number' || typeof current === 'boolean') && accepted.has(String(current));
  };
}

const defaultPreferences: AudioPreferences = { volume: () => 1, muted: () => false };

function defaultUnlock(scene: Phaser.Scene): AudioUnlockService {
  const sound = scene.sound as unknown as { locked?: boolean; once?: (event: string, callback: () => void) => void; off?: (event: string, callback: () => void) => void } | undefined;
  return {
    isUnlocked: () => sound?.locked !== true,
    onUnlocked: (callback) => {
      if (!sound?.once) return () => undefined;
      sound.once('unlocked', callback);
      return () => sound.off?.('unlocked', callback);
    },
  };
}

function validated(value: number | undefined, fallback: number, label: string, valid: (candidate: number) => boolean): number {
  const resolved = value ?? fallback;
  if (!Number.isFinite(resolved) || !valid(resolved)) throw new Error(`${label} is out of range`);
  return resolved;
}

/**
 * Voice pool behind both audio node types. A loop owns one voice; one-shots
 * allocate up to `polyphony` overlapping voices so rapid triggers (combo hits,
 * multi-target swings) layer instead of cutting each other off. Voices are
 * allocated on the first accepted play, not on tree entry: most authored audio
 * nodes sit idle, and an idle node owns no Phaser sound.
 */
export class AudioPlaybackController {
  private readonly voices: Voice[] = [];
  private cancelUnlock?: () => void;
  private desiredPlaying = false;
  private entered = false;
  private lastPlayAt = Number.NEGATIVE_INFINITY;
  private lastPan?: number;
  private lastAttenuation = 1;
  /** Runtime fade multiplier (music crossfades); 1 plays at the authored volume. */
  private gain = 1;
  private readonly preferences: AudioPreferences;
  private readonly unlock: AudioUnlockService;
  private readonly assetIds: readonly string[];
  private readonly polyphony: number;

  constructor(
    private readonly owner: Node,
    private readonly options: AudioStreamPlayerOptions,
    private readonly onFinished: () => void,
  ) {
    if (!options.assetId) throw new Error('AudioStreamPlayer requires an assetId');
    validated(options.volume, 1, 'Audio volume', (value) => value >= 0);
    validated(options.pitch, 1, 'Audio pitch', (value) => value > 0);
    validated(options.pitchRandomness, 0, 'Audio pitchRandomness', (value) => value >= 0 && value < 1);
    validated(options.minIntervalMs, 0, 'Audio minIntervalMs', (value) => value >= 0);
    this.polyphony = Math.floor(validated(options.polyphony, 4, 'Audio polyphony', (value) => value >= 1));
    this.assetIds = [options.assetId, ...(options.variantAssetIds ?? []).filter((id) => id.length > 0)];
    this.preferences = options.preferences ?? defaultPreferences;
    this.unlock = options.unlock ?? defaultUnlock(options.scene);
  }

  get playing(): boolean { return this.desiredPlaying; }
  get bus(): AudioBus { return this.options.bus ?? 'effects'; }

  /** Scales this node's volume at run time, for fades; clamped to [0, 1]. */
  setGain(gain: number): void {
    this.gain = Math.max(0, Math.min(1, Number.isFinite(gain) ? gain : 1));
    this.synchronize(this.lastPan, this.lastAttenuation);
  }

  enter(pan?: number, attenuation = 1): void {
    this.entered = true;
    this.owner.entryDisposables.add(() => this.releaseVoices());
    if (this.options.autoplay) this.desiredPlaying = true;
    this.synchronize(pan, attenuation);
    if (this.desiredPlaying) this.startWhenUnlocked();
  }

  exit(): void {
    this.entered = false;
    if (!this.options.loop) this.desiredPlaying = false;
    this.cancelPendingUnlock();
    if (this.options.detached && !this.options.loop) return;
    for (const voice of this.voices) this.stopVoice(voice);
  }

  play(): void {
    const now = this.now();
    if (!this.options.loop && now - this.lastPlayAt < (this.options.minIntervalMs ?? 0)) return;
    this.lastPlayAt = now;
    this.desiredPlaying = true;
    this.startWhenUnlocked();
  }

  stop(): void {
    this.desiredPlaying = false;
    this.cancelPendingUnlock();
    for (const voice of this.voices) this.stopVoice(voice);
  }

  synchronize(pan?: number, attenuation = 1): void {
    this.lastPan = pan;
    this.lastAttenuation = attenuation;
    const bus = this.options.bus ?? 'effects';
    const preferenceVolume = this.preferences.muted(bus) ? 0 : this.preferences.volume(bus);
    const volume = Math.max(0, (this.options.volume ?? 1) * preferenceVolume * attenuation * this.gain);
    for (const voice of this.voices) {
      voice.handle.setVolume?.(volume);
      voice.handle.setRate?.(voice.rate);
      if (pan !== undefined) voice.handle.setPan?.(Math.max(-1, Math.min(1, pan)));
    }
  }

  private now(): number { return this.options.now?.() ?? Date.now(); }

  private startWhenUnlocked(): void {
    if (!this.desiredPlaying || !this.entered) return;
    if (this.unlock.isUnlocked()) {
      this.cancelPendingUnlock();
      this.startVoice();
      return;
    }
    if (this.cancelUnlock) return;
    this.cancelUnlock = this.unlock.onUnlocked(() => {
      this.cancelUnlock = undefined;
      this.startWhenUnlocked();
    });
  }

  private startVoice(): void {
    const basePitch = this.options.pitch ?? 1;
    if (this.options.loop) {
      const voice = this.voices[0] ?? this.createVoice(this.options.assetId);
      if (voice.playing) return;
      voice.rate = basePitch;
      this.synchronize(this.lastPan, this.lastAttenuation);
      voice.playing = voice.handle.play({ loop: true, rate: voice.rate });
      return;
    }
    const random = this.options.random ?? Math.random;
    const assetId = this.assetIds[Math.min(this.assetIds.length - 1, Math.floor(random() * this.assetIds.length))];
    const voice = this.voices.find((candidate) => !candidate.playing && candidate.assetId === assetId)
      ?? (this.voices.length < this.polyphony ? this.createVoice(assetId) : this.recycleOldestVoice(assetId));
    voice.rate = basePitch * (1 + (random() * 2 - 1) * (this.options.pitchRandomness ?? 0));
    voice.startedAt = this.now();
    this.synchronize(this.lastPan, this.lastAttenuation);
    voice.playing = voice.handle.play({ loop: false, rate: voice.rate });
  }

  private createVoice(assetId: string): Voice {
    const cache = (this.options.scene as unknown as { cache?: { audio?: { exists?(key: string): boolean } } }).cache?.audio;
    const manager = this.options.scene.sound as Phaser.Sound.BaseSoundManager | undefined;
    const handle = !manager || (cache?.exists && !cache.exists(assetId)) ? silentHandle() : manager.add(assetId, { loop: this.options.loop ?? false, volume: 0, rate: this.options.pitch ?? 1 }) as unknown as SoundHandle;
    const voice: Voice = {
      assetId, handle, rate: this.options.pitch ?? 1, playing: false, startedAt: Number.NEGATIVE_INFINITY,
      complete: () => {
        handle.once?.('complete', voice.complete);
        if (this.options.loop) return;
        voice.playing = false;
        if (!this.voices.some((candidate) => candidate.playing)) this.desiredPlaying = false;
        this.onFinished();
      },
    };
    handle.once?.('complete', voice.complete);
    this.voices.push(voice);
    return voice;
  }

  private recycleOldestVoice(assetId: string): Voice {
    const oldest = this.voices.reduce((candidate, voice) => (voice.startedAt < candidate.startedAt ? voice : candidate));
    this.voices.splice(this.voices.indexOf(oldest), 1);
    this.destroyVoice(oldest, false);
    return this.createVoice(assetId);
  }

  private stopVoice(voice: Voice): void {
    if (voice.playing) voice.handle.stop();
    voice.playing = false;
  }

  private releaseVoices(): void {
    this.cancelPendingUnlock();
    const outlive = this.options.detached === true && this.options.loop !== true;
    for (const voice of this.voices.splice(0)) this.destroyVoice(voice, outlive && voice.playing);
  }

  /** Stops and frees one voice, or, when it should outlive its owner, frees it once it finishes. */
  private destroyVoice(voice: Voice, outlive: boolean): void {
    voice.handle.off?.('complete', voice.complete);
    const free = (): void => {
      const manager = this.options.scene.sound as unknown as { remove?: (candidate: SoundHandle) => boolean } | undefined;
      if (!manager?.remove?.(voice.handle)) voice.handle.destroy();
    };
    if (outlive) { voice.handle.once?.('complete', free); return; }
    voice.handle.stop();
    voice.playing = false;
    free();
  }

  private cancelPendingUnlock(): void { this.cancelUnlock?.(); this.cancelUnlock = undefined; }
}

export class AudioStreamPlayerNode extends Node {
  readonly playbackFinished = this.createSignal<void>('playback_finished');
  private readonly playback: AudioPlaybackController;

  constructor(private readonly audioOptions: AudioStreamPlayerOptions) {
    super(audioOptions);
    this.playback = new AudioPlaybackController(this, audioOptions, () => this.playbackFinished.emit());
    const accepts = compilePayloadFilter(audioOptions.payloadFilter);
    this.registerSignalHandler('play', (payload) => { if (accepts(payload)) this.play(); });
    this.registerSignalHandler('stop', (payload) => { if (accepts(payload)) this.stop(); });
    this.set_process(true);
    // Keep the mix live while menus pause the simulation (volume sliders, UI clicks).
    this.set_process_when_paused(true);
  }

  get playing(): boolean { return this.playback.playing; }
  get bus(): AudioBus { return this.playback.bus; }
  play(): void { this.playback.play(); }
  stop(): void { this.playback.stop(); }
  /** Runtime fade multiplier on top of the authored volume (see MusicDirector). */
  setGain(gain: number): void { this.playback.setGain(gain); }
  override _enter_tree(): void { this.playback.enter(); }
  override _process(): void { this.playback.synchronize(); }
  override _exit_tree(): void { this.playback.exit(); }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): AudioStreamPlayerNode {
    return new AudioStreamPlayerNode({ ...this.audioOptions, runtimeId, name: this.name });
  }
}
