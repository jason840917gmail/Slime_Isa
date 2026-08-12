import { weaponDefinitions as authoredDefinitions } from 'virtual-weapon-content';
import { normalizeWeaponDefinition } from './normalize';
import type { AuthoredWeaponDefinition, NormalizedWeaponDefinition } from './types';

const definitions = authoredDefinitions as unknown as readonly AuthoredWeaponDefinition[];
const normalizedDefinitions = definitions.map(normalizeWeaponDefinition);
const byId = new Map(normalizedDefinitions.map((definition) => [definition.weaponId, definition]));

export function getWeaponDefinition(weaponId: string): NormalizedWeaponDefinition {
  const definition = byId.get(weaponId);
  if (!definition) throw new Error(`Unknown weapon '${weaponId}'`);
  return definition;
}

export function getWeaponDefinitions(): readonly NormalizedWeaponDefinition[] {
  return normalizedDefinitions;
}
