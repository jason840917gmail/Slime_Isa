import ts from 'typescript';

import { convertedOutput, readJson } from './adapter-utils.mjs';

function slug(value) {
  return value.replaceAll('.', '-').replace(/[^a-z0-9-]+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
}

async function typescriptExport(readSource, sourcePath, exportName) {
  const source = await readSource(sourcePath);
  const output = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
    fileName: sourcePath,
  }).outputText;
  const encoded = Buffer.from(output).toString('base64');
  const loaded = await import(`data:text/javascript;base64,${encoded}`);
  if (!(exportName in loaded)) throw new Error(`TypeScript source '${sourcePath}' does not export '${exportName}'`);
  return loaded[exportName];
}

function fallbackSeed(mapId) {
  return [...mapId].reduce((hash, character) => ((hash * 31) + character.charCodeAt(0)) >>> 0, 0);
}

function tileSetEntry(definition) {
  return {
    assetIds: definition.visual.assetIds,
    selection: definition.visual.selection,
    physics: definition.physics,
    allowsDecorations: definition.allowsDecorations,
    tags: definition.tags,
    ...(definition.transition ? { transition: definition.transition } : {}),
  };
}

function retainedMapFields(unit, map) {
  return Object.keys(map)
    .filter((key) => !['mapId', 'tileSize', 'size', 'layers'].includes(key))
    .sort()
    .map((key) => ({ path: `$.${key}`, owner: unit.oldSourcePath }));
}

export const mapSceneAdapter = {
  async convert({ units, readSource }) {
    const tileCatalog = await typescriptExport(readSource, 'src/game/content/terrain/TileCatalog.ts', 'TILE_CATALOG');
    const areas = await typescriptExport(readSource, 'src/game/world/Area.ts', 'AREAS');
    const outputs = [];
    for (const unit of units) {
      if (unit.family !== 'map' || !unit.key.startsWith('map:')) throw new Error(`Map adapter does not support unit '${unit.key}'`);
      const map = await readJson(readSource, unit.oldSourcePath);
      if (map.mapId !== unit.stableId) throw new Error(`Map unit '${unit.key}' loaded mismatched map '${map.mapId}'`);
      const mapSlug = slug(map.mapId);
      const seed = Object.values(areas).find((area) => area.mapId === map.mapId)?.seed ?? fallbackSeed(map.mapId);
      const layerNodes = [];
      const retained = retainedMapFields(unit, map);

      map.layers.forEach((layer, layerIndex) => {
        const layerSlug = slug(layer.id);
        const tileSetId = `tiles.${mapSlug}.${layerSlug}.set`;
        const tileDataId = `tiles.${mapSlug}.${layerSlug}.data`;
        const usedTileIds = [...new Set(layer.rows.flatMap((row) => [...row].map((character) => layer.legend[character])))].sort();
        const tiles = Object.fromEntries(usedTileIds.map((tileId) => {
          const definition = tileCatalog[tileId];
          if (!definition) throw new Error(`Map '${map.mapId}' layer '${layer.id}' references unknown tile '${tileId}'`);
          return [tileId, tileSetEntry(definition)];
        }));
        const cells = layer.rows.flatMap((row, y) => [...row].map((character, x) => ({ x, y, tileId: layer.legend[character] })));
        const tileSet = { version: 1, resourceId: tileSetId, kind: 'tile-set', tiles };
        const tileData = {
          version: 1,
          resourceId: tileDataId,
          kind: 'tile-data',
          tileSet: tileSetId,
          columns: map.size.columns,
          rows: map.size.rows,
          cells,
        };
        outputs.push(convertedOutput(
          unit,
          `resources/tiles/${mapSlug}.${layerSlug}.tile-set.resource.json`,
          tileSet,
          ['$.layers'],
          retained,
        ));
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
            collisionLayer: 1,
            collisionMask: 2,
            collisionEnabled: true,
            editorLocked: false,
          },
        });
      });

      const scene = {
        version: 1,
        sceneId: `world.${mapSlug}`,
        rootNodeId: 'world',
        nodes: [
          { id: 'world', name: map.mapId, type: 'Node2D', parentId: null, order: 0, properties: { position: [0, 0] } },
          ...layerNodes,
        ],
        instances: [],
      };
      outputs.push(convertedOutput(
        unit,
        `worlds/${mapSlug}.scene.json`,
        scene,
        ['$.mapId', '$.tileSize', '$.layers'],
        retained,
      ));
    }
    return outputs;
  },
};
