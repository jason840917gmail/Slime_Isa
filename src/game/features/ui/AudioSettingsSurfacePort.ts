import type { JsonValue } from '../../content/scenes/types';
import type { AudioBus } from '../../infrastructure/phaser-nodes/AudioStreamPlayerNode';
import type { ModalHandle, ModalStack } from '../../ui/ModalStack';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

/** The persisted user mix; every value is in [0, 1]. */
export interface AudioMixSettings {
  readonly master: number;
  readonly effects: number;
  readonly music: number;
  readonly muted: boolean;
}

/** Where the mix is applied (the world's GlobalAudioServices). */
export interface AudioMixer {
  setMasterVolume(volume: number): void;
  setMasterMuted(muted: boolean): void;
  setVolume(bus: AudioBus, volume: number): void;
}

export interface AudioSettingsSurfaceOptions {
  readonly modalStack: ModalStack;
  readonly mixer: AudioMixer;
  readonly load: () => AudioMixSettings;
  readonly save: (settings: AudioMixSettings) => void;
  readonly defaults: AudioMixSettings;
  readonly onPausedChange: (paused: boolean) => void;
}

const SURFACE_ID = 'audio-settings';

/** Slider node name → setting it edits. */
const SLIDER_SETTINGS: Readonly<Record<string, 'master' | 'effects' | 'music'>> = {
  Master: 'master',
  Effects: 'effects',
  Music: 'music',
};

/**
 * Sound settings modal (Esc when no other surface is open): master, effects
 * and music volume plus a global mute. Changes apply live and persist per
 * device. Ambience follows the effects slider.
 */
export class AudioSettingsSurfacePort implements UiSurfacePort {
  private readonly handle: ModalHandle;
  private readonly listeners = new Set<(model: UiPresentationModel) => void>();
  private settings: AudioMixSettings;
  private openValue = false;
  private stopped = false;

  constructor(private readonly options: AudioSettingsSurfaceOptions) {
    this.settings = options.load();
    this.apply();
    this.handle = options.modalStack.register(SURFACE_ID, { isOpen: () => this.openValue, close: () => this.close() });
    document.addEventListener('keydown', this.handleShortcut, { capture: true });
  }

  isOpen(): boolean { return this.openValue; }

  open(): void {
    if (this.openValue || this.stopped) return;
    this.openValue = true;
    this.options.onPausedChange(true);
    this.handle.open();
    this.publish();
  }

  close(): void {
    if (!this.openValue) { this.handle.close(); return; }
    this.openValue = false;
    this.handle.close();
    this.options.onPausedChange(false);
    this.publish();
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== SURFACE_ID || this.stopped) return {};
    const { master, effects, music, muted } = this.settings;
    const percent = (value: number): string => `${Math.round(value * 100)}%`;
    return {
      open: this.openValue,
      master, effects, music,
      masterLabel: `Master volume  ${percent(master)}`,
      effectsLabel: `Sound effects  ${percent(effects)}`,
      musicLabel: `Music  ${percent(music)}`,
      muteLabel: muted ? 'Unmute' : 'Mute all',
      status: muted ? 'All sound is muted' : 'Changes apply immediately and are saved on this device',
    };
  }

  subscribe(surfaceId: string, listener: (model: UiPresentationModel) => void): () => void {
    if (surfaceId !== SURFACE_ID || this.stopped) return () => undefined;
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  invoke(surfaceId: string, actionId: string, payload?: JsonValue): void {
    if (surfaceId !== SURFACE_ID || this.stopped) return;
    if (actionId === 'close') { this.close(); return; }
    if (actionId === 'toggle-mute') { this.update({ muted: !this.settings.muted }); return; }
    if (actionId === 'reset') { this.update(this.options.defaults); return; }
    if (actionId === 'set-volume' && payload && typeof payload === 'object' && !Array.isArray(payload)) {
      const change = payload as Readonly<Record<string, JsonValue>>;
      const setting = typeof change.control === 'string' ? SLIDER_SETTINGS[change.control] : undefined;
      if (setting && typeof change.value === 'number' && Number.isFinite(change.value)) {
        this.update({ [setting]: Math.min(1, Math.max(0, change.value)) });
      }
    }
  }

  destroy(): void {
    if (this.stopped) return;
    this.close();
    this.stopped = true;
    document.removeEventListener('keydown', this.handleShortcut, { capture: true });
    this.handle.unregister();
    this.listeners.clear();
  }

  private update(change: Partial<AudioMixSettings>): void {
    this.settings = { ...this.settings, ...change };
    this.apply();
    this.options.save(this.settings);
    this.publish();
  }

  private apply(): void {
    const { mixer } = this.options;
    mixer.setMasterVolume(this.settings.master);
    mixer.setMasterMuted(this.settings.muted);
    mixer.setVolume('effects', this.settings.effects);
    mixer.setVolume('ambience', this.settings.effects);
    mixer.setVolume('music', this.settings.music);
  }

  /** Esc opens settings only when nothing else consumed it (ModalStack closes open surfaces first). */
  private readonly handleShortcut = (event: KeyboardEvent): void => {
    if (event.key !== 'Escape' || event.repeat || event.defaultPrevented || this.openValue) return;
    if (this.options.modalStack.hasActiveSurface()) return;
    if (event.target instanceof HTMLElement && event.target.closest('input, textarea, select, [contenteditable]')) return;
    this.open();
    event.preventDefault();
    event.stopPropagation();
  };

  private readonly publish = (): void => {
    if (this.stopped) return;
    const model = this.snapshot(SURFACE_ID);
    for (const listener of this.listeners) listener(model);
  };
}
