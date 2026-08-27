#!/usr/bin/env node
/** Validates one-file-per-object archetypes and their asset/frame references. */

import { readFileSync, readdirSync } from 'node:fs';
import { basename, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadValidatedResourceTags } from './lib/resource-tag-catalog.mjs';

const repoRoot = fileURLToPath(new URL('..', import.meta.url));
const objectRoot = resolve(process.env.SLIME_CHECK_OBJECT_ROOT ?? join(repoRoot, 'src', 'game', 'content', 'objects'));
const animationRoot = join(repoRoot, 'src', 'game', 'content', 'animations');
const effectRoot = join(repoRoot, 'src', 'game', 'content', 'effects');
const itemRoot = join(repoRoot, 'src', 'game', 'content', 'items');
const weaponRoot = join(repoRoot, 'src', 'game', 'content', 'weapons');
const manifest = JSON.parse(readFileSync(join(repoRoot, 'asset', 'assets.json'), 'utf8'));
const gameConstantsPath = resolve(process.env.SLIME_CHECK_GAME_CONSTANTS_PATH ?? join(repoRoot, 'src', 'game', 'content', 'game-constants.json'));
let resourceTags;
try {
  resourceTags = await loadValidatedResourceTags(repoRoot, gameConstantsPath);
} catch (error) {
  console.error(`objects:check failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
}
const idPattern = /^[a-z0-9]+([.-][a-z0-9-]+)+$/;
const errors = [];
const seenIds = new Map();

const knownItemIds = new Set(Object.keys(JSON.parse(readFileSync(join(itemRoot, 'items.json'), 'utf8'))));
function collectWeaponItemIds(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) collectWeaponItemIds(path);
    else if (entry.isFile() && entry.name === 'weapon.json') {
      const definition = JSON.parse(readFileSync(path, 'utf8'));
      if (typeof definition.weaponId === 'string') knownItemIds.add(definition.weaponId);
    }
  }
}
collectWeaponItemIds(weaponRoot);

function listObjectFiles(directory) {
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...listObjectFiles(path));
    if (entry.isFile() && entry.name.endsWith('.json') && entry.name !== 'objects.schema.json') {
      files.push(path);
    }
  }
  return files.sort();
}

function listAnimationFiles(directory) {
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...listAnimationFiles(path));
    else if (entry.isFile() && entry.name === 'animation.json') files.push(path);
  }
  return files;
}

function fail(file, objectId, field, message) {
  errors.push(`[${file}:${objectId}] ${field}: ${message}`);
}

function isRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function validateKeys(file, objectId, field, value, allowed) {
  if (!isRecord(value)) return;
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) fail(file, objectId, `${field}.${key}`, 'unknown property');
  }
}

function validateBounds(file, objectId, field, bounds, frame) {
  if (!isRecord(bounds)) {
    fail(file, objectId, field, 'must be an object');
    return;
  }
  validateKeys(file, objectId, field, bounds, new Set(['shape', 'width', 'height', 'radius', 'radiusX', 'radiusY', 'offsetX', 'offsetY']));

  const shape = bounds.shape ?? 'rectangle';
  if (!['rectangle', 'circle', 'ellipse'].includes(shape)) fail(file, objectId, `${field}.shape`, 'must be rectangle, circle, or ellipse');
  if (shape === 'circle' && (!Number.isInteger(bounds.radius) || bounds.radius < 1)) fail(file, objectId, `${field}.radius`, 'must be a positive integer for a circle');
  if (shape === 'ellipse' && (!Number.isInteger(bounds.radiusX) || bounds.radiusX < 1 || !Number.isInteger(bounds.radiusY) || bounds.radiusY < 1)) fail(file, objectId, field, 'ellipse radii must be positive integers');

  for (const property of ['width', 'height', 'offsetX', 'offsetY']) {
    const minimum = property.startsWith('offset') ? 0 : 1;
    if (!Number.isInteger(bounds[property]) || bounds[property] < minimum) {
      fail(file, objectId, `${field}.${property}`, `must be an integer >= ${minimum}`);
    }
  }

  if (Number.isInteger(bounds.offsetX) && Number.isInteger(bounds.width)
      && bounds.offsetX + bounds.width > frame.w) {
    fail(file, objectId, field, `horizontal collider exceeds frame width ${frame.w}`);
  }
  if (Number.isInteger(bounds.offsetY) && Number.isInteger(bounds.height)
      && bounds.offsetY + bounds.height > frame.h) {
    fail(file, objectId, field, `vertical collider exceeds frame height ${frame.h}`);
  }
}

function validateDepthBounds(file, objectId, field, bounds, frame) {
  if (!isRecord(bounds)) {
    fail(file, objectId, field, 'must be an object');
    return;
  }
  validateKeys(file, objectId, field, bounds, new Set(['width', 'height', 'offsetX', 'offsetY']));
  for (const property of ['width', 'height', 'offsetX', 'offsetY']) {
    const minimum = property.startsWith('offset') ? 0 : 1;
    if (!Number.isInteger(bounds[property]) || bounds[property] < minimum) {
      fail(file, objectId, `${field}.${property}`, `must be an integer >= ${minimum}`);
    }
  }
  if (Number.isInteger(bounds.offsetX) && Number.isInteger(bounds.width)
      && bounds.offsetX + bounds.width > frame.w) {
    fail(file, objectId, field, `horizontal depth bound exceeds frame width ${frame.w}`);
  }
  if (Number.isInteger(bounds.offsetY) && Number.isInteger(bounds.height)
      && bounds.offsetY + bounds.height > frame.h) {
    fail(file, objectId, field, `vertical depth bound exceeds frame height ${frame.h}`);
  }
}

function validateVisualOffset(file, objectId, field, offset) {
  if (!isRecord(offset)) {
    fail(file, objectId, field, 'must be an object');
    return;
  }
  validateKeys(file, objectId, field, offset, new Set(['x', 'y']));
  for (const property of ['x', 'y']) {
    if (!Number.isInteger(offset[property])) fail(file, objectId, `${field}.${property}`, 'must be an integer');
  }
}

function listEffectIds(directory) {
  const ids = new Set();
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      for (const id of listEffectIds(path)) ids.add(id);
    } else if (entry.isFile() && entry.name === 'effect.json') {
      const definition = JSON.parse(readFileSync(path, 'utf8'));
      if (typeof definition.effectId === 'string') ids.add(definition.effectId);
    }
  }
  return ids;
}

function validateVisualScale(file, objectId, field, scale) {
  if (typeof scale !== 'number' || !Number.isFinite(scale) || scale < 0.05 || scale > 8) {
    fail(file, objectId, field, 'must be a finite number between 0.05 and 8');
  }
}

const objectFiles = listObjectFiles(objectRoot);
const knownObjectDefinitions = new Map();
for (const absolutePath of objectFiles) {
  try {
    const definition = JSON.parse(readFileSync(absolutePath, 'utf8'));
    if (typeof definition.objectId === 'string') knownObjectDefinitions.set(definition.objectId, definition);
  } catch {
    // The main validation pass reports malformed JSON with the source file.
  }
}
const animations = new Map(
  listAnimationFiles(animationRoot).map((path) => {
    const definition = JSON.parse(readFileSync(path, 'utf8'));
    return [definition.animationId, definition];
  }),
);
const effectIds = listEffectIds(effectRoot);

for (const absolutePath of objectFiles) {
  const file = relative(objectRoot, absolutePath).replaceAll('\\', '/');
  let object;
  try {
    object = JSON.parse(readFileSync(absolutePath, 'utf8'));
  } catch (error) {
    fail(file, '<file>', 'json', error.message);
    continue;
  }

  const objectId = object.objectId ?? '<missing-id>';
  validateKeys(
    file,
    objectId,
    'object',
    object,
    new Set(['$schema', 'objectId', 'selection', 'variants', 'physics', 'behavior', 'collectible', 'destructible', 'resourceNode', 'tags']),
  );

  if (typeof object.objectId !== 'string' || !idPattern.test(object.objectId)) {
    fail(file, objectId, 'objectId', 'must be a lowercase dotted ID');
  } else {
    const expectedFilename = `${object.objectId.replaceAll('.', '-')}.json`;
    if (basename(absolutePath) !== expectedFilename) {
      fail(file, objectId, 'objectId', `filename must be '${expectedFilename}'`);
    }
    if (seenIds.has(object.objectId)) {
      fail(file, objectId, 'objectId', `duplicate of ${seenIds.get(object.objectId)}`);
    } else {
      seenIds.set(object.objectId, file);
    }
  }

  if (object.selection !== 'authored') {
    fail(file, objectId, 'selection', "must be 'authored'");
  }

  const hasPhysics = object.physics !== null;
  if (object.behavior !== undefined && (typeof object.behavior !== 'string' || !idPattern.test(object.behavior))) {
    fail(file, objectId, 'behavior', 'must be a lowercase dotted ID');
  }
  if (hasPhysics) {
    if (!isRecord(object.physics) || object.physics.body !== 'static') {
      fail(file, objectId, 'physics', "must be null or { body: 'static' }");
    } else {
      validateKeys(file, objectId, 'physics', object.physics, new Set(['body']));
    }
  }

  if (!Array.isArray(object.variants) || object.variants.length === 0) {
    fail(file, objectId, 'variants', 'must be a non-empty array');
  } else {
    const seenVisualIds = new Set();
    for (const [groupIndex, group] of object.variants.entries()) {
      const groupField = `variants.${groupIndex}`;
      if (!isRecord(group)) {
        fail(file, objectId, groupField, 'must be an object');
        continue;
      }
      validateKeys(file, objectId, groupField, group, new Set(['assetId', 'frames']));

      const asset = manifest.assets[group.assetId];
      if (!asset) {
        fail(file, objectId, `${groupField}.assetId`, `unknown asset '${group.assetId}'`);
        continue;
      }
      if (asset.source?.kind !== 'spritesheet' && asset.source?.kind !== 'procedural') {
        fail(file, objectId, `${groupField}.assetId`, 'object variants require spritesheet or procedural media');
        continue;
      }
      if (!Array.isArray(group.frames) || group.frames.length === 0) {
        fail(file, objectId, `${groupField}.frames`, 'must be a non-empty array');
        continue;
      }

      const frame = asset.source.kind === 'spritesheet' ? asset.source.frame : null;
      const frameCount = frame ? frame.cols * frame.rows : 1;
      for (const [frameEntryIndex, frameEntry] of group.frames.entries()) {
        const frameField = `${groupField}.frames.${frameEntryIndex}`;
        if (!isRecord(frameEntry)) {
          fail(file, objectId, frameField, 'must be an object');
          continue;
        }
        validateKeys(
          file,
          objectId,
          frameField,
          frameEntry,
          new Set([
            'visualId',
            'frame',
            'displayName',
            'scale',
            'visualOffset',
            'depthBounds',
            'occlusionBounds',
            'idleAnimationId',
            'onHitAnimationId',
            'collider',
          ]),
        );

        if (typeof frameEntry.visualId !== 'string' || !/^[a-z0-9]+([.-][a-z0-9-]+)*$/.test(frameEntry.visualId)) {
          fail(file, objectId, `${frameField}.visualId`, 'must be a lowercase stable visual ID');
        } else if (seenVisualIds.has(frameEntry.visualId)) {
          fail(file, objectId, `${frameField}.visualId`, `duplicate visual ID '${frameEntry.visualId}'`);
        } else {
          seenVisualIds.add(frameEntry.visualId);
        }

        if (!Number.isInteger(frameEntry.frame) || frameEntry.frame < 0 || frameEntry.frame >= frameCount) {
          fail(file, objectId, `${frameField}.frame`, `must be inside spritesheet range 0..${frameCount - 1}`);
        }

        if (frameEntry.displayName !== undefined
            && (typeof frameEntry.displayName !== 'string'
              || frameEntry.displayName.trim().length === 0
              || frameEntry.displayName.length > 80)) {
          fail(file, objectId, `${frameField}.displayName`, 'must contain 1 to 80 characters');
        }
        if (frameEntry.visualOffset !== undefined) {
          validateVisualOffset(file, objectId, `${frameField}.visualOffset`, frameEntry.visualOffset);
        }
        if (frameEntry.scale !== undefined) {
          validateVisualScale(file, objectId, `${frameField}.scale`, frameEntry.scale);
        }

        const hasIdleAnimation = frameEntry.idleAnimationId !== undefined;
        const hasOnHitAnimation = frameEntry.onHitAnimationId !== undefined;

        for (const [field, expectedLoop] of [['idleAnimationId', true], ['onHitAnimationId', false]]) {
          const value = frameEntry[field];
          if (value === undefined) continue;
          if (typeof value !== 'string' || !idPattern.test(value)) {
            fail(file, objectId, `${frameField}.${field}`, 'must be a lowercase dotted animation ID');
          } else if (!animations.has(value)) {
            fail(file, objectId, `${frameField}.${field}`, `unknown animation '${value}'`);
          } else if (animations.get(value).animation.loop !== expectedLoop) {
            fail(file, objectId, `${frameField}.${field}`, `animation '${value}' has the wrong loop contract`);
          }
        }

        if (frameEntry.occlusionBounds !== undefined) {
          if (asset.source.kind !== 'spritesheet') {
            fail(file, objectId, `${frameField}.occlusionBounds`, 'procedural object variants cannot define occlusion bounds');
          } else if (hasIdleAnimation || hasOnHitAnimation) {
            fail(file, objectId, `${frameField}.occlusionBounds`, 'animated object variants cannot define occlusion bounds');
          } else if (frame) {
            validateBounds(file, objectId, `${frameField}.occlusionBounds`, frameEntry.occlusionBounds, frame);
          }
        }

        if (frameEntry.depthBounds !== undefined) {
          if (asset.source.kind !== 'spritesheet') {
            fail(file, objectId, `${frameField}.depthBounds`, 'procedural object variants cannot define depth bounds');
          } else if (frame) {
            validateDepthBounds(file, objectId, `${frameField}.depthBounds`, frameEntry.depthBounds, frame);
          }
        }

        if (hasPhysics && frameEntry.collider === undefined) {
          fail(file, objectId, `${frameField}.collider`, 'required because this object has physics');
        } else if (!hasPhysics && frameEntry.collider !== undefined) {
          fail(file, objectId, `${frameField}.collider`, 'decorative objects must not define colliders');
        } else if (frameEntry.collider !== undefined) {
          if (frame) validateBounds(file, objectId, `${frameField}.collider`, frameEntry.collider, frame);
        }
      }
    }
  }

  if (!Array.isArray(object.tags) || object.tags.some((tag) => typeof tag !== 'string' || !/^[a-z0-9-]+$/.test(tag))) {
    fail(file, objectId, 'tags', 'must contain lowercase kebab strings');
  }

  if (object.destructible !== undefined) {
    validateKeys(file, objectId, 'destructible', object.destructible, new Set(['health', 'drops']));
    if (!Number.isInteger(object.destructible.health) || object.destructible.health < 1) {
      fail(file, objectId, 'destructible.health', 'must be an integer >= 1');
    }
    if (!Array.isArray(object.destructible.drops)
        || object.destructible.drops.some((drop) => typeof drop !== 'string' || drop.length === 0)) {
      fail(file, objectId, 'destructible.drops', 'must contain non-empty item IDs');
    }
  }

  if (object.collectible !== undefined) {
    validateKeys(file, objectId, 'collectible', object.collectible, new Set(['itemId', 'quantity']));
    if (typeof object.collectible.itemId !== 'string' || object.collectible.itemId.length === 0) {
      fail(file, objectId, 'collectible.itemId', 'must be a non-empty item ID');
    } else if (!knownItemIds.has(object.collectible.itemId)) {
      fail(file, objectId, 'collectible.itemId', `unknown inventory item '${object.collectible.itemId}'`);
    }
    if (!Number.isInteger(object.collectible.quantity) || object.collectible.quantity < 1) {
      fail(file, objectId, 'collectible.quantity', 'must be an integer >= 1');
    }
    if (object.physics !== null) fail(file, objectId, 'physics', 'collectibles must not be solid');
    if (!Array.isArray(object.tags) || !object.tags.includes('collectible')) {
      fail(file, objectId, 'tags', 'collectible objects must include the collectible tag');
    }
  }

  if (object.collectible !== undefined && object.resourceNode !== undefined) {
    fail(file, objectId, 'object', 'cannot define both collectible and resourceNode capabilities');
  }
  if (Array.isArray(object.tags) && object.tags.includes('collectible') && object.collectible === undefined) {
    fail(file, objectId, 'tags', 'the collectible tag requires a collectible payload');
  }

  if (object.resourceNode !== undefined) {
    validateKeys(file, objectId, 'resourceNode', object.resourceNode, new Set(['health', 'drop', 'hitEffectId', 'persistHealth', 'depletionMessage', 'harvestRequirement']));
    if (!Number.isInteger(object.resourceNode.health) || object.resourceNode.health < 1) {
      fail(file, objectId, 'resourceNode.health', 'must be an integer >= 1');
    }
    const drop = object.resourceNode.drop;
    if (!isRecord(drop)) {
      fail(file, objectId, 'resourceNode.drop', 'must be an object with objectId, visualId, and pieces');
    } else {
      validateKeys(file, objectId, 'resourceNode.drop', drop, new Set(['objectId', 'visualId', 'pieces']));
      const target = knownObjectDefinitions.get(drop.objectId);
      if (typeof drop.objectId !== 'string' || !idPattern.test(drop.objectId) || !target) {
        fail(file, objectId, 'resourceNode.drop.objectId', `unknown collectible object '${String(drop.objectId)}'`);
      } else if (!target.collectible) {
        fail(file, objectId, 'resourceNode.drop.objectId', 'must reference an object with collectible data');
      }
      if (typeof drop.visualId !== 'string' || drop.visualId.length === 0) {
        fail(file, objectId, 'resourceNode.drop.visualId', 'must be a non-empty visual ID');
      } else if (target && !target.variants?.some((variant) => variant.frames?.some((frame) => frame.visualId === drop.visualId))) {
        fail(file, objectId, 'resourceNode.drop.visualId', `unknown visual '${drop.visualId}' for '${drop.objectId}'`);
      }
      if (!Number.isInteger(drop.pieces) || drop.pieces < 1) {
        fail(file, objectId, 'resourceNode.drop.pieces', 'must be an integer >= 1');
      }
    }
    if (object.resourceNode.hitEffectId !== undefined) {
      if (typeof object.resourceNode.hitEffectId !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(object.resourceNode.hitEffectId)) {
        fail(file, objectId, 'resourceNode.hitEffectId', 'must be a lowercase kebab-case effect ID');
      } else if (!effectIds.has(object.resourceNode.hitEffectId)) {
        fail(file, objectId, 'resourceNode.hitEffectId', `unknown effect '${object.resourceNode.hitEffectId}'`);
      }
    }
    if (object.resourceNode.persistHealth !== undefined && typeof object.resourceNode.persistHealth !== 'boolean') {
      fail(file, objectId, 'resourceNode.persistHealth', 'must be a boolean');
    }
    if (object.resourceNode.depletionMessage !== undefined
        && (typeof object.resourceNode.depletionMessage !== 'string'
          || object.resourceNode.depletionMessage.trim().length === 0
          || object.resourceNode.depletionMessage.length > 80)) {
      fail(file, objectId, 'resourceNode.depletionMessage', 'must contain 1 to 80 characters');
    }
    if (object.resourceNode.harvestRequirement !== undefined) {
      const requirement = object.resourceNode.harvestRequirement;
      validateKeys(file, objectId, 'resourceNode.harvestRequirement', requirement, new Set(['targetTag', 'minimumTier', 'failureMessage']));
      if (typeof requirement.targetTag !== 'string' || requirement.targetTag.length === 0) {
        fail(file, objectId, 'resourceNode.harvestRequirement.targetTag', 'must be a non-empty resource tag');
      } else if (!resourceTags.has(requirement.targetTag)) {
        fail(file, objectId, 'resourceNode.harvestRequirement.targetTag', `unknown resource tag '${requirement.targetTag}'; configured tags: ${[...resourceTags].join(', ')}`);
      }
      if (!Number.isInteger(requirement.minimumTier) || requirement.minimumTier < 1) {
        fail(file, objectId, 'resourceNode.harvestRequirement.minimumTier', 'must be an integer >= 1');
      }
      if (typeof requirement.failureMessage !== 'string' || requirement.failureMessage.trim().length === 0 || requirement.failureMessage.length > 80) {
        fail(file, objectId, 'resourceNode.harvestRequirement.failureMessage', 'must contain 1 to 80 characters');
      }
    }
  }
}

if (errors.length > 0) {
  console.error(`objects:check failed with ${errors.length} error(s):`);
  for (const error of errors) console.error(`  - ${error}`);
  process.exit(1);
}

console.log(`objects:check OK - ${objectFiles.length} object file(s), all asset/frame/collider references valid.`);
