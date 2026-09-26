import { resourceId, sceneId, type ResourceId, type SceneId } from '../../content/scenes/identifiers';

export interface SceneStudioRoute {
  readonly active: boolean;
  readonly scene?: SceneId;
  readonly resource?: ResourceId;
}

export { redirectLegacyStudioRoute, redirectLegacyCharacterStudioRoute } from './LegacyRouteRedirects';

export function parseSceneStudioRoute(search: string): SceneStudioRoute {
  const query = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  if (query.get('studio') !== 'scenes') return { active: false };
  const requested = query.get('scene');
  const requestedResource = query.get('resource');
  return { active: true, ...(requested ? { scene: sceneId(requested) } : {}), ...(requestedResource ? { resource: resourceId(requestedResource) } : {}) };
}

export function formatSceneStudioRoute(route: SceneStudioRoute, currentSearch = ''): string {
  const query = new URLSearchParams(currentSearch.startsWith('?') ? currentSearch.slice(1) : currentSearch);
  if (!route.active) { query.delete('studio'); query.delete('scene'); query.delete('resource'); }
  else {
    query.set('studio', 'scenes');
    if (route.scene) query.set('scene', route.scene);
    else query.delete('scene');
    if (route.resource) query.set('resource', route.resource);
    else query.delete('resource');
  }
  const value = query.toString();
  return value ? `?${value}` : '';
}
