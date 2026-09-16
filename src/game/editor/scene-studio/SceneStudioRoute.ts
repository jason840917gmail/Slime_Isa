import { sceneId, type SceneId } from '../../content/scenes/identifiers';

export interface SceneStudioRoute {
  readonly active: boolean;
  readonly scene?: SceneId;
}

const LEGACY_SCENE_STUDIOS = Object.freeze({
  characters: { query: 'character', prefix: 'character' },
  weapons: { query: 'weapon', prefix: 'weapon' },
  projectiles: { query: 'projectile', prefix: 'projectile' },
} as const);

export function redirectLegacyStudioRoute(search: string): string | undefined {
  const query = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  const studio = query.get('studio');
  const mapping = studio && studio in LEGACY_SCENE_STUDIOS
    ? LEGACY_SCENE_STUDIOS[studio as keyof typeof LEGACY_SCENE_STUDIOS]
    : undefined;
  if (!mapping) return undefined;
  const stableId = query.get(mapping.query)?.trim();
  query.delete(mapping.query);
  query.delete('animation');
  query.delete('slot');
  query.delete('direction');
  return formatSceneStudioRoute({
    active: true,
    ...(stableId ? { scene: sceneId(`${mapping.prefix}.${stableId}`) } : {}),
  }, query.toString());
}

export function redirectLegacyCharacterStudioRoute(search: string): string | undefined {
  const query = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  if (query.get('studio') !== 'characters') return undefined;
  return redirectLegacyStudioRoute(search);
}

export function parseSceneStudioRoute(search: string): SceneStudioRoute {
  const query = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  if (query.get('studio') !== 'scenes') return { active: false };
  const requested = query.get('scene');
  return { active: true, ...(requested ? { scene: sceneId(requested) } : {}) };
}

export function formatSceneStudioRoute(route: SceneStudioRoute, currentSearch = ''): string {
  const query = new URLSearchParams(currentSearch.startsWith('?') ? currentSearch.slice(1) : currentSearch);
  if (!route.active) { query.delete('studio'); query.delete('scene'); }
  else {
    query.set('studio', 'scenes');
    if (route.scene) query.set('scene', route.scene);
    else query.delete('scene');
  }
  const value = query.toString();
  return value ? `?${value}` : '';
}
