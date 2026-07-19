import { promises as fs } from 'node:fs';
import path from 'node:path';

import { defineConfig, type Plugin } from 'vite';

import { parseMapFile, type MapFile } from './src/game/content/maps/mapFormat';
import { hasObjectVisual, isObjectArchetypeId } from './src/game/content/objects/ObjectCatalog';
import { isWorldTileId } from './src/game/content/terrain/TileCatalog';
import { ENEMY_CONFIGS } from './src/game/enemies/library/EnemyTypes';
import {
  edgeEntryPoint,
  edgeExitZone,
  exitDirection,
  MAP_DIRECTIONS,
  OPPOSITE_DIRECTION,
} from './src/game/editor/MapConnections';
import type { Direction } from './src/game/world/Area';

const MAX_EDITOR_BODY_BYTES = 2 * 1024 * 1024;

function validateMapReferences(map: MapFile): string[] {
  const issues: string[] = [];
  for (const [layerIndex, layer] of map.layers.entries()) {
    for (const [token, tileId] of Object.entries(layer.legend)) {
      if (!isWorldTileId(tileId)) issues.push(`layers[${layerIndex}].legend['${token}']: unknown tile '${tileId}'`);
    }
  }
  for (const [objectIndex, object] of map.objects.entries()) {
    if (!isObjectArchetypeId(object.objectId)) {
      issues.push(`objects[${objectIndex}].objectId: unknown object '${object.objectId}'`);
    } else if (!hasObjectVisual(object.objectId, object.visualId)) {
      issues.push(`objects[${objectIndex}].visualId: unknown visual '${object.visualId}' for '${object.objectId}'`);
    }
  }
  for (const [enemyIndex, enemy] of (map.spawns?.enemies ?? []).entries()) {
    if (!(enemy.type in ENEMY_CONFIGS)) issues.push(`spawns.enemies[${enemyIndex}].type: unknown enemy '${enemy.type}'`);
  }
  for (const [exitIndex, exit] of (map.exits ?? []).entries()) {
    if (!['north', 'east', 'south', 'west'].includes(exit.entry)) {
      issues.push(`exits[${exitIndex}].entry: unknown direction '${exit.entry}'`);
    }
  }
  return issues;
}

async function readRequestBody(request: NodeJS.ReadableStream): Promise<string> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk as Uint8Array);
    size += buffer.length;
    if (size > MAX_EDITOR_BODY_BYTES) throw new Error('Map payload exceeds the 2 MB editor limit');
    chunks.push(buffer);
  }
  return Buffer.concat(chunks).toString('utf8');
}

