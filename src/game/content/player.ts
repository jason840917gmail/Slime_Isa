import { getPrimaryPlayerPackage } from './characters/CharacterCatalog';
import { GAME_CONSTANTS } from '../Constant';

const primary = getPrimaryPlayerPackage().character;
if (!primary.player) throw new Error('Primary player package is missing gameplay properties');

/** Physics-friendly movement tuning choices, ordered from deliberate to fast. */
export const PLAYER_MOVEMENT_SPEED_OPTIONS = [
  120, 150, 180, 210, 240, 270, 300, 330, 360, 420,
] as const;

export type PlayerMovementSpeedOption = typeof PLAYER_MOVEMENT_SPEED_OPTIONS[number];

/** Focused player runtime configuration adapted from the editable package. */
export const PLAYER_CONFIG = {
  name: primary.player.name,
  attributes: GAME_CONSTANTS.character.player.initialAttributes,
  body: primary.body,
  movement: GAME_CONSTANTS.character.player.movement,
  progression: GAME_CONSTANTS.character.player.progression,
} as const;
