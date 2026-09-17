import { sceneId, type SceneId } from '../../content/scenes/identifiers';
import type { MapId } from '../../content/maps/mapFormat';
import type { PackedScene } from '../../runtime/scene/PackedScene';
import type { LoadedMap } from '../maps/MapRepository';

export interface WorldMapSource {
  load(mapId: MapId, signal?: AbortSignal): Promise<LoadedMap | null>;
}

export interface WorldSceneSource {
  ensure(sceneId: SceneId, signal?: AbortSignal): Promise<PackedScene>;
}

export interface LoadedWorldScene {
  readonly mapId: MapId;
  readonly sceneId: SceneId;
  readonly loadedMap: LoadedMap;
  readonly packedScene: PackedScene;
}

/**
 * Resolves every immutable input required for a world before the active Phaser
 * scene is allowed to change. Neither source is installed by this loader, so a
 * missing, invalid, failed, or cancelled destination cannot partially commit.
 */
export class WorldSceneLoader {
  constructor(
    private readonly maps: WorldMapSource,
    private readonly scenes: WorldSceneSource,
  ) {}

  async load(mapId: MapId, signal?: AbortSignal): Promise<LoadedWorldScene> {
    throwIfAborted(signal);
    const loadedMap = await this.maps.load(mapId, signal);
    throwIfAborted(signal);
    if (!loadedMap) {
      throw new Error(`Required authored map '${mapId}' was not found in src/game/content/maps`);
    }
    if (loadedMap.map.mapId !== mapId) {
      throw new Error(`World load requested map '${mapId}' but resolved '${loadedMap.map.mapId}'`);
    }

    const authoredSceneId = sceneId(`world.${mapId}`);
    const packedScene = await this.scenes.ensure(authoredSceneId, signal);
    throwIfAborted(signal);
    if (packedScene.definition.sourceSceneId !== authoredSceneId) {
      throw new Error(`World load requested scene '${authoredSceneId}' but resolved '${packedScene.definition.sourceSceneId}'`);
    }
    return { mapId, sceneId: authoredSceneId, loadedMap, packedScene };
  }
}

function throwIfAborted(signal?: AbortSignal): void {
  if (!signal?.aborted) return;
  const error = new Error('World scene load was aborted');
  error.name = 'AbortError';
  throw error;
}
