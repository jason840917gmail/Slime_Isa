import ts from 'typescript';
import { collision } from './collision-layers.mjs';

import { convertedOutput, readJson } from './adapter-utils.mjs';
import { TERRAIN_TILE_SET_ID } from './terrain.mjs';

function slug(value) {
  return value.replaceAll('.', '-').replace(/[^a-z0-9-]+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
}

async function typescriptModule(readSource, sourcePath) {
  const source = await readSource(sourcePath);
  const output = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
    fileName: sourcePath,
  }).outputText;
  const encoded = Buffer.from(output).toString('base64');
  return import(`data:text/javascript;base64,${encoded}`);
}

async function typescriptExport(readSource, sourcePath, exportName) {
  const loaded = await typescriptModule(readSource, sourcePath);
  if (!(exportName in loaded)) throw new Error(`TypeScript source '${sourcePath}' does not export '${exportName}'`);
  return loaded[exportName];
}

function fallbackSeed(mapId) {
  return [...mapId].reduce((hash, character) => ((hash * 31) + character.charCodeAt(0)) >>> 0, 0);
}

const ENTRY_DIRECTIONS = ['north', 'east', 'south', 'west'];

function retainedMapFields(unit, map, consumedKeys = []) {
  const consumed = new Set(consumedKeys);
  return Object.keys(map)
    .filter((key) => !['mapId', 'tileSize', 'size', 'layers', 'objects', 'bossCamps'].includes(key) && !consumed.has(key))
    .sort()
    .map((key) => ({ path: `$.${key}`, owner: unit.oldSourcePath }));
}

function override(sourceNodeId, property, value) {
  return { sourceInstancePath: [], sourceNodeId, property, value };
}

function chestContents(initialState, mapId, instanceId) {
  if (initialState?.contents === undefined) return undefined;
  if (!Array.isArray(initialState.contents)) {
    throw new Error(`Map '${mapId}' chest '${instanceId}' initialState.contents must be an array`);
  }
  const contents = {};
  for (const [index, stack] of initialState.contents.entries()) {
    if (!stack || typeof stack !== 'object' || typeof stack.itemId !== 'string'
      || !Number.isSafeInteger(stack.quantity) || stack.quantity < 1) {
      throw new Error(`Map '${mapId}' chest '${instanceId}' contents[${index}] is invalid`);
    }
    contents[stack.itemId] = (contents[stack.itemId] ?? 0) + stack.quantity;
  }
  return contents;
}

function objectInstanceOverrides(map, instance, mapping) {
  const overrides = [override(mapping.rootNodeId, 'position', [instance.x, instance.y])];
  if (!mapping.scriptNodeId) return overrides;
  overrides.push(
    override(mapping.scriptNodeId, 'mapId', map.mapId),
    override(mapping.scriptNodeId, 'instanceId', instance.instanceId),
  );
  if (mapping.npcDefinitionId) overrides.push(override(mapping.scriptNodeId, 'npcDefinitionId', mapping.npcDefinitionId));
  if (instance.objectId === 'chest.wooden') {
    const contents = chestContents(instance.initialState, map.mapId, instance.instanceId);
    if (contents) overrides.push(override(mapping.scriptNodeId, 'initialContents', contents));
  }
  if (typeof instance.initialState?.health === 'number') {
    overrides.push(override(mapping.scriptNodeId, 'initialHealth', instance.initialState.health));
  }
  return overrides;
}

