import { promises as fs } from 'node:fs';
import path from 'node:path';

import { defineConfig, type Plugin } from 'vite';

import { characterContentModulesPlugin } from './src/game/content/characters/characterContentModulesPlugin';

import { parseMapFile, type MapFile } from './src/game/content/maps/mapFormat';
import { isObjectArchetypeId } from './src/game/content/objects/ObjectCatalog';
import { isWorldTileId } from './src/game/content/terrain/TileCatalog';
import enemyTypesJson from './src/game/content/enemies/enemy-types.json';
import { ASSET_MANIFEST, type AssetId } from './src/game/infrastructure/assets/manifest';
import {
  edgeEntryPoint,
  edgeExitZone,
  exitDirection,
  MAP_DIRECTIONS,
  OPPOSITE_DIRECTION,
} from './src/game/editor/MapConnections';
import type { Direction } from './src/game/world/Area';

const MAX_EDITOR_BODY_BYTES = 2 * 1024 * 1024;
const OBJECT_ID_PATTERN = /^[a-z0-9]+([.-][a-z0-9-]+)+$/;
const OBJECT_DEFINITION_ROOT = path.resolve(process.cwd(), 'src/game/content/objects');
const ENEMY_CONFIGS = enemyTypesJson.types;

interface MutableObjectFrame {
  [key: string]: unknown;
  visualId: string;
  frame: number;
}

interface MutableObjectVariant {
  assetId: string;
  frames: MutableObjectFrame[];
}

interface MutableObjectDefinition {
  [key: string]: unknown;
  objectId: string;
  variants: MutableObjectVariant[];
  physics: unknown;
}

interface ObjectVisualOffsetPayload {
  readonly x: number;
  readonly y: number;
}

interface ObjectColliderPayload {
  readonly width: number;
  readonly height: number;
  readonly offsetX: number;
  readonly offsetY: number;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

interface ObjectOcclusionPayload {
  readonly width: number;
  readonly height: number;
  readonly offsetX: number;
  readonly offsetY: number;
}

function requireInteger(value: unknown, minimum: number, label: string): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < minimum) {
    throw new Error(`${label} must be an integer >= ${minimum}`);
  }
  return value;
}

function requireWholePixel(value: unknown): number {
  if (typeof value !== 'number' || !Number.isInteger(value)) {
    throw new Error('Visual offset values must be whole pixels');
  }
  return value;
}

function validateRecordKeys(value: Record<string, unknown>, allowed: readonly string[], label: string): void {
  const allowedKeys = new Set(allowed);
  for (const key of Object.keys(value)) {
    if (!allowedKeys.has(key)) throw new Error(`${label}.${key}: unknown property`);
  }
}

async function findObjectDefinitionPath(directory: string, objectId: string): Promise<string | undefined> {
  const entries = await fs.readdir(directory, { withFileTypes: true });
  const expectedFilename = `${objectId.replaceAll('.', '-')}.json`;
  for (const entry of entries) {
    const candidate = path.resolve(directory, entry.name);
    if (entry.isDirectory()) {
      const nested = await findObjectDefinitionPath(candidate, objectId);
      if (nested) return nested;
      continue;
    }
    if (!entry.isFile() || entry.name !== expectedFilename || entry.name === 'objects.schema.json') continue;
    const parsed = JSON.parse(await fs.readFile(candidate, 'utf8')) as { objectId?: unknown };
    if (parsed.objectId === objectId) return candidate;
  }
  return undefined;
}

function frameDimensions(assetId: string): { readonly width: number; readonly height: number } | undefined {
  if (!(assetId in ASSET_MANIFEST.assets)) throw new Error(`Unknown asset '${assetId}'`);
  const asset = ASSET_MANIFEST.assets[assetId as AssetId];
  const source: unknown = asset.source;
  if (!isRecord(source) || source.kind !== 'spritesheet' || !isRecord(source.frame)) return undefined;
  const width = source.frame.w;
  const height = source.frame.h;
  if (typeof width !== 'number' || typeof height !== 'number') {
    throw new Error(`Spritesheet asset '${assetId}' has invalid frame dimensions`);
  }
  return { width, height };
}

