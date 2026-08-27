import { promises as fs, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';

import { defineConfig, type Plugin } from 'vite';

import { characterContentModulesPlugin } from './src/game/content/characters/characterContentModulesPlugin';
import { animationContentModulesPlugin } from './src/game/content/animations/animationContentModulesPlugin';
import { readCatalog as readAnimationCatalog } from './src/game/content/animations/animationContentModulesPlugin';
import { gameConstantsContentPlugin } from './src/game/content/gameConstantsContentPlugin';

import { parseMapFile, type MapFile } from './src/game/content/maps/mapFormat';
import { isObjectArchetypeId } from './src/game/content/objects/ObjectCatalog';
import { isWorldTileId } from './src/game/content/terrain/TileCatalog';
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
const CHARACTER_DEFINITION_ROOT = path.resolve(process.cwd(), 'src/game/content/characters');
const ANIMATION_DEFINITION_ROOT = path.resolve(process.cwd(), 'src/game/content/animations');
const ITEM_DEFINITION_PATH = path.resolve(process.cwd(), 'src/game/content/items/items.json');
const WEAPON_DEFINITION_ROOT = path.resolve(process.cwd(), 'src/game/content/weapons');

function discoverEnemyIds(directory: string): string[] {
  const ids: string[] = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const candidate = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      ids.push(...discoverEnemyIds(candidate));
      continue;
    }
    if (!entry.isFile() || entry.name !== 'character.json') continue;
    const character = JSON.parse(readFileSync(candidate, 'utf8')) as { characterId?: unknown; kind?: unknown };
    if (character.kind === 'enemy' && typeof character.characterId === 'string') ids.push(character.characterId);
  }
  return ids;
}

const ENEMY_IDS = new Set(discoverEnemyIds(CHARACTER_DEFINITION_ROOT));
const KNOWN_ITEM_IDS = new Set(Object.keys(JSON.parse(readFileSync(ITEM_DEFINITION_PATH, 'utf8')) as Record<string, unknown>));
function discoverWeaponItemIds(directory: string): void {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const candidate = path.join(directory, entry.name);
    if (entry.isDirectory()) discoverWeaponItemIds(candidate);
    else if (entry.isFile() && entry.name === 'weapon.json') {
      const definition = JSON.parse(readFileSync(candidate, 'utf8')) as { weaponId?: unknown };
      if (typeof definition.weaponId === 'string') KNOWN_ITEM_IDS.add(definition.weaponId);
    }
  }
}
discoverWeaponItemIds(WEAPON_DEFINITION_ROOT);

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
  collectible?: Record<string, unknown>;
  destructible?: Record<string, unknown>;
  resourceNode?: Record<string, unknown>;
}

interface ObjectVisualOffsetPayload {
  readonly x: number;
  readonly y: number;
}

