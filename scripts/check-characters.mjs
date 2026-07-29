#!/usr/bin/env node
/** Validates version-1 character packages and visual discovery contracts. */

import { readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const characterRoot = join(root, 'src', 'game', 'content', 'characters');
const visualRoot = join(root, 'src', 'game', 'content', 'visuals');
const manifest = JSON.parse(readFileSync(join(root, 'asset', 'assets.json'), 'utf8'));
const idPattern = /^[a-z0-9]+(?:[.-][a-z0-9-]+)*$/;
const characterIdPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const errors = [];
const characterIds = new Map();
const visualIds = new Map();
const primaryPlayers = [];

function isRecord(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function listFiles(directory, fileName, output = []) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.name.startsWith('.') || entry.name.startsWith('.character-studio-')) continue;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) listFiles(path, fileName, output);
    else if (entry.isFile() && entry.name === fileName) output.push(path);
  }
  return output.sort();
}
function fail(file, path, message) { errors.push(`[${relative(root, file)}] ${path}: ${message}`); }
function keys(file, path, value, allowed) { if (isRecord(value)) for (const key of Object.keys(value)) if (!allowed.has(key)) fail(file, `${path}.${key}`, 'unknown property'); }
function finite(file, path, value, predicate, message) { if (typeof value !== 'number' || !Number.isFinite(value) || !predicate(value)) fail(file, path, message); }
function integer(file, path, value, predicate, message) { if (!Number.isInteger(value) || !predicate(value)) fail(file, path, message); }
function pair(file, path, value, predicate) { if (!Array.isArray(value) || value.length !== 2) { fail(file, path, 'must contain two numbers'); return; } value.forEach((entry, index) => finite(file, `${path}[${index}]`, entry, predicate, 'invalid number')); }
function transform(file, path, value, required) {
  if (!isRecord(value)) { fail(file, path, 'must be an object'); return; }
  keys(file, path, value, new Set(['origin', 'scale', 'sourceOffset']));
  if (required || value.origin !== undefined) pair(file, `${path}.origin`, value.origin, (entry) => entry >= 0 && entry <= 1);
  if (required || value.scale !== undefined) pair(file, `${path}.scale`, value.scale, (entry) => entry > 0);
  if (required || value.sourceOffset !== undefined) pair(file, `${path}.sourceOffset`, value.sourceOffset, () => true);
}
function frameCount(assetId) {
  const asset = manifest.assets[assetId];
  if (!asset) return undefined;
  return asset.source.kind === 'spritesheet' ? asset.source.frame.count ?? asset.source.frame.cols * asset.source.frame.rows : 1;
}

for (const file of listFiles(characterRoot, 'visual-set.json')) {
  let value;
  try { value = JSON.parse(readFileSync(file, 'utf8')); } catch (error) { fail(file, 'json', error.message); continue; }
  keys(file, 'visualSet', value, new Set(['$schema', 'version', 'visualSetId', 'assetId', 'defaults', 'frameVisuals', 'clips']));
  if (value.version !== 1) fail(file, 'version', 'must be 1');
  if (typeof value.visualSetId !== 'string' || !idPattern.test(value.visualSetId)) fail(file, 'visualSetId', 'must be a lowercase dotted ID');
  if (visualIds.has(value.visualSetId)) fail(file, 'visualSetId', `duplicates ${visualIds.get(value.visualSetId)}`); else visualIds.set(value.visualSetId, relative(root, file));
  const asset = manifest.assets[value.assetId];
  if (!asset) { fail(file, 'assetId', `unknown asset '${value.assetId}'`); continue; }
  const count = frameCount(value.assetId);
  transform(file, 'defaults', value.defaults, true);
  for (const [frameText, valueOverride] of Object.entries(value.frameVisuals ?? {})) { const frame = Number(frameText); if (!/^(0|[1-9][0-9]*)$/.test(frameText) || frame >= count) fail(file, `frameVisuals.${frameText}`, `outside 0..${count - 1}`); transform(file, `frameVisuals.${frameText}`, valueOverride, false); }
  if (!isRecord(value.clips) || Object.keys(value.clips).length === 0) { fail(file, 'clips', 'must be non-empty'); continue; }
  for (const [clipId, clip] of Object.entries(value.clips)) {
    if (!idPattern.test(clipId)) fail(file, `clips.${clipId}`, 'invalid clip ID');
    keys(file, `clips.${clipId}`, clip, new Set(['frames', 'framesPerSecond', 'loop', 'loopMode']));
    if (!Array.isArray(clip.frames) || clip.frames.length === 0) fail(file, `clips.${clipId}.frames`, 'must be non-empty');
    for (const [index, frame] of (clip.frames ?? []).entries()) if (!Number.isInteger(frame) || frame < 0 || frame >= count) fail(file, `clips.${clipId}.frames[${index}]`, `outside 0..${count - 1}`);
    finite(file, `clips.${clipId}.framesPerSecond`, clip.framesPerSecond, (entry) => entry > 0 && entry <= 240, 'must be between 0 and 240');
    if (typeof clip.loop !== 'boolean') fail(file, `clips.${clipId}.loop`, 'must be boolean');
    if (clip.loopMode !== undefined && clip.loopMode !== 'wrap' && clip.loopMode !== 'ping-pong') fail(file, `clips.${clipId}.loopMode`, "must be 'wrap' or 'ping-pong'");
  }
}

