import { projectileDefinitions as authoredDefinitions } from 'virtual-projectile-content';
import type { ProjectileDefinition } from './types';

const definitions = authoredDefinitions as unknown as readonly ProjectileDefinition[];
const byId = new Map(definitions.map((definition) => [definition.projectileId, definition]));

export function getProjectileDefinition(projectileId: string): ProjectileDefinition {
  const definition = byId.get(projectileId);
  if (!definition) throw new Error(`Unknown projectile '${projectileId}'`);
  return definition;
}

export function getProjectileDefinitions(): readonly ProjectileDefinition[] {
  return definitions;
}
