import { getPrimaryPlayerPackage } from './characters/CharacterCatalog';

const primary = getPrimaryPlayerPackage().character;
if (!primary.player) throw new Error('Primary player package is missing gameplay properties');

/** Focused player runtime configuration adapted from the editable package. */
export const PLAYER_CONFIG = {
  name: primary.player.name,
  body: primary.body,
  movement: primary.player.movement,
  progression: primary.player.progression,
} as const;
