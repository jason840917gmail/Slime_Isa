import { parseMapFile, type MapFile, type MapId } from '../../content/maps/mapFormat';
import { getObjectArchetype, hasObjectVisual, isObjectArchetypeId } from '../../content/objects/ObjectCatalog';
import { getCharacterPackage } from '../../content/characters/CharacterCatalog';
import { getNpcDefinition } from '../../content/npcs/NpcCatalog';
import { validateMapReferences as validatePureMapReferences } from '../../content/maps/validateMapReferences';
import { browserMapReferenceResolver } from './BrowserMapReferenceResolver';
import { validateObjectInitialState } from '../../content/objects/ObjectInitialState';
import { isWorldTileId } from '../../content/terrain/TileCatalog';
import { ENEMY_CONFIGS } from '../../enemies/library/EnemyTypes';
import type { Direction } from '../../world/Area';
import { dimensionsFromMap, type WorldDimensions } from '../../world/WorldDimensions';

interface JsonModule {
  readonly default: unknown;
}

export interface LoadedMap {
  readonly map: MapFile;
  readonly dimensions: WorldDimensions;
}

const MAP_MODULES = import.meta.glob<JsonModule>('/src/game/content/maps/*.map.json');
const DIRECTIONS = new Set<Direction>(['north', 'east', 'south', 'west']);

function abortError(): Error {
  const error = new Error('Map load was aborted');
  error.name = 'AbortError';
  return error;
}

function awaitAbortable<T>(promise: Promise<T>, signal?: AbortSignal): Promise<T> {
  if (!signal) return promise;
  if (signal.aborted) return Promise.reject(abortError());
  return new Promise<T>((resolve, reject) => {
    const onAbort = (): void => reject(abortError());
    signal.addEventListener('abort', onAbort, { once: true });
    promise.then(
      (value) => {
        signal.removeEventListener('abort', onAbort);
        if (signal.aborted) reject(abortError());
        else resolve(value);
      },
      (error: unknown) => {
        signal.removeEventListener('abort', onAbort);
        reject(error);
      },
    );
  });
}

export function getAuthoredMapIds(): readonly MapId[] {
  return Object.keys(MAP_MODULES)
    .map((modulePath) => modulePath.split('/').pop()?.replace(/\.map\.json$/, ''))
    .filter((mapId): mapId is string => Boolean(mapId))
    .sort();
}

export class MapReferenceError extends Error {
  constructor(
    public readonly mapId: MapId,
    public readonly issues: readonly string[],
  ) {
    super(`Invalid map references '${mapId}':\n  - ${issues.join('\n  - ')}`);
    this.name = 'MapReferenceError';
  }
}

function validateReferences(map: MapFile): void {
  const issues: string[] = [];

  issues.push(...validatePureMapReferences(map, browserMapReferenceResolver));

  map.layers.forEach((layer, layerIndex) => {
    for (const [token, tileId] of Object.entries(layer.legend)) {
      if (!isWorldTileId(tileId)) {
        issues.push(`layers[${layerIndex}].legend['${token}']: unknown tile ID '${tileId}'`);
      }
    }
  });

  map.objects.forEach((object, objectIndex) => {
    if (!isObjectArchetypeId(object.objectId)) {
      issues.push(`objects[${objectIndex}].objectId: unknown object ID '${object.objectId}'`);
    } else {
      const definition = getObjectArchetype(object.objectId);
      const npc = definition.npc;
      const validVisual = npc
        ? (() => {
          const npcDefinition = getNpcDefinition(npc.definitionId);
          if (!npcDefinition || object.visualId !== npc.placementVisualId) return false;
          try { getCharacterPackage(npcDefinition.characterId); return true; } catch { return false; }
        })()
        : hasObjectVisual(object.objectId, object.visualId);
      if (!validVisual) {
        issues.push(`objects[${objectIndex}].visualId: unknown visual '${object.visualId}' for '${object.objectId}'`);
      } else {
        for (const issue of validateObjectInitialState(object.objectId, object.initialState)) {
          issues.push(`objects[${objectIndex}].${issue}`);
        }
      }
    }
  });

  map.spawns?.enemies.forEach((enemy, enemyIndex) => {
    if (!(enemy.type in ENEMY_CONFIGS)) {
      issues.push(`spawns.enemies[${enemyIndex}].type: unknown enemy ID '${enemy.type}'`);
    }
  });

  map.enemySpawnAreas?.forEach((area, areaIndex) => {
    area.enemies.forEach((enemy, enemyIndex) => {
      if (!(enemy.type in ENEMY_CONFIGS)) {
        issues.push(`enemySpawnAreas[${areaIndex}].enemies[${enemyIndex}].type: unknown enemy ID '${enemy.type}'`);
      }
    });
  });

  map.exits?.forEach((exit, exitIndex) => {
    if (!MAP_MODULES[`/src/game/content/maps/${exit.to}.map.json`]) {
      issues.push(`exits[${exitIndex}].to: unknown authored map '${exit.to}'`);
      return;
    }
    if (!DIRECTIONS.has(exit.entry as Direction)) {
      issues.push(`exits[${exitIndex}].entry: expected north/east/south/west`);
    }
  });

  if (issues.length > 0) throw new MapReferenceError(map.mapId, issues);
}

export class MapRepository {
  private readonly cache = new Map<MapId, Promise<LoadedMap | null>>();

  load(mapId: MapId, signal?: AbortSignal): Promise<LoadedMap | null> {
    const cached = this.cache.get(mapId);
    if (cached) return awaitAbortable(cached, signal);

    const pending = this.loadUncached(mapId);
    this.cache.set(mapId, pending);
    void pending.catch(() => {
      if (this.cache.get(mapId) === pending) this.cache.delete(mapId);
    });
    return awaitAbortable(pending, signal);
  }

  private async loadUncached(mapId: MapId): Promise<LoadedMap | null> {
    const loadModule = MAP_MODULES[`/src/game/content/maps/${mapId}.map.json`];
    if (!loadModule) return null;

    const module = await loadModule();
    const map = parseMapFile(module.default, mapId);
    if (map.mapId !== mapId) {
      throw new MapReferenceError(mapId, [`mapId: file requested as '${mapId}' but declares '${map.mapId}'`]);
    }
    validateReferences(map);

    return {
      map,
      dimensions: dimensionsFromMap(map),
    };
  }
}

export const mapRepository = new MapRepository();