function navigationContent(map, firstOrder) {
  const nodes = [];
  const subresources = [];
  const connections = [];
  const mappings = [];
  let order = firstOrder;

  const addMarker = (id, sourcePath, point, sourceKind, direction) => {
    nodes.push({
      id,
      name: id,
      type: 'Node2D',
      parentId: 'world',
      order: order++,
      properties: { position: [point.x, point.y] },
    });
    mappings.push({
      sourceKind,
      sourcePath,
      nodeId: id,
      position: [point.x, point.y],
      ...(direction ? { direction } : {}),
    });
  };

  addMarker('player-spawn', '$.player.spawn', map.player.spawn, 'player-spawn');
  for (const direction of ENTRY_DIRECTIONS) {
    const point = map.player.entries[direction];
    if (point) addMarker(`player-entry-${direction}`, `$.player.entries.${direction}`, point, 'player-entry', direction);
  }

  for (const [index, exit] of (map.exits ?? []).entries()) {
    const exitId = `exit-${index + 1}`;
    const shapeId = `${exitId}-shape`;
    const scriptId = `${exitId}-script`;
    const shapeResourceId = `${map.mapId}.${exitId}.shape`;
    const position = [exit.zone.x + (exit.zone.w / 2), exit.zone.y + (exit.zone.h / 2)];
    const gate = exit.gate ?? {};
    nodes.push(
      {
        id: exitId,
        name: exitId,
        type: 'Area2D',
        parentId: 'world',
        order: order++,
        properties: {
          position,
          ...collision(['trigger'], ['player', 'npc']),
          monitoring: true,
          monitorable: false,
        },
      },
      {
        id: shapeId,
        name: 'collision-shape',
        type: 'CollisionShape2D',
        parentId: exitId,
        order: 0,
        properties: { shape: { resourceId: shapeResourceId } },
      },
      {
        id: scriptId,
        name: 'world-exit-script',
        type: 'ScriptNode',
        scriptId: 'game.world-exit',
        parentId: exitId,
        order: 1,
        properties: {
          mapId: map.mapId,
          exitId,
          targetAreaId: exit.to,
          entry: exit.entry,
          area: { nodeId: exitId },
          gate,
        },
      },
    );
    subresources.push({
      version: 1,
      resourceId: shapeResourceId,
      kind: 'collision-shape',
      value: { shape: 'rectangle', width: exit.zone.w, height: exit.zone.h },
    });
    connections.push({
      source: { nodeId: exitId },
      signal: 'body_entered',
      target: { nodeId: scriptId },
      handler: 'on_body_entered',
    });
    mappings.push({
      sourceKind: 'exit',
      sourcePath: `$.exits[${index}]`,
      sourceId: exitId,
      areaNodeId: exitId,
      shapeNodeId: shapeId,
      scriptNodeId: scriptId,
      position,
      zone: exit.zone,
      targetAreaId: exit.to,
      entry: exit.entry,
      gate,
    });
  }

  const expectedMarkerCount = 1 + Object.keys(map.player.entries).length;
  const markerCount = mappings.filter((mapping) => mapping.sourceKind !== 'exit').length;
  const exitCount = mappings.filter((mapping) => mapping.sourceKind === 'exit').length;
  if (markerCount !== expectedMarkerCount || exitCount !== (map.exits?.length ?? 0)) {
    throw new Error(`Map '${map.mapId}' lost navigation content during conversion`);
  }
  const sourcePaths = mappings.map((mapping) => mapping.sourcePath);
  if (new Set(sourcePaths).size !== sourcePaths.length) {
    throw new Error(`Map '${map.mapId}' duplicates a navigation source during conversion`);
  }

  return { nodes, subresources, connections, mappings, rootChildCount: order - firstOrder };
}