function validateObjectVisualUpdate(
  payload: Record<string, unknown>,
  definition: MutableObjectDefinition,
): {
  readonly frame: MutableObjectFrame;
  readonly displayName: string;
  readonly visualOffset: ObjectVisualOffsetPayload;
  readonly collider?: ObjectColliderPayload;
  readonly occlusionBounds?: ObjectOcclusionPayload;
} {
  validateRecordKeys(payload, ['objectId', 'visualId', 'displayName', 'visualOffset', 'collider', 'occlusionBounds'], 'payload');
  const objectId = payload.objectId;
  const visualId = payload.visualId;
  if (typeof objectId !== 'string' || !OBJECT_ID_PATTERN.test(objectId) || !isObjectArchetypeId(objectId)) {
    throw new Error(`Unknown object '${String(objectId)}'`);
  }
  if (definition.objectId !== objectId) throw new Error(`Object definition ID mismatch for '${objectId}'`);
  if (typeof visualId !== 'string' || !/^[a-z0-9]+([.-][a-z0-9-]+)*$/.test(visualId)) {
    throw new Error('Visual ID must be a lowercase stable ID');
  }
  const variant = definition.variants.find((candidate) => candidate.frames.some((frame) => frame.visualId === visualId));
  const frame = variant?.frames.find((candidate) => candidate.visualId === visualId);
  if (!variant || !frame) throw new Error(`Unknown visual '${visualId}' for '${objectId}'`);

  const displayName = payload.displayName;
  if (typeof displayName !== 'string' || displayName.trim().length === 0 || displayName.length > 80) {
    throw new Error('Display name must contain 1 to 80 characters');
  }
  const visualOffsetValue = payload.visualOffset;
  if (!isRecord(visualOffsetValue)) throw new Error('Visual offset is required');
  validateRecordKeys(visualOffsetValue, ['x', 'y'], 'visualOffset');
  const visualOffset = {
    x: requireWholePixel(visualOffsetValue.x),
    y: requireWholePixel(visualOffsetValue.y),
  };
  const colliderValue = payload.collider;
  const occlusionValue = payload.occlusionBounds;
  let occlusionBounds: ObjectOcclusionPayload | undefined;
  if (occlusionValue !== undefined) {
    if (!isRecord(occlusionValue)) throw new Error('Occlusion bounds must be an object');
    validateRecordKeys(occlusionValue, ['width', 'height', 'offsetX', 'offsetY'], 'occlusionBounds');
    occlusionBounds = {
      width: requireInteger(occlusionValue.width, 1, 'Occlusion width'),
      height: requireInteger(occlusionValue.height, 1, 'Occlusion height'),
      offsetX: requireInteger(occlusionValue.offsetX, 0, 'Occlusion offsetX'),
      offsetY: requireInteger(occlusionValue.offsetY, 0, 'Occlusion offsetY'),
    };
    const dimensions = frameDimensions(variant.assetId);
    if (!dimensions) throw new Error('Procedural object templates cannot define occlusion bounds');
    if (frame.visualSetId !== undefined || frame.animationClip !== undefined) {
      throw new Error('Animated object templates cannot define occlusion bounds');
    }
    if (occlusionBounds.offsetX + occlusionBounds.width > dimensions.width) {
      throw new Error(`Occlusion bounds exceed frame width ${dimensions.width}`);
    }
    if (occlusionBounds.offsetY + occlusionBounds.height > dimensions.height) {
      throw new Error(`Occlusion bounds exceed frame height ${dimensions.height}`);
    }
  }
  if (definition.physics === null) {
    if (colliderValue !== undefined) throw new Error('Decorative objects cannot have colliders');
    return { frame, displayName, visualOffset, occlusionBounds };
  }
  if (!isRecord(colliderValue)) throw new Error('Solid objects require a collider');
  validateRecordKeys(colliderValue, ['width', 'height', 'offsetX', 'offsetY'], 'collider');
  const collider = {
    width: requireInteger(colliderValue.width, 1, 'Collider width'),
    height: requireInteger(colliderValue.height, 1, 'Collider height'),
    offsetX: requireInteger(colliderValue.offsetX, 0, 'Collider offsetX'),
    offsetY: requireInteger(colliderValue.offsetY, 0, 'Collider offsetY'),
  };
  const dimensions = frameDimensions(variant.assetId);
  if (dimensions && collider.offsetX + collider.width > dimensions.width) {
    throw new Error(`Collider exceeds frame width ${dimensions.width}`);
  }
  if (dimensions && collider.offsetY + collider.height > dimensions.height) {
    throw new Error(`Collider exceeds frame height ${dimensions.height}`);
  }
  return { frame, displayName, visualOffset, collider, occlusionBounds };
}

