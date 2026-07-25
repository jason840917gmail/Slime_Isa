#!/usr/bin/env node
/** Validates editor-friendly visual-set JSON and its manifest/frame references. */

import { readFileSync, readdirSync } from 'node:fs';
import { basename, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('..', import.meta.url));
const visualRoot = join(repoRoot, 'src', 'game', 'content', 'visuals');
const manifest = JSON.parse(readFileSync(join(repoRoot, 'asset', 'assets.json'), 'utf8'));
const idPattern = /^[a-z0-9]+([.-][a-z0-9-]+)+$/;
const clipPattern = /^[a-z0-9]+([.-][a-z0-9-]+)*$/;
const errors = [];
const visualSetIds = new Map();
const runtimeKeys = new Map();
const requiredClipsByVisualSet = new Map([
  ['character.player.slime', ['knockback']],
]);

function listVisualSetFiles(directory) {
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...listVisualSetFiles(path));
    if (entry.isFile() && entry.name === 'visual-set.json') files.push(path);
  }
  return files.sort();
}

function fail(file, visualSetId, field, message) {
  errors.push(`[${file}:${visualSetId}] ${field}: ${message}`);
}

function isRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function validateKeys(file, visualSetId, field, value, allowed) {
  if (!isRecord(value)) return;
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) fail(file, visualSetId, `${field}.${key}`, 'unknown property');
  }
}

function validatePair(file, visualSetId, field, pair, predicate, required) {
  if (pair === undefined && !required) return;
  if (!Array.isArray(pair) || pair.length !== 2) {
    fail(file, visualSetId, field, 'must contain exactly two numbers');
    return;
  }
  pair.forEach((entry, index) => {
    if (!Number.isFinite(entry) || !predicate(entry)) {
      fail(file, visualSetId, `${field}.${index}`, 'contains an invalid number');
    }
  });
}

function validateTransform(file, visualSetId, field, transform, required) {
  if (!isRecord(transform)) {
    fail(file, visualSetId, field, 'must be an object');
    return;
  }
  validateKeys(file, visualSetId, field, transform, new Set(['origin', 'scale', 'sourceOffset']));
  validatePair(file, visualSetId, `${field}.origin`, transform.origin, (entry) => entry >= 0 && entry <= 1, required);
  validatePair(file, visualSetId, `${field}.scale`, transform.scale, (entry) => entry > 0, required);
  validatePair(file, visualSetId, `${field}.sourceOffset`, transform.sourceOffset, () => true, required);
}

