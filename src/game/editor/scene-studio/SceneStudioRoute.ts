import { sceneId, type SceneId } from '../../content/scenes/identifiers';

export interface SceneStudioRoute {
  readonly active: boolean;
  readonly scene?: SceneId;
}

export function redirectLegacyCharacterStudioRoute(search: string): string | undefined {
  const query = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  if (query.get('studio') !== 'characters') return undefined;
  const character = query.get('character')?.trim();
  query.delete('character');
  return formatSceneStudioRoute({
    active: true,
    ...(character ? { scene: sceneId(`character.${character}`) } : {}),
  }, query.toString());
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