function worldAreaContent(map, firstOrder) {
  const nodes = [];
  const subresources = [];
  const mappings = [];
  let order = firstOrder;
  // Perimeters live on CollisionShape2D nodes (shape / stayShape); `data` keeps only settings.
  const shapeOf = (perimeter) => {
    const rectangle = perimeter.shape === 'rectangle' || perimeter.w !== undefined;
    return {
      center: rectangle ? [perimeter.x + perimeter.w / 2, perimeter.y + perimeter.h / 2] : [perimeter.x, perimeter.y],
      value: rectangle ? { shape: 'rectangle', width: perimeter.w, height: perimeter.h } : { shape: 'circle', radius: perimeter.radius },
    };
  };
  const addArea = (id, kind, sourcePath, perimeter, data, stayPerimeter) => {
    const areaNodeId = `area-${id}`;
    const shapeNodeId = `${areaNodeId}-shape`;
    const stayNodeId = `${areaNodeId}-stay-shape`;
    const scriptNodeId = `${areaNodeId}-script`;
    const shapeResourceId = `${map.mapId}.${areaNodeId}.shape`;
    const stayResourceId = `${map.mapId}.${areaNodeId}.stay-shape`;
    const outer = shapeOf(perimeter);
    const position = outer.center;
    const stay = stayPerimeter ? shapeOf(stayPerimeter) : undefined;
    const offset = (center) => {
      const local = [center[0] - position[0], center[1] - position[1]];
      return local[0] === 0 && local[1] === 0 ? {} : { position: local };
    };
    nodes.push(
      { id: areaNodeId, name: id, type: 'Area2D', parentId: 'world', order: order++, properties: {
        position, ...collision(['trigger'], []), monitoring: false, monitorable: false,
      } },
      { id: shapeNodeId, name: stay ? 'pursue-shape' : 'collision-shape', type: 'CollisionShape2D', parentId: areaNodeId, order: 0, properties: { shape: { resourceId: shapeResourceId } } },
      ...(stay ? [{ id: stayNodeId, name: 'stay-shape', type: 'CollisionShape2D', parentId: areaNodeId, order: 1, properties: { ...offset(stay.center), shape: { resourceId: stayResourceId } } }] : []),
      { id: scriptNodeId, name: 'world-area-script', type: 'ScriptNode', scriptId: 'game.world-area', parentId: areaNodeId, order: stay ? 2 : 1, properties: {
        areaKind: kind, areaId: id, area: { nodeId: areaNodeId }, shape: { nodeId: shapeNodeId },
        ...(stay ? { stayShape: { nodeId: stayNodeId } } : {}), data,
      } },
    );
    subresources.push({ version: 1, resourceId: shapeResourceId, kind: 'collision-shape', value: outer.value });
    if (stay) subresources.push({ version: 1, resourceId: stayResourceId, kind: 'collision-shape', value: stay.value });
    mappings.push({ sourceKind: kind, sourcePath, sourceId: id, areaNodeId, shapeNodeId, scriptNodeId, position });
  };
  for (const [index, zone] of (map.enemySafeZones ?? []).entries()) {
    addArea(`enemy-safe-${index + 1}`, 'enemy-safe-zone', `$.enemySafeZones[${index}]`, zone, {});
  }
  for (const [index, area] of (map.enemySpawnAreas ?? []).entries()) {
    const { id: _id, stayPerimeter, pursuePerimeter, ...settings } = area;
    addArea(area.id, 'enemy-spawn', `$.enemySpawnAreas[${index}]`, pursuePerimeter, settings, stayPerimeter);
  }
  for (const [index, area] of (map.npcWanderAreas ?? []).entries()) {
    const { id: _id, perimeter, ...settings } = area;
    addArea(area.id, 'npc-wander', `$.npcWanderAreas[${index}]`, perimeter, settings);
  }
  return { nodes, subresources, mappings, rootChildCount: order - firstOrder };
}

