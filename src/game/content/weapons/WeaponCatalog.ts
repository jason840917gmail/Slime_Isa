import { weaponDefinitions as authoredDefinitions } from 'virtual-weapon-content';
import type { WeaponDefinition } from './types';

const definitions = authoredDefinitions as unknown as readonly WeaponDefinition[];
const byId = new Map(definitions.map((definition) => [definition.weaponId, definition]));

export function getWeaponDefinition(weaponId: string): WeaponDefinition {
  const definition = byId.get(weaponId);
  if (!definition) throw new Error(`Unknown weapon '${weaponId}'`);
  return definition;
}

export function getWeaponDefinitions(): readonly WeaponDefinition[] {
  return definitions;
}
