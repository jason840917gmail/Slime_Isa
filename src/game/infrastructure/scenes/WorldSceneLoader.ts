import { sceneId, type SceneId } from '../../content/scenes/identifiers';
import { MAP_FORMAT_VERSION, type MapDirection, type MapFile, type MapId, type MapLayer, type MapPoint } from '../../content/maps/mapFormat';
import type { CollisionShapeResourceDocument, JsonValue, TileDataResourceDocument } from '../../content/scenes/resources/types';
import { enemySpawnPerimeterIssues, perimeterFromCollisionShape, type WorldAreaTransform } from '../../content/scenes/worldAreaGeometry';
import { parseTileMapDataResource } from '../../content/scenes/resources/TileMapDataResource';
import type { PackedNodeDocument, PackedScene } from '../../runtime/scene/PackedScene';
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
  const areaData = worldAreaData(packedScene);
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

type WorldAreaDataKind = 'enemy-safe-zone' | 'enemy-spawn' | 'npc-wander';

function isJsonRecord(value: JsonValue | undefined): value is { readonly [key: string]: JsonValue } {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

/**
 * Builds the legacy map-format area records from scene-authored world areas.
 * Settings come from the script's `data`; every perimeter comes from the
 * CollisionShape2D nodes it references, placed by their global transforms.
 */
function worldAreaData(packedScene: PackedScene): (kind: WorldAreaDataKind) => never[] {
  const { nodes, resources } = packedScene.definition;
  const byKey = new Map(nodes.map((node) => [node.key, node]));
  const shapes = new Map(resources
    .filter((resource): resource is CollisionShapeResourceDocument => resource.kind === 'collision-shape')
    .map((resource) => [resource.resourceId as string, resource.value]));
  const transforms = new Map<string, WorldAreaTransform>();
  const globalTransform = (node: PackedNodeDocument): WorldAreaTransform => {
    const cached = transforms.get(node.key);
    if (cached) return cached;
    const parent = node.parentKey ? byKey.get(node.parentKey) : undefined;
    const base: WorldAreaTransform = parent ? globalTransform(parent) : { position: [0, 0], rotation: 0, scale: [1, 1] };
    const vector = (value: JsonValue | undefined, fallback: readonly [number, number]): readonly [number, number] => (
      Array.isArray(value) && value.length === 2 && typeof value[0] === 'number' && typeof value[1] === 'number' ? [value[0], value[1]] : fallback
    );
    // Mirrors Node2D.readWorldTransform; non-2D nodes carry no transform and pass the parent's through.
    const [lx, ly] = vector(node.properties.position, [0, 0]);
    const rotation = typeof node.properties.rotation === 'number' ? node.properties.rotation : 0;
    const [sx, sy] = vector(node.properties.scale, [1, 1]);
    const scaledX = lx * base.scale[0];
    const scaledY = ly * base.scale[1];
    const cosine = Math.cos(base.rotation);
    const sine = Math.sin(base.rotation);
    const result: WorldAreaTransform = {
      position: [base.position[0] + scaledX * cosine - scaledY * sine, base.position[1] + scaledX * sine + scaledY * cosine],
      rotation: base.rotation + rotation,
      scale: [base.scale[0] * sx, base.scale[1] * sy],
    };
    transforms.set(node.key, result);
    return result;
  };
  const referenced = (script: PackedNodeDocument, key: string): PackedNodeDocument | undefined => {
    const reference = script.properties[key];
    if (!isJsonRecord(reference) || typeof reference.nodeId !== 'string') return undefined;
    // Same scoping rule SceneResolver uses when it validates node references.
    const scope = script.propertyScopes[key] ?? script.instancePath;
    const path = [...scope, ...(Array.isArray(reference.instancePath) ? reference.instancePath as string[] : []), reference.nodeId];
    return byKey.get(path.join('/'));
  };
  const perimeter = (script: PackedNodeDocument, key: string, label: string) => {
    const where = `World area '${String(script.properties.areaId ?? script.authoredNodeId)}' in '${packedScene.sourceSceneId}'`;
    const node = referenced(script, key);
    if (!node) throw new Error(`${where} requires its ${label} shape reference`);
    if (node.type !== 'CollisionShape2D') throw new Error(`${where}: ${label} must reference a CollisionShape2D`);
    const shapeReference = node.properties.shape;
    const value = isJsonRecord(shapeReference) && typeof shapeReference.resourceId === 'string' ? shapes.get(shapeReference.resourceId) : undefined;
    if (!value) throw new Error(`${where}: ${label} shape has no collision-shape resource`);
    const result = perimeterFromCollisionShape(value, globalTransform(node));
    if (!result.perimeter) throw new Error(`${where}: ${label} ${result.issue}`);
    return result.perimeter;
  };
  const scripts = nodes.filter((node) => node.scriptId === 'game.world-area');
  return (kind) => scripts
    .filter((script) => script.properties.areaKind === kind)
    .map((script) => {
      const data = isJsonRecord(script.properties.data) ? structuredClone(script.properties.data) : {};
      const id = typeof script.properties.areaId === 'string' ? script.properties.areaId : script.authoredNodeId;
      const outer = perimeter(script, 'shape', 'perimeter');
      if (kind === 'enemy-safe-zone') {
        if (outer.shape !== 'rectangle') throw new Error(`World area '${id}' in '${packedScene.sourceSceneId}': safe zones must be rectangles`);
        return { x: outer.x, y: outer.y, w: outer.w, h: outer.h };
      }
      if (kind === 'npc-wander') return { ...data, id, perimeter: outer };
      const stay = perimeter(script, 'stayShape', 'stay');
      const issues = enemySpawnPerimeterIssues(stay, outer);
      if (issues.length > 0) throw new Error(`World area '${id}' in '${packedScene.sourceSceneId}': ${issues.join('; ')}`);
      return { ...data, id, stayPerimeter: stay, pursuePerimeter: outer };
    }) as never[];
}

function throwIfAborted(signal?: AbortSignal): void {
  if (!signal?.aborted) return;
  const error = new Error('World scene load was aborted');
  error.name = 'AbortError';
  throw error;
}