function worldPlacements(map, mappingModule, firstOrder) {
  const instances = [];
  const placements = [];
  const claimedIds = new Set();
  const guardedChestOwners = new Map();
  let order = firstOrder;

  for (const camp of map.bossCamps ?? []) {
    const sceneId = mappingModule.resolveLegacyBossCampScene(camp.id);
    if (!sceneId) throw new Error(`Map '${map.mapId}' boss camp '${camp.id}' has no encounter scene mapping`);
    if (claimedIds.has(camp.id)) throw new Error(`Map '${map.mapId}' duplicates world placement '${camp.id}'`);
    claimedIds.add(camp.id);
    if (camp.guardedChestInstanceId) guardedChestOwners.set(camp.guardedChestInstanceId, camp.id);
    instances.push({
      instanceId: camp.id,
      name: camp.id,
      sceneId,
      parentNodeId: 'world',
      order: order++,
      persistenceKey: camp.id,
      overrides: [override('root', 'position', [camp.activationPerimeter.x, camp.activationPerimeter.y])],
    });
    placements.push({
      sourceKind: 'boss-camp', sourceId: camp.id, ownership: 'world-instance',
      instanceId: camp.id, sceneId, persistenceKey: camp.id,
    });
  }

  for (const object of map.objects) {
    const campId = guardedChestOwners.get(object.instanceId);
    if (campId) {
      placements.push({
        sourceKind: 'object', sourceId: object.instanceId, objectId: object.objectId, visualId: object.visualId,
        ownership: 'encounter-instance', owningInstanceId: campId,
        sceneId: mappingModule.resolveLegacyMapObjectScene(object)?.sceneId,
        persistenceKey: `${map.mapId}.${object.instanceId}`,
        initialState: object.initialState ?? {},
      });
      continue;
    }
    const mapping = mappingModule.resolveLegacyMapObjectScene(object);
    if (!mapping) throw new Error(`Map '${map.mapId}' object '${object.instanceId}' (${object.objectId}/${object.visualId}) has no scene mapping`);
    if (claimedIds.has(object.instanceId)) throw new Error(`Map '${map.mapId}' duplicates world placement '${object.instanceId}'`);
    claimedIds.add(object.instanceId);
    const persistenceKey = `${map.mapId}.${object.instanceId}`;
    instances.push({
      instanceId: object.instanceId,
      name: object.instanceId,
      sceneId: mapping.sceneId,
      parentNodeId: 'world',
      order: order++,
      persistenceKey,
      overrides: objectInstanceOverrides(map, object, mapping),
    });
    placements.push({
      sourceKind: 'object', sourceId: object.instanceId, objectId: object.objectId, visualId: object.visualId,
      ownership: 'world-instance', instanceId: object.instanceId, sceneId: mapping.sceneId,
      persistenceKey, initialState: object.initialState ?? {},
      ...(mapping.npcDefinitionId ? { npcDefinitionId: mapping.npcDefinitionId } : {}),
    });
  }

  for (const [chestId, campId] of guardedChestOwners) {
    if (!map.objects.some((object) => object.instanceId === chestId)) {
      throw new Error(`Map '${map.mapId}' boss camp '${campId}' guards missing object '${chestId}'`);
    }
  }
  if (placements.length !== (map.bossCamps?.length ?? 0) + map.objects.length) {
    throw new Error(`Map '${map.mapId}' lost a world placement during conversion`);
  }
  return { instances, placements };
}

