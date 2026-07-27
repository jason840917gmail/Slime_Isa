#!/usr/bin/env node
/** Validates one-file-per-object archetypes and their asset/frame references. */

import { readFileSync, readdirSync } from 'node:fs';
import { basename, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('..', import.meta.url));
const objectRoot = join(repoRoot, 'src', 'game', 'content', 'objects');
const visualRoot = join(repoRoot, 'src', 'game', 'content', 'visuals');
const manifest = JSON.parse(readFileSync(join(repoRoot, 'asset', 'assets.json'), 'utf8'));
const idPattern = /^[a-z0-9]+([.-][a-z0-9-]+)+$/;
const errors = [];
const seenIds = new Map();

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

function listVisualSetFiles(directory) {
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...listVisualSetFiles(path));
    if (entry.isFile() && entry.name === 'visual-set.json') files.push(path);
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
  validateKeys(file, objectId, field, bounds, new Set(['width', 'height', 'offsetX', 'offsetY']));

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

const objectFiles = listObjectFiles(objectRoot);
const visualSets = new Map(
  listVisualSetFiles(visualRoot).map((path) => {
    const definition = JSON.parse(readFileSync(path, 'utf8'));
    return [definition.visualSetId, definition];
  }),
);

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
    new Set(['$schema', 'objectId', 'selection', 'variants', 'physics', 'behavior', 'destructible', 'tags']),
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
            'visualOffset',
            'visualSetId',
            'animationClip',
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

        const hasVisualSet = frameEntry.visualSetId !== undefined;
        const hasAnimationClip = frameEntry.animationClip !== undefined;
        if (hasVisualSet !== hasAnimationClip) {
          fail(
            file,
            objectId,
            frameField,
            'visualSetId and animationClip must be declared together',
          );
        } else if (hasVisualSet) {
          const visualSet = visualSets.get(frameEntry.visualSetId);
          if (!visualSet) {
            fail(
              file,
              objectId,
              `${frameField}.visualSetId`,
              `unknown visual set '${frameEntry.visualSetId}'`,
            );
          } else {
            if (visualSet.assetId !== group.assetId) {
              fail(
                file,
                objectId,
                `${frameField}.visualSetId`,
                `visual set asset '${visualSet.assetId}' does not match '${group.assetId}'`,
              );
            }
            if (!visualSet.clips?.[frameEntry.animationClip]) {
              fail(
                file,
                objectId,
                `${frameField}.animationClip`,
                `unknown clip '${frameEntry.animationClip}'`,
              );
            }
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
}

if (errors.length > 0) {
  console.error(`objects:check failed with ${errors.length} error(s):`);
  for (const error of errors) console.error(`  - ${error}`);
  process.exit(1);
}

console.log(`objects:check OK - ${objectFiles.length} object file(s), all asset/frame/collider references valid.`);
