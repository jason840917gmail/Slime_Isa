import { getPrimaryPlayerPackage } from './characters/CharacterCatalog';
import type { CharacterAttributeSet } from './characters/types';

const primary = getPrimaryPlayerPackage().character;
if (!primary.player) throw new Error('Primary player package is missing gameplay properties');

const DEFAULT_PLAYER_ATTRIBUTES: CharacterAttributeSet = {
  strength: 10,
  vitality: 10,
  agility: 10,
  intellect: 10,
};

/** Physics-friendly movement tuning choices, ordered from deliberate to fast. */
export const PLAYER_MOVEMENT_SPEED_OPTIONS = [
  120, 150, 180, 210, 240, 270, 300, 330, 360, 420,
] as const;

export type PlayerMovementSpeedOption = typeof PLAYER_MOVEMENT_SPEED_OPTIONS[number];

/** Focused player runtime configuration adapted from the editable package. */
export const PLAYER_CONFIG = {
  name: primary.player.name,
  attributes: primary.attributes ?? DEFAULT_PLAYER_ATTRIBUTES,
  body: primary.body,
  movement: primary.player.movement,
  progression: primary.player.progression,
} as const;
