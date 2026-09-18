import { sceneId, type SceneId } from '../../content/scenes/identifiers';
import { MAP_FORMAT_VERSION, type MapDirection, type MapFile, type MapId, type MapLayer, type MapPoint } from '../../content/maps/mapFormat';
import type { TileDataResourceDocument } from '../../content/scenes/resources/types';
import { parseTileMapDataResource } from '../../content/scenes/resources/TileMapDataResource';
import type { PackedScene } from '../../runtime/scene/PackedScene';
import { dimensionsFromMap, type WorldDimensions } from '../../world/WorldDimensions';

export interface LoadedWorldMap {
  readonly map: MapFile;
  readonly dimensions: WorldDimensions;
}

export interface WorldSceneSource {
  ensure(sceneId: SceneId, signal?: AbortSignal): Promise<PackedScene>;
}

export interface LoadedWorldScene {
  readonly mapId: MapId;
  readonly sceneId: SceneId;
  readonly loadedMap: LoadedWorldMap;
  readonly packedScene: PackedScene;
}

/**
 * Resolves every immutable input required for a world before the active Phaser
 * scene is allowed to change. Neither source is installed by this loader, so a
 * missing, invalid, failed, or cancelled destination cannot partially commit.
 */
export class WorldSceneLoader {
  constructor(private readonly scenes: WorldSceneSource) {}

  async load(mapId: MapId, signal?: AbortSignal): Promise<LoadedWorldScene> {
    throwIfAborted(signal);
    const authoredSceneId = sceneId(`world.${mapId}`);
    const packedScene = await this.scenes.ensure(authoredSceneId, signal);
    throwIfAborted(signal);
    if (packedScene.definition.sourceSceneId !== authoredSceneId) {
      throw new Error(`World load requested scene '${authoredSceneId}' but resolved '${packedScene.definition.sourceSceneId}'`);
    }
    const loadedMap = loadedMapFromScene(packedScene);
    if (loadedMap.map.mapId !== mapId) {
      throw new Error(`World load requested map '${mapId}' but scene defines '${loadedMap.map.mapId}'`);
    }
    return { mapId, sceneId: authoredSceneId, loadedMap, packedScene };
  }
}

function loadedMapFromScene(packedScene: PackedScene): LoadedWorldMap {
  const definition = packedScene.definition.nodes.find((node) => node.scriptId === 'game.world-definition');
  if (!definition) throw new Error(`World scene '${packedScene.sourceSceneId}' requires a game.world-definition script`);
  const { mapId, tileSize, columns, rows, metadata } = definition.properties;
  if (typeof mapId !== 'string' || !Number.isSafeInteger(tileSize) || !Number.isSafeInteger(columns) || !Number.isSafeInteger(rows)
    || !metadata || typeof metadata !== 'object' || Array.isArray(metadata)) {
    throw new Error(`World scene '${packedScene.sourceSceneId}' has invalid world-definition properties`);
  }
  const resolvedTileSize = tileSize as number;
  const resolvedColumns = columns as number;
  const resolvedRows = rows as number;
  const tileResources = new Map(packedScene.definition.resources
    .filter((resource): resource is TileDataResourceDocument => resource.kind === 'tile-data')
    .map((resource) => [resource.resourceId, resource]));
  const layers: MapLayer[] = packedScene.definition.nodes
    .filter((node) => node.type === 'TileMapLayer2D')
    .sort((left, right) => left.order - right.order)
    .map((node) => {
      const reference = node.properties.tileData;
      const resourceId = reference && typeof reference === 'object' && !Array.isArray(reference) && 'resourceId' in reference
        ? reference.resourceId : undefined;
      const resource = typeof resourceId === 'string' ? tileResources.get(resourceId as TileDataResourceDocument['resourceId']) : undefined;
      if (!resource) throw new Error(`World layer '${node.authoredNodeId}' requires packed tile-data`);
      const tileData = parseTileMapDataResource(resource);
      const tileIds = [...new Set(tileData.cells.map((cell) => cell.tileId))].sort();
      const tokens = new Map(tileIds.map((tileId, index) => [tileId, String.fromCharCode(0xe000 + index)]));
      const grid = Array.from({ length: tileData.rows }, () => Array.from({ length: tileData.columns }, () => tokens.get(tileIds[0]) ?? '\ue000'));
      for (const cell of tileData.cells) grid[cell.y][cell.x] = tokens.get(cell.tileId)!;
      return {
        id: node.name,
        encoding: 'legend-chars-v1',
        legend: Object.fromEntries([...tokens].map(([tileId, token]) => [token, tileId])),
        rows: grid.map((row) => row.join('')),
      };
    });
  if (layers.length === 0) throw new Error(`World scene '${packedScene.sourceSceneId}' requires a TileMapLayer2D`);
  const worldData = structuredClone(metadata) as unknown as Omit<MapFile, 'version' | 'mapId' | 'tileSize' | 'size' | 'layers'>;
  const markerPoint = (authoredNodeId: string): MapPoint | undefined => {
    const value = packedScene.definition.nodes.find((node) => node.authoredNodeId === authoredNodeId)?.properties.position;
    return Array.isArray(value) && value.length === 2 && value.every((coordinate) => typeof coordinate === 'number')
      ? { x: value[0] as number, y: value[1] as number } : undefined;
  };
  const spawn = markerPoint('player-spawn');
  if (!spawn) throw new Error(`World scene '${packedScene.sourceSceneId}' requires a player-spawn marker`);
  const entries = Object.fromEntries((['north', 'east', 'south', 'west'] as const)
    .map((direction) => [direction, markerPoint(`player-entry-${direction}`)] as const)
    .filter((entry): entry is readonly [MapDirection, MapPoint] => entry[1] !== undefined));
  const authoredAreas = packedScene.definition.nodes.filter((node) => node.scriptId === 'game.world-area');
  const areaData = (kind: string) => authoredAreas
    .filter((node) => node.properties.areaKind === kind)
    .map((node) => structuredClone(node.properties.data)) as never[];
  const map = {
    version: MAP_FORMAT_VERSION,
    mapId,
    tileSize: resolvedTileSize,
    size: { columns: resolvedColumns, rows: resolvedRows },
    layers,
    ...worldData,
    player: { spawn, entries },
    enemySafeZones: areaData('enemy-safe-zone'),
    enemySpawnAreas: areaData('enemy-spawn'),
    npcWanderAreas: areaData('npc-wander'),
  } satisfies MapFile;
  return { map, dimensions: dimensionsFromMap(map) };
}

function throwIfAborted(signal?: AbortSignal): void {
  if (!signal?.aborted) return;
  const error = new Error('World scene load was aborted');
  error.name = 'AbortError';
  throw error;
}