for (const absolutePath of listVisualSetFiles(visualRoot)) {
  const file = relative(visualRoot, absolutePath).replaceAll('\\', '/');
  let definition;
  try {
    definition = JSON.parse(readFileSync(absolutePath, 'utf8'));
  } catch (error) {
    fail(file, '<file>', 'json', error.message);
    continue;
  }

  const visualSetId = definition.visualSetId ?? '<missing-id>';
  validateKeys(
    file,
    visualSetId,
    'visualSet',
    definition,
    new Set(['$schema', 'visualSetId', 'assetId', 'defaults', 'frameVisuals', 'clips']),
  );

  if (typeof definition.visualSetId !== 'string' || !idPattern.test(definition.visualSetId)) {
    fail(file, visualSetId, 'visualSetId', 'must be a lowercase dotted ID');
  } else if (visualSetIds.has(definition.visualSetId)) {
    fail(file, visualSetId, 'visualSetId', `duplicate of ${visualSetIds.get(definition.visualSetId)}`);
  } else {
    visualSetIds.set(definition.visualSetId, file);
  }

  if (basename(absolutePath) !== 'visual-set.json') {
    fail(file, visualSetId, 'file', "must be named 'visual-set.json'");
  }

  const asset = manifest.assets[definition.assetId];
  if (!asset) {
    fail(file, visualSetId, 'assetId', `unknown asset '${definition.assetId}'`);
    continue;
  }
  if (!['spritesheet', 'image', 'procedural'].includes(asset.source?.kind)) {
    fail(file, visualSetId, 'assetId', 'must reference spritesheet, image, or procedural media');
    continue;
  }

  const frameCount = asset.source.kind === 'spritesheet'
    ? asset.source.frame.count ?? asset.source.frame.cols * asset.source.frame.rows
    : 1;

  validateTransform(file, visualSetId, 'defaults', definition.defaults, true);

  if (definition.frameVisuals !== undefined && !isRecord(definition.frameVisuals)) {
    fail(file, visualSetId, 'frameVisuals', 'must be an object keyed by source frame');
  } else {
    for (const [frameText, transform] of Object.entries(definition.frameVisuals ?? {})) {
      const frame = Number(frameText);
      if (!/^(0|[1-9][0-9]*)$/.test(frameText) || frame < 0 || frame >= frameCount) {
        fail(file, visualSetId, `frameVisuals.${frameText}`, `must be inside 0..${frameCount - 1}`);
      }
      validateTransform(file, visualSetId, `frameVisuals.${frameText}`, transform, false);
    }
  }

  if (!isRecord(definition.clips) || Object.keys(definition.clips).length === 0) {
    fail(file, visualSetId, 'clips', 'must be a non-empty object');
    continue;
  }

  for (const requiredClip of requiredClipsByVisualSet.get(visualSetId) ?? []) {
    if (!definition.clips[requiredClip]) {
      fail(file, visualSetId, `clips.${requiredClip}`, 'required by the visual contract');
    }
  }

  for (const [clipId, clip] of Object.entries(definition.clips)) {
    const field = `clips.${clipId}`;
    if (!clipPattern.test(clipId)) {
      fail(file, visualSetId, field, 'clip ID must be lowercase kebab/dotted text');
    }
    if (!isRecord(clip)) {
      fail(file, visualSetId, field, 'must be an object');
      continue;
    }
    validateKeys(file, visualSetId, field, clip, new Set(['runtimeKey', 'frames', 'frameRate', 'repeat']));
    if (typeof clip.runtimeKey !== 'string' || !clipPattern.test(clip.runtimeKey)) {
      fail(file, visualSetId, `${field}.runtimeKey`, 'must be a lowercase stable animation key');
    } else if (runtimeKeys.has(clip.runtimeKey)) {
      fail(file, visualSetId, `${field}.runtimeKey`, `duplicate of ${runtimeKeys.get(clip.runtimeKey)}`);
    } else {
      runtimeKeys.set(clip.runtimeKey, `${visualSetId}.${clipId}`);
    }
    if (!Array.isArray(clip.frames) || clip.frames.length === 0) {
      fail(file, visualSetId, `${field}.frames`, 'must contain at least one source frame');
    } else {
      clip.frames.forEach((frame, index) => {
        if (!Number.isInteger(frame) || frame < 0 || frame >= frameCount) {
          fail(file, visualSetId, `${field}.frames.${index}`, `must be inside 0..${frameCount - 1}`);
        }
      });
    }
    if (!Number.isFinite(clip.frameRate) || clip.frameRate <= 0) {
      fail(file, visualSetId, `${field}.frameRate`, 'must be greater than zero');
    }
    if (!Number.isInteger(clip.repeat) || clip.repeat < -1) {
      fail(file, visualSetId, `${field}.repeat`, 'must be an integer >= -1');
    }
  }
}

for (const visualSetId of requiredClipsByVisualSet.keys()) {
  if (!visualSetIds.has(visualSetId)) {
    fail('<catalog>', visualSetId, 'visualSetId', 'required visual set is missing');
  }
}

if (errors.length > 0) {
  console.error(`visuals:check failed with ${errors.length} error(s):`);
  for (const error of errors) console.error(`  - ${error}`);
  process.exit(1);
}

console.log(
  `visuals:check OK - ${visualSetIds.size} visual set(s), ` +
  `${runtimeKeys.size} unique runtime animation key(s).`,
);