interface ObjectVisualScalePayload {
  readonly value: number;
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

interface ObjectDepthPayload {
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

function requireVisualScale(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0.05 || value > 8) {
    throw new Error('Visual scale must be a finite number between 0.05 and 8');
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

function assetFrameCapacity(assetId: string): number {
  if (!(assetId in ASSET_MANIFEST.assets)) throw new Error(`Unknown asset '${assetId}'`);
  const asset = ASSET_MANIFEST.assets[assetId as AssetId];
  const source: unknown = asset.source;
  if (!isRecord(source) || (source.kind !== 'image' && source.kind !== 'spritesheet')) {
    throw new Error(`Asset '${assetId}' is not an image source`);
  }
  if (source.kind === 'image') return 1;
  if (!isRecord(source.frame)) throw new Error(`Spritesheet asset '${assetId}' has no frame metadata`);
  const columns = source.frame.cols;
  const rows = source.frame.rows;
  const count = source.frame.count;
  if (typeof columns !== 'number' || !Number.isInteger(columns) || columns < 1
    || typeof rows !== 'number' || !Number.isInteger(rows) || rows < 1) {
    throw new Error(`Spritesheet asset '${assetId}' has invalid grid dimensions`);
  }
  const capacity = columns * rows;
  if (count === undefined) return capacity;
  if (typeof count !== 'number' || !Number.isInteger(count) || count < 1 || count > capacity) {
    throw new Error(`Spritesheet asset '${assetId}' has an invalid populated frame count`);
  }
  return count;
}

async function validateObjectVisualUpdate(
  payload: Record<string, unknown>,
  definition: MutableObjectDefinition,
): Promise<{
  readonly frame: MutableObjectFrame;
  readonly displayName: string;
  readonly scale: ObjectVisualScalePayload['value'];
  readonly visualOffset: ObjectVisualOffsetPayload;
  readonly collider?: ObjectColliderPayload;
  readonly occlusionBounds?: ObjectOcclusionPayload;
  readonly depthBounds?: ObjectDepthPayload;
  readonly idleAnimationId?: string;
  readonly onHitAnimationId?: string;
}> {
  validateRecordKeys(payload, ['objectId', 'visualId', 'displayName', 'scale', 'visualOffset', 'collider', 'depthBounds', 'occlusionBounds', 'idleAnimationId', 'onHitAnimationId'], 'payload');
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
  const scale = payload.scale === undefined ? 1 : requireVisualScale(payload.scale);
  const visualOffsetValue = payload.visualOffset;
  if (!isRecord(visualOffsetValue)) throw new Error('Visual offset is required');
  validateRecordKeys(visualOffsetValue, ['x', 'y'], 'visualOffset');
  const visualOffset = {
    x: requireWholePixel(visualOffsetValue.x),
    y: requireWholePixel(visualOffsetValue.y),
  };
  const colliderValue = payload.collider;
  const depthValue = payload.depthBounds;
  const occlusionValue = payload.occlusionBounds;
  let depthBounds: ObjectDepthPayload | undefined;
  if (depthValue !== undefined) {
    if (!isRecord(depthValue)) throw new Error('Depth bounds must be an object');
    validateRecordKeys(depthValue, ['width', 'height', 'offsetX', 'offsetY'], 'depthBounds');
    depthBounds = {
      width: requireInteger(depthValue.width, 1, 'Depth width'),
      height: requireInteger(depthValue.height, 1, 'Depth height'),
      offsetX: requireInteger(depthValue.offsetX, 0, 'Depth offsetX'),
      offsetY: requireInteger(depthValue.offsetY, 0, 'Depth offsetY'),
    };
    const dimensions = frameDimensions(variant.assetId);
    if (!dimensions) throw new Error('Procedural object templates cannot define depth bounds');
    if (depthBounds.offsetX + depthBounds.width > dimensions.width) {
      throw new Error(`Depth bounds exceed frame width ${dimensions.width}`);
    }
    if (depthBounds.offsetY + depthBounds.height > dimensions.height) {
      throw new Error(`Depth bounds exceed frame height ${dimensions.height}`);
    }
  }
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
    if (occlusionBounds.offsetX + occlusionBounds.width > dimensions.width) {
      throw new Error(`Occlusion bounds exceed frame width ${dimensions.width}`);
    }
    if (occlusionBounds.offsetY + occlusionBounds.height > dimensions.height) {
      throw new Error(`Occlusion bounds exceed frame height ${dimensions.height}`);
    }
  }
  const readAnimationId = (value: unknown, field: string): string | undefined => {
    if (value === null || value === undefined) return undefined;
    if (typeof value !== 'string') throw new Error(`${field} must be a string or null`);
    return value;
  };
  const idleAnimationId = readAnimationId(payload.idleAnimationId, 'idleAnimationId');
  const onHitAnimationId = readAnimationId(payload.onHitAnimationId, 'onHitAnimationId');
  if (occlusionBounds && (idleAnimationId !== undefined || onHitAnimationId !== undefined)) {
    throw new Error('Animated object templates cannot define occlusion bounds');
  }
  for (const [field, value, expectedLoop] of [['idleAnimationId', idleAnimationId, true], ['onHitAnimationId', onHitAnimationId, false]] as const) {
    if (value === undefined) continue;
    if (typeof value !== 'string' || !/^[a-z0-9]+(?:[.-][a-z0-9]+(?:-[a-z0-9]+)*)+$/.test(value)) throw new Error(`${field} must be a lowercase stable animation ID`);
    const catalog = await readAnimationCatalog(ANIMATION_DEFINITION_ROOT);
    const animation = catalog.packages.find((entry) => entry.animationId === value);
    if (!animation) throw new Error(`${field} '${value}' was not found in the shared animation catalog`);
    if (animation.animation.loop !== expectedLoop) throw new Error(`${field} '${value}' has the wrong loop contract`);
  }
  if (definition.physics === null) {
    if (colliderValue !== undefined) throw new Error('Decorative objects cannot have colliders');
    return { frame, displayName, scale, visualOffset, depthBounds, occlusionBounds, idleAnimationId, onHitAnimationId };
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
  return { frame, displayName, scale, visualOffset, collider, depthBounds, occlusionBounds, idleAnimationId, onHitAnimationId };
}

async function validateObjectGameplayUpdate(
  payload: Record<string, unknown>,
  definition: MutableObjectDefinition,
): Promise<{ readonly collectible?: Record<string, unknown>; readonly resourceNode?: Record<string, unknown> }> {
  validateRecordKeys(payload, ['objectId', 'collectible', 'resourceNode'], 'payload');
  const objectId = payload.objectId;
  if (typeof objectId !== 'string' || !OBJECT_ID_PATTERN.test(objectId) || !isObjectArchetypeId(objectId)) {
    throw new Error(`Unknown object '${String(objectId)}'`);
  }
  if (definition.objectId !== objectId) throw new Error(`Object definition ID mismatch for '${objectId}'`);
  if (definition.collectible && definition.resourceNode) throw new Error(`Object '${objectId}' cannot be both a collectible and a resource node`);

  if (definition.collectible) {
    if (!isRecord(payload.collectible)) throw new Error('Collectible attributes are required');
    validateRecordKeys(payload.collectible, ['itemId', 'quantity'], 'collectible');
    if (typeof payload.collectible.itemId !== 'string' || payload.collectible.itemId.trim().length === 0) {
      throw new Error('Collectible item ID is required');
    }
    if (!KNOWN_ITEM_IDS.has(payload.collectible.itemId.trim())) throw new Error(`Unknown inventory item '${payload.collectible.itemId}'`);
    const quantity = requireInteger(payload.collectible.quantity, 1, 'Collectible quantity');
    return { collectible: { itemId: payload.collectible.itemId.trim(), quantity } };
  }

  if (!definition.resourceNode) throw new Error(`Object '${objectId}' has no resource or collectible gameplay attributes`);
  if (!isRecord(payload.resourceNode)) throw new Error('Resource attributes are required');
  validateRecordKeys(payload.resourceNode, ['health', 'drop', 'hitEffectId', 'persistHealth', 'depletionMessage', 'harvestRequirement'], 'resourceNode');
  const health = requireInteger(payload.resourceNode.health, 1, 'Resource life points');
  if (!isRecord(payload.resourceNode.drop)) throw new Error('Resource drop is required');
  validateRecordKeys(payload.resourceNode.drop, ['objectId', 'visualId', 'pieces'], 'resourceNode.drop');
  const dropObjectId = payload.resourceNode.drop.objectId;
  if (typeof dropObjectId !== 'string' || !isObjectArchetypeId(dropObjectId)) throw new Error(`Unknown collectible drop '${String(dropObjectId)}'`);
  const dropDefinitionPath = await findObjectDefinitionPath(OBJECT_DEFINITION_ROOT, dropObjectId);
  if (!dropDefinitionPath) throw new Error(`Collectible drop '${dropObjectId}' was not found`);
  const dropDefinition = JSON.parse(await fs.readFile(dropDefinitionPath, 'utf8')) as MutableObjectDefinition;
  if (!dropDefinition.collectible) throw new Error(`Drop object '${dropObjectId}' is not a collectible`);
  const visualId = payload.resourceNode.drop.visualId;
  if (typeof visualId !== 'string' || !dropDefinition.variants.some((variant) => variant.frames.some((frame) => frame.visualId === visualId))) {
    throw new Error(`Unknown drop visual '${String(visualId)}' for '${dropObjectId}'`);
  }
  const pieces = requireInteger(payload.resourceNode.drop.pieces, 1, 'Resource drop pieces');
  const optionalString = (value: unknown, label: string): string | undefined => {
    if (value === undefined) return undefined;
    if (typeof value !== 'string') throw new Error(`${label} must be a string`);
    return value.trim() || undefined;
  };
  const hitEffectId = optionalString(payload.resourceNode.hitEffectId, 'hitEffectId');
  const depletionMessage = optionalString(payload.resourceNode.depletionMessage, 'depletionMessage');
  let harvestRequirement: Record<string, unknown> | undefined;
  if (payload.resourceNode.harvestRequirement !== undefined) {
    if (!isRecord(payload.resourceNode.harvestRequirement)) throw new Error('Harvest requirement must be an object');
    validateRecordKeys(payload.resourceNode.harvestRequirement, ['targetTag', 'minimumTier', 'failureMessage'], 'harvestRequirement');
    const targetTag = payload.resourceNode.harvestRequirement.targetTag;
    const failureMessage = payload.resourceNode.harvestRequirement.failureMessage;
    if (typeof targetTag !== 'string' || targetTag.trim().length === 0) throw new Error('Harvest target tag is required');
    if (typeof failureMessage !== 'string' || failureMessage.trim().length === 0) throw new Error('Harvest failure message is required');
    harvestRequirement = {
      targetTag: targetTag.trim(),
      minimumTier: requireInteger(payload.resourceNode.harvestRequirement.minimumTier, 1, 'Harvest minimum tier'),
      failureMessage: failureMessage.trim(),
    };
  }
  if (payload.resourceNode.persistHealth !== undefined && typeof payload.resourceNode.persistHealth !== 'boolean') {
    throw new Error('persistHealth must be a boolean');
  }
  return {
    resourceNode: {
      health,
      drop: { objectId: dropObjectId, visualId, pieces },
      ...(hitEffectId ? { hitEffectId } : {}),
      persistHealth: payload.resourceNode.persistHealth !== false,
      ...(depletionMessage ? { depletionMessage } : {}),
      ...(harvestRequirement ? { harvestRequirement } : {}),
    },
  };
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
    const objectPath = `objects[${objectIndex}]`;
    if (!definition) {
      issues.push(`${objectPath}.objectId: unknown object '${object.objectId}'`);
    } else if (!definition.variants.some((variant) => (
      variant.frames.some((frame) => frame.visualId === object.visualId)
    ))) {
      issues.push(`${objectPath}.visualId: unknown visual '${object.visualId}' for '${object.objectId}'`);
    }
    if (!definition || object.initialState === undefined) continue;
    const state = object.initialState;
    const allowed = definition.collectible
      ? new Set(['quantity', 'remaining'])
      : definition.resourceNode
        ? new Set(['health', 'dropObjectId', 'dropVisualId', 'dropPieces'])
        : definition.destructible
          ? new Set(['health'])
        : new Set<string>();
    for (const key of Object.keys(state)) {
      if (!allowed.has(key)) issues.push(`${objectPath}.initialState.${key}: not supported by '${object.objectId}'`);
    }
    if (definition.collectible) {
      const defaultQuantity = definition.collectible.quantity;
      const quantity = state.quantity ?? defaultQuantity;
      if (!Number.isInteger(quantity) || (quantity as number) < 1) {
        issues.push(`${objectPath}.initialState.quantity: expected integer >= 1`);
      }
      if (state.remaining !== undefined && (!Number.isInteger(state.remaining)
        || (state.remaining as number) < 0
        || (typeof quantity === 'number' && (state.remaining as number) > quantity))) {
        issues.push(`${objectPath}.initialState.remaining: expected integer from 0 through starting quantity`);
      }
      continue;
    }
    if (definition.destructible) {
      const defaultHealth = definition.destructible.health;
      if (state.health !== undefined && (!Number.isInteger(state.health)
        || (state.health as number) < 0
        || (typeof defaultHealth === 'number' && (state.health as number) > defaultHealth))) {
        issues.push(`${objectPath}.initialState.health: expected integer from 0 through ${String(defaultHealth)}`);
      }
      continue;
    }
    if (!definition.resourceNode) {
      if (Object.keys(state).length > 0) issues.push(`${objectPath}.initialState: object has no gameplay overrides`);
      continue;
    }
    const resource = definition.resourceNode;
    const defaultHealth = resource.health;
    if (state.health !== undefined && (!Number.isInteger(state.health)
      || (state.health as number) < 0
      || (typeof defaultHealth === 'number' && (state.health as number) > defaultHealth))) {
      issues.push(`${objectPath}.initialState.health: expected integer from 0 through ${String(defaultHealth)}`);
    }
    const defaultDrop = isRecord(resource.drop) ? resource.drop : {};
    const dropObjectId = typeof state.dropObjectId === 'string' ? state.dropObjectId : defaultDrop.objectId;
    const dropDefinition = typeof dropObjectId === 'string' ? await loadObjectDefinition(dropObjectId) : undefined;
    const dropVisualId = typeof state.dropVisualId === 'string'
      ? state.dropVisualId
      : state.dropObjectId !== undefined
        ? dropDefinition?.variants[0]?.frames[0]?.visualId
        : defaultDrop.visualId;
    if (!dropDefinition?.collectible) {
      issues.push(`${objectPath}.initialState.dropObjectId: must reference a collectible object`);
    } else if (typeof dropVisualId !== 'string' || !dropDefinition.variants.some((variant) => variant.frames.some((frame) => frame.visualId === dropVisualId))) {
      issues.push(`${objectPath}.initialState.dropVisualId: unknown visual '${String(dropVisualId)}' for '${String(dropObjectId)}'`);
    }
    if (state.dropPieces !== undefined && (!Number.isInteger(state.dropPieces) || (state.dropPieces as number) < 1)) {
      issues.push(`${objectPath}.initialState.dropPieces: expected integer >= 1`);
    }
  }
  for (const [enemyIndex, enemy] of (map.spawns?.enemies ?? []).entries()) {
    if (!ENEMY_IDS.has(enemy.type)) issues.push(`spawns.enemies[${enemyIndex}].type: unknown enemy '${enemy.type}'`);
  }
  for (const [areaIndex, area] of (map.enemySpawnAreas ?? []).entries()) {
    for (const [enemyIndex, enemy] of area.enemies.entries()) {
      if (!ENEMY_IDS.has(enemy.type)) {
        issues.push(`enemySpawnAreas[${areaIndex}].enemies[${enemyIndex}].type: unknown enemy '${enemy.type}'`);
      }
    }
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
  const suppressMapHotUpdates = new Set<string>();
  return {
    name: 'slime-map-editor-save',
    apply: 'serve',
    handleHotUpdate(context) {
      const file = path.resolve(context.file);
      // The editor already owns the current map state. Suppress only the
      // watcher event caused by its atomic save; unrelated manual map edits
      // continue through Vite's normal HMR path.
      if (suppressMapHotUpdates.delete(file)) return [];
      return undefined;
    },
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
          const update = await validateObjectVisualUpdate(payload, definition);

          update.frame.displayName = update.displayName;
          update.frame.scale = update.scale;
          update.frame.visualOffset = update.visualOffset;
          if (definition.physics === null) delete update.frame.collider;
          else update.frame.collider = update.collider;
          if (update.depthBounds) update.frame.depthBounds = update.depthBounds;
          else delete update.frame.depthBounds;
          if (update.occlusionBounds) update.frame.occlusionBounds = update.occlusionBounds;
          else delete update.frame.occlusionBounds;
          if ('idleAnimationId' in payload) {
            if (update.idleAnimationId) update.frame.idleAnimationId = update.idleAnimationId;
            else delete update.frame.idleAnimationId;
          }
          if ('onHitAnimationId' in payload) {
            if (update.onHitAnimationId) update.frame.onHitAnimationId = update.onHitAnimationId;
            else delete update.frame.onHitAnimationId;
          }

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
            scale: update.scale,
            visualOffset: update.visualOffset,
            collider: update.collider,
            depthBounds: update.depthBounds,
            occlusionBounds: update.occlusionBounds,
            idleAnimationId: update.frame.idleAnimationId,
            onHitAnimationId: update.frame.onHitAnimationId,
          }));
        } catch (error) {
          if (temporaryPath) await fs.rm(temporaryPath, { force: true });
          response.statusCode = 400;
          response.end(JSON.stringify({ ok: false, error: error instanceof Error ? error.message : String(error) }));
        }
      });

      server.middlewares.use('/__map-editor/object-gameplay/update', async (request, response) => {
        response.setHeader('Content-Type', 'application/json; charset=utf-8');
        if (request.method !== 'POST') {
          response.statusCode = 405;
          response.end(JSON.stringify({ ok: false, error: 'POST required' }));
          return;
        }
        let temporaryPath: string | undefined;
        try {
          const payload = JSON.parse(await readRequestBody(request)) as Record<string, unknown>;
          if (typeof payload.objectId !== 'string') throw new Error('Object ID is required');
          const definitionPath = await findObjectDefinitionPath(OBJECT_DEFINITION_ROOT, payload.objectId);
          if (!definitionPath) throw new Error(`Object definition '${payload.objectId}' was not found`);
          const definition = JSON.parse(await fs.readFile(definitionPath, 'utf8')) as MutableObjectDefinition;
          const update = await validateObjectGameplayUpdate(payload, definition);
          if (update.collectible) definition.collectible = update.collectible;
          if (update.resourceNode) definition.resourceNode = update.resourceNode;
          temporaryPath = `${definitionPath}.${process.pid}.${Date.now()}.tmp`;
          await fs.writeFile(temporaryPath, `${JSON.stringify(definition, null, 2)}\n`, 'utf8');
          await fs.rename(temporaryPath, definitionPath);
          temporaryPath = undefined;
          response.statusCode = 200;
          response.end(JSON.stringify({ ok: true, objectId: payload.objectId }));
        } catch (error) {
          if (temporaryPath) await fs.rm(temporaryPath, { force: true });
          response.statusCode = 400;
          response.end(JSON.stringify({ ok: false, error: error instanceof Error ? error.message : String(error) }));
        }
      });

      server.middlewares.use('/__map-editor/object-template/create', async (request, response) => {
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
            ['objectId', 'assetId', 'visualId', 'frame', 'displayName', 'scale', 'visualOffset', 'collider', 'depthBounds', 'occlusionBounds', 'idleAnimationId', 'onHitAnimationId'],
            'payload',
          );
          const objectId = payload.objectId;
          const assetId = payload.assetId;
          const visualId = payload.visualId;
          const frame = payload.frame;
          if (typeof objectId !== 'string' || !isObjectArchetypeId(objectId)) {
            throw new Error(`Unknown object '${String(objectId)}'`);
          }
          if (typeof assetId !== 'string' || !(assetId in ASSET_MANIFEST.assets)) {
            throw new Error(`Unknown asset '${String(assetId)}'`);
          }
          if (typeof frame !== 'number' || !Number.isInteger(frame) || frame < 0 || frame >= assetFrameCapacity(assetId)) {
            throw new Error(`Frame must be an integer inside 0..${assetFrameCapacity(assetId) - 1}`);
          }

          const definitionPath = await findObjectDefinitionPath(OBJECT_DEFINITION_ROOT, objectId);
          if (!definitionPath) throw new Error(`Object definition '${objectId}' was not found`);
          const definition = JSON.parse(await fs.readFile(definitionPath, 'utf8')) as MutableObjectDefinition;
          if (definition.variants.some((variant) => variant.frames.some((candidate) => candidate.visualId === visualId))) {
            throw new Error(`Visual '${String(visualId)}' already exists for '${objectId}'`);
          }

          const candidateDefinition: MutableObjectDefinition = {
            ...definition,
            variants: [{ assetId, frames: [{ visualId: typeof visualId === 'string' ? visualId : '', frame }] }],
          };
          const fields = { ...payload };
          delete fields.assetId;
          delete fields.frame;
          const update = await validateObjectVisualUpdate(fields, candidateDefinition);
          const createdFrame: MutableObjectFrame = {
            ...update.frame,
            visualId: update.frame.visualId,
            frame: update.frame.frame,
            displayName: update.displayName,
            scale: update.scale,
            visualOffset: update.visualOffset,
          };
          if (definition.physics === null) delete createdFrame.collider;
          else createdFrame.collider = update.collider;
          if (update.depthBounds) createdFrame.depthBounds = update.depthBounds;
          if (update.occlusionBounds) createdFrame.occlusionBounds = update.occlusionBounds;
          if (payload.idleAnimationId !== undefined) {
            if (update.idleAnimationId) createdFrame.idleAnimationId = update.idleAnimationId;
            else delete createdFrame.idleAnimationId;
          }
          if (payload.onHitAnimationId !== undefined) {
            if (update.onHitAnimationId) createdFrame.onHitAnimationId = update.onHitAnimationId;
            else delete createdFrame.onHitAnimationId;
          }

          const variant = definition.variants.find((candidate) => candidate.assetId === assetId);
          if (variant) variant.frames.push(createdFrame);
          else definition.variants.push({ assetId, frames: [createdFrame] });

          temporaryPath = `${definitionPath}.${process.pid}.${Date.now()}.tmp`;
          await fs.writeFile(temporaryPath, `${JSON.stringify(definition, null, 2)}\n`, 'utf8');
          await fs.rename(temporaryPath, definitionPath);
          temporaryPath = undefined;
          response.statusCode = 201;
          response.end(JSON.stringify({
            ok: true,
            objectId,
            visualId: createdFrame.visualId,
            assetId,
            frame: createdFrame.frame,
            displayName: update.displayName,
            reloadRequired: true,
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
            ['objectId', 'sourceVisualId', 'visualId', 'displayName', 'scale', 'visualOffset', 'collider', 'depthBounds', 'occlusionBounds'],
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
          const update = await validateObjectVisualUpdate({
            objectId,
            visualId: sourceVisualId,
            displayName: payload.displayName,
            scale: payload.scale,
            visualOffset: payload.visualOffset,
            collider: payload.collider,
            depthBounds: payload.depthBounds,
            occlusionBounds: payload.occlusionBounds,
            idleAnimationId: payload.idleAnimationId,
            onHitAnimationId: payload.onHitAnimationId,
          }, definition);

          const duplicatedFrame: MutableObjectFrame = {
            ...update.frame,
            visualId,
            displayName: update.displayName,
            scale: update.scale,
            visualOffset: update.visualOffset,
          };
          if (definition.physics === null) delete duplicatedFrame.collider;
          else duplicatedFrame.collider = update.collider;
          if (update.depthBounds) duplicatedFrame.depthBounds = update.depthBounds;
          else delete duplicatedFrame.depthBounds;
          if (update.occlusionBounds) duplicatedFrame.occlusionBounds = update.occlusionBounds;
          else delete duplicatedFrame.occlusionBounds;
          if (payload.idleAnimationId !== undefined) {
            if (update.idleAnimationId) duplicatedFrame.idleAnimationId = update.idleAnimationId;
            else delete duplicatedFrame.idleAnimationId;
          }
          if (payload.onHitAnimationId !== undefined) {
            if (update.onHitAnimationId) duplicatedFrame.onHitAnimationId = update.onHitAnimationId;
            else delete duplicatedFrame.onHitAnimationId;
          }
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
            depthBounds: update.depthBounds,
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
            suppressMapHotUpdates.add(path.resolve(filesToWrite[index].target));
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
  plugins: [characterContentModulesPlugin(), animationContentModulesPlugin(), gameConstantsContentPlugin(), mapEditorSavePlugin()],
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
