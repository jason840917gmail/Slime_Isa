import { gameSettings } from '../settings/GameSettingsService';
import { GameFeel } from './GameFeel';

/** The game's one feel service, reading the player's shake and motion settings. */
export const gameFeel = new GameFeel(() => ({
  shakeScale: gameSettings.shakeScale,
  reduceMotion: gameSettings.settings.reduceMotion,
}));