export const mapSceneAdapter = {
  async convert({ units, readSource }) {
    const tileCatalog = await typescriptExport(readSource, 'scripts/migrations/frozen-sources/TileCatalog.ts', 'TILE_CATALOG');
    // Tiles authored after the freeze exist only in the shared TileSet resource.
    const tileSet = await readJson(readSource, 'src/game/content/scenes/authored/resources/terrain/terrain.tile-set.resource.json');
    const areas = await typescriptExport(readSource, 'src/game/world/Area.ts', 'AREAS');
    const placementMapping = await typescriptModule(readSource, 'src/game/infrastructure/scenes/compatibility/LegacyMapPlacementMapping.ts');
    const outputs = [];
    for (const unit of units) {
      if (unit.family !== 'map' || !unit.key.startsWith('map:')) throw new Error(`Map adapter does not support unit '${unit.key}'`);
      const map = await readJson(readSource, unit.oldSourcePath);
      if (map.mapId !== unit.stableId) throw new Error(`Map unit '${unit.key}' loaded mismatched map '${map.mapId}'`);
      const mapSlug = slug(map.mapId);
      const seed = Object.values(areas).find((area) => area.mapId === map.mapId)?.seed ?? fallbackSeed(map.mapId);
      const layerNodes = [];
      const retained = retainedMapFields(unit, map);
      const navigationRetained = retainedMapFields(unit, map, ['player', 'exits', 'enemySafeZones', 'enemySpawnAreas', 'npcWanderAreas', 'spawns']);

      map.layers.forEach((layer, layerIndex) => {
        const layerSlug = slug(layer.id);
        const tileDataId = `tiles.${mapSlug}.${layerSlug}.data`;
        const usedTileIds = [...new Set(layer.rows.flatMap((row) => [...row].map((character) => layer.legend[character])))].sort();
        for (const tileId of usedTileIds) {
          if (!tileCatalog[tileId] && !tileSet.tiles?.[tileId]) throw new Error(`Map '${map.mapId}' layer '${layer.id}' references unknown tile '${tileId}'`);
        }
        const cells = layer.rows.flatMap((row, y) => [...row].map((character, x) => ({ x, y, tileId: layer.legend[character] })));
        // Every map layer paints with the one shared terrain TileSet.
        const tileData = {
          version: 1,
          resourceId: tileDataId,
          kind: 'tile-data',
          tileSet: TERRAIN_TILE_SET_ID,
          columns: map.size.columns,
          rows: map.size.rows,
          cells,
        };
        outputs.push(convertedOutput(
          unit,
          `resources/tiles/${mapSlug}.${layerSlug}.tile-data.resource.json`,
          tileData,
          ['$.layers', '$.size'],
          retained,
        ));
        layerNodes.push({
          id: `layer-${layerSlug}`,
          name: layer.id,
          type: 'TileMapLayer2D',
          parentId: 'world',
          order: layerIndex,
          properties: {
            position: [0, 0],
            tileData: { resourceId: tileDataId },
            tileSize: map.tileSize,
            seed,
            depth: layerIndex,
            ...collision(['world'], []),
            collisionEnabled: true,
            editorLocked: false,
          },
        });
      });

      const worldMetadata = {
        objects: [],
        player: map.player,
        ...(map.spawns ? { spawns: map.spawns } : {}),
      };
      const definitionNode = {
        id: 'world-definition',
        name: 'world-definition',
        type: 'ScriptNode',
        scriptId: 'game.world-definition',
        parentId: 'world',
        order: layerNodes.length,
        properties: {
          mapId: map.mapId,
          tileSize: map.tileSize,
          columns: map.size.columns,
          rows: map.size.rows,
          metadata: worldMetadata,
        },
      };
      const areasContent = worldAreaContent(map, layerNodes.length + 1);
      const navigation = navigationContent(map, layerNodes.length + 1 + areasContent.rootChildCount);
      const rootChildCount = layerNodes.length + 1 + areasContent.rootChildCount + navigation.rootChildCount;
      const world = worldPlacements(map, placementMapping, rootChildCount);

      const scene = {
        version: 1,
        sceneId: `world.${mapSlug}`,
        rootNodeId: 'world',
        nodes: [
          { id: 'world', name: map.mapId, type: 'Node2D', parentId: null, order: 0, properties: { position: [0, 0] } },
          ...layerNodes,
          definitionNode,
          ...areasContent.nodes,
          ...navigation.nodes,
        ],
        instances: world.instances,
        ...(navigation.connections.length > 0 ? { connections: navigation.connections } : {}),
        ...([...areasContent.subresources, ...navigation.subresources].length > 0 ? { subresources: [...areasContent.subresources, ...navigation.subresources] } : {}),
      };
      outputs.push(convertedOutput(
        unit,
        `worlds/${mapSlug}.scene.json`,
        scene,
        ['$.mapId', '$.tileSize', '$.layers', '$.objects', '$.bossCamps', '$.player', '$.exits'],
        navigationRetained,
      ));
      outputs.push(convertedOutput(
        unit,
        `reports/worlds/${mapSlug}.mapping.json`,
        {
          version: 1,
          mapId: map.mapId,
          sceneId: scene.sceneId,
          sourceCounts: {
            objects: map.objects.length,
            bossCamps: map.bossCamps?.length ?? 0,
            playerMarkers: 1 + Object.keys(map.player.entries).length,
            exits: map.exits?.length ?? 0,
            enemySafeZones: map.enemySafeZones?.length ?? 0,
            enemySpawnAreas: map.enemySpawnAreas?.length ?? 0,
            npcWanderAreas: map.npcWanderAreas?.length ?? 0,
          },
          worldInstanceCount: world.instances.length,
          placements: world.placements,
          navigation: navigation.mappings,
          areas: areasContent.mappings,
        },
        ['$.objects', '$.bossCamps', '$.player', '$.exits'],
        navigationRetained,
      ));
    }
    return outputs;
  },
};
