import { sceneId, type SceneId } from '../../content/scenes/identifiers';
import { formatSceneStudioRoute } from './SceneStudioRoute';

const LEGACY_STUDIOS = new Set(['characters', 'weapons', 'projectiles', 'animations']);
const LEGACY_CONTEXT_KEYS = ['character', 'weapon', 'projectile', 'animation', 'slot', 'direction', 'editor'];

function selectedScene(query: URLSearchParams, studio: string): SceneId | undefined {
  const contexts = studio === 'characters'
    ? [['character', 'character']]
    : studio === 'weapons'
      ? [['weapon', 'weapon']]
      : studio === 'projectiles'
        ? [['projectile', 'projectile']]
        : [['character', 'character'], ['weapon', 'weapon'], ['projectile', 'projectile']];
  for (const [key, prefix] of contexts) {
    const stableId = query.get(key)?.trim();
    if (stableId) return sceneId(`${prefix}.${stableId}`);
  }
  return undefined;
}

export function redirectLegacyStudioRoute(search: string): string | undefined {
  const query = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  const studio = query.get('studio');
  if (studio && LEGACY_STUDIOS.has(studio)) {
    const scene = selectedScene(query, studio);
    for (const key of LEGACY_CONTEXT_KEYS) query.delete(key);
    return formatSceneStudioRoute({ active: true, ...(scene ? { scene } : {}) }, query.toString());
  }
  const mapId = query.get('editor')?.trim();
  if (!mapId) return undefined;
  query.delete('editor');
  return formatSceneStudioRoute({
    active: true,
    scene: studio === 'scenes' && query.has('scene')
      ? sceneId(query.get('scene')!)
      : sceneId(`world.${mapId}`),
  }, query.toString());
}

export function redirectLegacyCharacterStudioRoute(search: string): string | undefined {
  const query = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  return query.get('studio') === 'characters' ? redirectLegacyStudioRoute(search) : undefined;
}