async function validateMapReferences(map: MapFile): Promise<string[]> {
  const issues: string[] = [];
  const objectDefinitions = new Map<string, Promise<MutableObjectDefinition | undefined>>();
  const loadObjectDefinition = (objectId: string): Promise<MutableObjectDefinition | undefined> => {
    const cached = objectDefinitions.get(objectId);
    if (cached) return cached;
    const pending = (async () => {
      const definitionPath = await findObjectDefinitionPath(OBJECT_DEFINITION_ROOT, objectId);
      if (!definitionPath) return undefined;
      return JSON.parse(await fs.readFile(definitionPath, 'utf8')) as MutableObjectDefinition;
    })();
    objectDefinitions.set(objectId, pending);
    return pending;
  };
  for (const [layerIndex, layer] of map.layers.entries()) {
    for (const [token, tileId] of Object.entries(layer.legend)) {
      if (!isWorldTileId(tileId)) issues.push(`layers[${layerIndex}].legend['${token}']: unknown tile '${tileId}'`);
    }
  }
  for (const [objectIndex, object] of map.objects.entries()) {
    const definition = await loadObjectDefinition(object.objectId);
    if (!definition) {
      issues.push(`objects[${objectIndex}].objectId: unknown object '${object.objectId}'`);
    } else if (!definition.variants.some((variant) => (
      variant.frames.some((frame) => frame.visualId === object.visualId)
    ))) {
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
    const buffer = typeof chunk === 'string' ? Buffer.from(chunk) : Buffer.from(chunk);
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
          const referenceIssues = await validateMapReferences(map);
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

      server.middlewares.use('/__map-editor/object-template/update', async (request, response) => {
        response.setHeader('Content-Type', 'application/json; charset=utf-8');
        if (request.method !== 'POST') {
          response.statusCode = 405;
          response.end(JSON.stringify({ ok: false, error: 'POST required' }));
          return;
        }

        let temporaryPath: string | undefined;
        try {
          const payload = JSON.parse(await readRequestBody(request)) as Record<string, unknown>;
          const objectId = payload.objectId;
          if (typeof objectId !== 'string') throw new Error('Object ID is required');
          const definitionPath = await findObjectDefinitionPath(OBJECT_DEFINITION_ROOT, objectId);
          if (!definitionPath) throw new Error(`Object definition '${objectId}' was not found`);
          const definition = JSON.parse(await fs.readFile(definitionPath, 'utf8')) as MutableObjectDefinition;
          const update = validateObjectVisualUpdate(payload, definition);

          update.frame.displayName = update.displayName;
          update.frame.visualOffset = update.visualOffset;
          if (definition.physics === null) delete update.frame.collider;
          else update.frame.collider = update.collider;
          if (update.occlusionBounds) update.frame.occlusionBounds = update.occlusionBounds;
          else delete update.frame.occlusionBounds;

          temporaryPath = `${definitionPath}.${process.pid}.${Date.now()}.tmp`;
          await fs.writeFile(temporaryPath, `${JSON.stringify(definition, null, 2)}\n`, 'utf8');
          await fs.rename(temporaryPath, definitionPath);
          temporaryPath = undefined;
          response.statusCode = 200;
          response.end(JSON.stringify({
            ok: true,
            objectId,
            visualId: payload.visualId,
            displayName: update.displayName,
            visualOffset: update.visualOffset,
            collider: update.collider,
            occlusionBounds: update.occlusionBounds,
          }));
        } catch (error) {
          if (temporaryPath) await fs.rm(temporaryPath, { force: true });
          response.statusCode = 400;
          response.end(JSON.stringify({ ok: false, error: error instanceof Error ? error.message : String(error) }));
        }
      });

      server.middlewares.use('/__map-editor/object-template/duplicate', async (request, response) => {
        response.setHeader('Content-Type', 'application/json; charset=utf-8');
        if (request.method !== 'POST') {
          response.statusCode = 405;
          response.end(JSON.stringify({ ok: false, error: 'POST required' }));
          return;
        }

        let temporaryPath: string | undefined;
        try {
          const payload = JSON.parse(await readRequestBody(request)) as Record<string, unknown>;
          validateRecordKeys(
            payload,
            ['objectId', 'sourceVisualId', 'visualId', 'displayName', 'visualOffset', 'collider', 'occlusionBounds'],
            'payload',
          );
          const objectId = payload.objectId;
          const sourceVisualId = payload.sourceVisualId;
          const visualId = payload.visualId;
          if (typeof objectId !== 'string' || !isObjectArchetypeId(objectId)) {
            throw new Error(`Unknown object '${String(objectId)}'`);
          }
          if (typeof sourceVisualId !== 'string') throw new Error('Source visual ID is required');
          if (typeof visualId !== 'string' || !/^[a-z0-9]+([.-][a-z0-9-]+)*$/.test(visualId)) {
            throw new Error('Visual ID must be a lowercase stable ID');
          }

          const definitionPath = await findObjectDefinitionPath(OBJECT_DEFINITION_ROOT, objectId);
          if (!definitionPath) throw new Error(`Object definition '${objectId}' was not found`);
          const definition = JSON.parse(await fs.readFile(definitionPath, 'utf8')) as MutableObjectDefinition;
          if (definition.variants.some((variant) => (
            variant.frames.some((frame) => frame.visualId === visualId)
          ))) {
            throw new Error(`Visual '${visualId}' already exists for '${objectId}'`);
          }
          const sourceVariant = definition.variants.find((variant) => (
            variant.frames.some((frame) => frame.visualId === sourceVisualId)
          ));
          if (!sourceVariant) throw new Error(`Unknown visual '${sourceVisualId}' for '${objectId}'`);
          const update = validateObjectVisualUpdate({
            objectId,
            visualId: sourceVisualId,
            displayName: payload.displayName,
            visualOffset: payload.visualOffset,
            collider: payload.collider,
            occlusionBounds: payload.occlusionBounds,
          }, definition);

          const duplicatedFrame: MutableObjectFrame = {
            ...update.frame,
            visualId,
            displayName: update.displayName,
            visualOffset: update.visualOffset,
          };
          if (definition.physics === null) delete duplicatedFrame.collider;
          else duplicatedFrame.collider = update.collider;
          if (update.occlusionBounds) duplicatedFrame.occlusionBounds = update.occlusionBounds;
          else delete duplicatedFrame.occlusionBounds;
          sourceVariant.frames.push(duplicatedFrame);

          temporaryPath = `${definitionPath}.${process.pid}.${Date.now()}.tmp`;
          await fs.writeFile(temporaryPath, `${JSON.stringify(definition, null, 2)}\n`, 'utf8');
          await fs.rename(temporaryPath, definitionPath);
          temporaryPath = undefined;
          response.statusCode = 201;
          response.end(JSON.stringify({
            ok: true,
            objectId,
            visualId,
            displayName: update.displayName,
            visualOffset: update.visualOffset,
            collider: update.collider,
            occlusionBounds: update.occlusionBounds,
          }));
        } catch (error) {
          if (temporaryPath) await fs.rm(temporaryPath, { force: true });
          response.statusCode = 400;
          response.end(JSON.stringify({ ok: false, error: error instanceof Error ? error.message : String(error) }));
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
          const referenceIssues = await validateMapReferences(map);
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
            const targetIssues = await validateMapReferences(validatedTarget);
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
  plugins: [characterContentModulesPlugin(), mapEditorSavePlugin()],
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