function mapEditorSavePlugin(): Plugin {
  return {
    name: 'slime-map-editor-save',
    apply: 'serve',
    configureServer(server) {
      server.middlewares.use('/__map-editor/create', async (request, response) => {
        response.setHeader('Content-Type', 'application/json; charset=utf-8');
        if (request.method !== 'POST') {
          response.statusCode = 405;
          response.end(JSON.stringify({ ok: false, error: 'POST required' }));
          return;
        }

        try {
          const payload = JSON.parse(await readRequestBody(request)) as Record<string, unknown>;
          const mapId = payload.mapId;
          const columns = payload.columns;
          const rows = payload.rows;
          const tileSize = payload.tileSize;
          const tileId = payload.tileId;
          if (typeof mapId !== 'string') throw new Error('Map ID is required');
          if (!Number.isInteger(columns) || (columns as number) < 1 || (columns as number) > 256) {
            throw new Error('Columns must be an integer from 1 to 256');
          }
          if (!Number.isInteger(rows) || (rows as number) < 1 || (rows as number) > 256) {
            throw new Error('Rows must be an integer from 1 to 256');
          }
          if (!Number.isInteger(tileSize) || (tileSize as number) < 16 || (tileSize as number) > 256) {
            throw new Error('Tile size must be an integer from 16 to 256');
          }
          if (typeof tileId !== 'string' || !isWorldTileId(tileId)) throw new Error(`Unknown base terrain '${String(tileId)}'`);

          const width = columns as number;
          const height = rows as number;
          const cellSize = tileSize as number;
          const map = parseMapFile({
            $schema: './maps.schema.json',
            version: 1,
            mapId,
            tileSize: cellSize,
            size: { columns: width, rows: height },
            layers: [{
              id: 'ground',
              encoding: 'legend-chars-v1',
              legend: { g: tileId },
              rows: Array.from({ length: height }, () => 'g'.repeat(width)),
            }],
            objects: [],
            player: {
              spawn: { x: cellSize / 2, y: cellSize / 2 },
              entries: {},
            },
            exits: [],
            enemySafeZones: [],
          }, 'new-map');
          const referenceIssues = validateMapReferences(map);
          if (referenceIssues.length > 0) throw new Error(referenceIssues.join('\n'));

          const mapsDirectory = path.resolve(process.cwd(), 'src/game/content/maps');
          const targetPath = path.resolve(mapsDirectory, `${map.mapId}.map.json`);
          if (path.dirname(targetPath) !== mapsDirectory) throw new Error('Invalid map output path');
          await fs.mkdir(mapsDirectory, { recursive: true });
          await fs.writeFile(targetPath, `${JSON.stringify(map, null, 2)}\n`, { encoding: 'utf8', flag: 'wx' });
          response.statusCode = 201;
          response.end(JSON.stringify({ ok: true, mapId: map.mapId }));
        } catch (error) {
          const code = error instanceof Error && 'code' in error ? (error as NodeJS.ErrnoException).code : undefined;
          response.statusCode = code === 'EEXIST' ? 409 : 400;
          response.end(JSON.stringify({
            ok: false,
            error: code === 'EEXIST' ? 'A map with that ID already exists' : error instanceof Error ? error.message : String(error),
          }));
        }
      });

      server.middlewares.use('/__map-editor/save', async (request, response) => {
        response.setHeader('Content-Type', 'application/json; charset=utf-8');
        if (request.method !== 'POST') {
          response.statusCode = 405;
          response.end(JSON.stringify({ ok: false, error: 'POST required' }));
          return;
        }

        const temporaryPaths: string[] = [];
        try {
          const raw = await readRequestBody(request);
          const map = parseMapFile(JSON.parse(raw), 'editor-save');
          const referenceIssues = validateMapReferences(map);
          if (referenceIssues.length > 0) throw new Error(referenceIssues.join('\n'));

          const mapsDirectory = path.resolve(process.cwd(), 'src/game/content/maps');
          const targetPath = path.resolve(mapsDirectory, `${map.mapId}.map.json`);
          if (path.dirname(targetPath) !== mapsDirectory) throw new Error('Invalid map output path');
          await fs.access(targetPath);

          const persistedMap = parseMapFile(JSON.parse(await fs.readFile(targetPath, 'utf8')), map.mapId);
          const updatedTargets = new Map<string, MutableMapData>();
          const loadTarget = async (mapId: string): Promise<MutableMapData> => {
            const cached = updatedTargets.get(mapId);
            if (cached) return cached;
            if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(mapId)) throw new Error(`Invalid target map '${mapId}'`);
            const targetFile = path.resolve(mapsDirectory, `${mapId}.map.json`);
            if (path.dirname(targetFile) !== mapsDirectory) throw new Error(`Invalid target map '${mapId}'`);
            const data = JSON.parse(await fs.readFile(targetFile, 'utf8')) as MutableMapData;
            parseMapFile(data, mapId);
            updatedTargets.set(mapId, data);
            return data;
          };

          for (const direction of MAP_DIRECTIONS) {
            const previousTarget = connectionTarget(persistedMap, direction);
            const nextTarget = connectionTarget(map, direction);
            const reciprocalDirection = OPPOSITE_DIRECTION[direction];

            if (previousTarget && previousTarget !== nextTarget) {
              const previousMap = await loadTarget(previousTarget);
              previousMap.exits = previousMap.exits.filter((exit) => (
                exitDirection(exit, previousMap) !== reciprocalDirection || exit.to !== map.mapId
              ));
            }

            if (!nextTarget) continue;
            if (nextTarget === map.mapId) throw new Error(`A map cannot connect ${direction} to itself`);
            const targetMap = await loadTarget(nextTarget);
            const occupied = targetMap.exits.find((exit) => exitDirection(exit, targetMap) === reciprocalDirection);
            if (occupied && occupied.to !== map.mapId) {
              throw new Error(
                `${nextTarget}'s ${reciprocalDirection} edge is already connected to '${occupied.to}'. Disconnect it first.`,
              );
            }
            targetMap.player.entries[reciprocalDirection] ??= edgeEntryPoint(reciprocalDirection, targetMap);
            targetMap.exits = targetMap.exits.filter((exit) => exitDirection(exit, targetMap) !== reciprocalDirection);
            targetMap.exits.push({
              zone: edgeExitZone(reciprocalDirection, targetMap),
              to: map.mapId,
              entry: direction,
            });
          }

          const filesToWrite: Array<{ target: string; value: unknown }> = [{ target: targetPath, value: map }];
          for (const [targetMapId, targetData] of updatedTargets) {
            const validatedTarget = parseMapFile(targetData, targetMapId);
            const targetIssues = validateMapReferences(validatedTarget);
            if (targetIssues.length > 0) throw new Error(targetIssues.join('\n'));
            filesToWrite.push({
              target: path.join(mapsDirectory, `${targetMapId}.map.json`),
              value: validatedTarget,
            });
          }
          for (const [index, file] of filesToWrite.entries()) {
            const temporary = `${file.target}.${process.pid}.${Date.now()}.${index}.tmp`;
            temporaryPaths.push(temporary);
            await fs.writeFile(temporary, `${JSON.stringify(file.value, null, 2)}\n`, 'utf8');
          }
          for (let index = 0; index < filesToWrite.length; index += 1) {
            await fs.rename(temporaryPaths[index], filesToWrite[index].target);
          }
          temporaryPaths.length = 0;
          response.statusCode = 200;
          response.end(JSON.stringify({ ok: true, mapId: map.mapId, updatedMaps: [...updatedTargets.keys()] }));
        } catch (error) {
          await Promise.all(temporaryPaths.map((temporary) => fs.rm(temporary, { force: true })));
          response.statusCode = 400;
          response.end(JSON.stringify({ ok: false, error: error instanceof Error ? error.message : String(error) }));
        }
      });
    },
  };
}

interface MutableMapData {
  [key: string]: unknown;
  mapId: string;
  tileSize: number;
  size: { columns: number; rows: number };
  player: {
    spawn: { x: number; y: number };
    entries: Partial<Record<Direction, { x: number; y: number }>>;
  };
  exits: Array<{ zone: { x: number; y: number; w: number; h: number }; to: string; entry: string }>;
}

function connectionTarget(map: MapFile, direction: Direction): string | undefined {
  return map.exits?.find((exit) => exitDirection(exit, map) === direction)?.to;
}

export default defineConfig({
  base: './',
  plugins: [mapEditorSavePlugin()],
  server: {
    open: false,
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          phaser: ['phaser'],
        },
      },
    },
  },
});
