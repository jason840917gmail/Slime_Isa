import { characterPackages } from 'virtual-character-content';

import { validateCharacterPackage } from './validation';
import type { CharacterDocument, CharacterPackage, EnemyGameplayDocument, PlayerGameplayDocument } from './types';

const packages = characterPackages as unknown as readonly CharacterPackage[];
const byId = new Map(packages.map((entry) => [entry.character.characterId, entry]));

for (const entry of packages) {
  const issues = validateCharacterPackage(entry);
  if (issues.length > 0) throw new Error(issues.map((issue) => `${issue.path}: ${issue.message}`).join('\n'));
}

export function getCharacterPackage(characterId: string): CharacterPackage {
  const packageValue = byId.get(characterId);
  if (!packageValue) throw new Error(`Unknown character '${characterId}'`);
  return packageValue;
}

export function getCharacterPackages(): readonly CharacterPackage[] {
  return packages;
}

export function getPrimaryPlayerPackage(): CharacterPackage {
  const players = packages.filter((entry) => entry.character.kind === 'player');
  const primary = players.filter((entry) => entry.character.runtimeRole === 'primary-player');
  if (primary.length !== 1) throw new Error(`Expected exactly one primary player, found ${primary.length}`);
  return primary[0];
}

export function getEnemyPackages(): readonly CharacterPackage[] {
  return packages.filter((entry) => entry.character.kind === 'enemy');
}

export function getPlayerGameplay(character: CharacterDocument): PlayerGameplayDocument {
  if (character.kind !== 'player' || !character.player) throw new Error(`Character '${character.characterId}' is not a player`);
  return character.player;
}

export function getEnemyGameplay(character: CharacterDocument): EnemyGameplayDocument {
  if (character.kind !== 'enemy' || !character.enemy) throw new Error(`Character '${character.characterId}' is not an enemy`);
  return character.enemy;
}
