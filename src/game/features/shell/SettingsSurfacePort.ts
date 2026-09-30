import type { JsonValue } from '../../content/scenes/types';
import type { AudioBus } from '../../infrastructure/phaser-nodes/AudioStreamPlayerNode';
import type { UiPresentationModel } from '../scripts/ui/UiSurfaceScript';
import { DEFAULT_GAME_SETTINGS, type GameSettings, type GameSettingsService } from '../settings/GameSettingsService';
import { MenuSurface, type MenuSurfaceOptions } from './MenuSurface';

/** Where the sound mix is applied (the world's GlobalAudioServices). */
export interface AudioMixer {
  setMasterVolume(volume: number): void;
  setMasterMuted(muted: boolean): void;
  setVolume(bus: AudioBus, volume: number): void;
}

export interface SettingsSurfaceOptions extends MenuSurfaceOptions {
  readonly settings: GameSettingsService;
  /** Opens the controls list on top of the settings. */
  readonly openControls: () => void;
}

/** Slider node name → setting it edits. */
const SLIDER_SETTINGS: Readonly<Record<string, 'master' | 'effects' | 'music' | 'screenShake'>> = {
  Master: 'master',
  Effects: 'effects',
  Music: 'music',
  Shake: 'screenShake',
};

export const SETTINGS_SURFACE_ID = 'settings';

/**
 * Settings (from the pause menu or the title): sound mix and mute, screen
 * shake, reduce motion, and the controls list. Edits go to the settings
 * service, which saves them on this device (separate from save slots); the
 * world applies the sound mix from there with `applyMix`.
 */
export class SettingsSurfacePort extends MenuSurface {
  private readonly stopWatching: () => void;

  constructor(private readonly options: SettingsSurfaceOptions) {
    super(SETTINGS_SURFACE_ID, options);
    this.stopWatching = options.settings.observe(() => this.publish());
  }

  protected model(): UiPresentationModel {
    const { master, effects, music, muted, screenShake, reduceMotion } = this.options.settings.settings;
    const percent = (value: number): string => `${Math.round(value * 100)}%`;
    return {
      master, effects, music, screenShake,
      masterLabel: `Master volume  ${percent(master)}`,
      effectsLabel: `Sound effects  ${percent(effects)}`,
      musicLabel: `Music  ${percent(music)}`,
      shakeLabel: reduceMotion ? 'Screen shake  off (reduce motion)' : `Screen shake  ${percent(screenShake)}`,
      shakeDisabled: reduceMotion,
      muteLabel: muted ? 'Unmute' : 'Mute all',
      motionLabel: reduceMotion ? 'Reduce motion: On' : 'Reduce motion: Off',
      status: muted ? 'All sound is muted' : 'Changes apply immediately and are saved on this device',
    };
  }

  protected act(actionId: string, payload?: JsonValue): void {
    const { settings } = this.options;
    if (actionId === 'toggle-mute') settings.update({ muted: !settings.settings.muted });
    else if (actionId === 'toggle-reduce-motion') settings.update({ reduceMotion: !settings.settings.reduceMotion });
    else if (actionId === 'reset') settings.update(DEFAULT_GAME_SETTINGS);
    else if (actionId === 'controls') this.options.openControls();
    else if (actionId === 'set-value' && payload && typeof payload === 'object' && !Array.isArray(payload)) {
      const change = payload as Readonly<Record<string, JsonValue>>;
      const setting = typeof change.control === 'string' ? SLIDER_SETTINGS[change.control] : undefined;
      if (setting && typeof change.value === 'number' && Number.isFinite(change.value)) {
        settings.update({ [setting]: Math.min(1, Math.max(0, change.value)) });
      }
    }
  }

  override destroy(): void {
    this.stopWatching();
    super.destroy();
  }
}

export function applyMix(mixer: AudioMixer, settings: GameSettings): void {
  mixer.setMasterVolume(settings.master);
  mixer.setMasterMuted(settings.muted);
  mixer.setVolume('effects', settings.effects);
  mixer.setVolume('ambience', settings.effects);
  mixer.setVolume('music', settings.music);
}