for (const file of listFiles(characterRoot, 'character.json')) {
  let value;
  try { value = JSON.parse(readFileSync(file, 'utf8')); } catch (error) { fail(file, 'json', error.message); continue; }
  keys(file, 'character', value, new Set(['$schema', 'version', 'characterId', 'displayName', 'kind', 'runtimeRole', 'visualSetId', 'attributes', 'body', 'hitboxes', 'animationTracks', 'player', 'enemy']));
  if (value.version !== 1) fail(file, 'version', 'must be 1');
  if (!characterIdPattern.test(value.characterId ?? '')) fail(file, 'characterId', 'must be lowercase kebab-case');
  if (characterIds.has(value.characterId)) fail(file, 'characterId', `duplicates ${characterIds.get(value.characterId)}`); else characterIds.set(value.characterId, relative(root, file));
  if (value.kind === 'player' && value.runtimeRole === 'primary-player') primaryPlayers.push(value.characterId);
  if (!visualIds.has(value.visualSetId)) fail(file, 'visualSetId', `no package visual set '${value.visualSetId}'`);
  if (value.attributes !== undefined) {
    keys(file, 'attributes', value.attributes, new Set(['strength', 'vitality', 'agility', 'intellect']));
    for (const field of ['strength', 'vitality', 'agility', 'intellect']) finite(file, `attributes.${field}`, value.attributes[field], (entry) => entry >= 0, 'must be zero or greater');
  }
  if (!isRecord(value.body)) fail(file, 'body', 'must be an object');
  else {
    const shape = value.body.shape ?? 'rectangle';
    if (!['rectangle', 'circle', 'ellipse'].includes(shape)) fail(file, 'body.shape', 'must be rectangle, circle, or ellipse');
    if (shape === 'circle') finite(file, 'body.radius', value.body.radius, (entry) => entry > 0, 'must be greater than zero for a circle');
    if (shape === 'ellipse') { finite(file, 'body.radiusX', value.body.radiusX, (entry) => entry > 0, 'must be greater than zero for an ellipse'); finite(file, 'body.radiusY', value.body.radiusY, (entry) => entry > 0, 'must be greater than zero for an ellipse'); }
    for (const field of ['width', 'height']) finite(file, `body.${field}`, value.body[field], (entry) => entry > 0, 'must be greater than zero');
    for (const field of ['centerOffsetX', 'centerOffsetY']) finite(file, `body.${field}`, value.body[field], () => true, 'must be finite');
  }
  if (value.kind === 'player' && !isRecord(value.player)) fail(file, 'player', 'required for players');
  if (value.kind === 'enemy' && !isRecord(value.enemy)) fail(file, 'enemy', 'required for enemies');
}

if (primaryPlayers.length !== 1) errors.push(`[catalog] primary player: expected exactly one, found ${primaryPlayers.length}`);
if (errors.length > 0) { console.error(`characters:check failed with ${errors.length} error(s):`); errors.forEach((error) => console.error(`  - ${error}`)); process.exit(1); }
console.log(`characters:check OK - ${characterIds.size} character package(s), ${visualIds.size} visual set(s), one primary player.`);
