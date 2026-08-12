#!/usr/bin/env node
/** Validates reusable v1/v2 weapon definitions without importing browser code. */
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const weaponRoot = join(root, 'src', 'game', 'content', 'weapons');
const effectRoot = join(root, 'src', 'game', 'content', 'effects');
const errors = [];
const ids = new Set();
const effectIds = new Set();

function files(directory) {
  const output = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    const target = join(directory, entry.name);
    if (entry.isDirectory()) output.push(...files(target));
    else if (entry.name === 'weapon.json') output.push(target);
  }
  return output;
}

function effectFiles(directory) {
  const output = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const target = join(directory, entry.name);
    if (entry.isDirectory()) output.push(...effectFiles(target));
    else if (entry.name === 'effect.json') output.push(target);
  }
  return output;
}
for (const file of effectFiles(effectRoot)) effectIds.add(JSON.parse(readFileSync(file, 'utf8')).effectId);

function legacyFrameCount(animation) {
  return animation?.keyframeTimes !== undefined && animation?.durationSeconds !== undefined
    ? Math.max(1, Math.round(animation.durationSeconds * animation.framesPerSecond))
    : Math.max(1, animation?.frames?.length ?? 0);
}

function layeredFrameCount(weapon, label, animation) {
  const product = animation?.durationSeconds * animation?.framesPerSecond;
  const count = Math.round(product);
  if (!(count >= 1) || Math.abs(product - count) > 1e-6) errors.push(`[${weapon.weaponId}] ${label} duration and FPS must resolve to whole frames`);
  return count;
}

function validateHitboxes(weapon, label, hitboxes) {
  for (const [id, hitbox] of Object.entries(hitboxes ?? {})) {
    if (!['rectangle', 'circle', 'ellipse', 'sector'].includes(hitbox.shape)) errors.push(`[${weapon.weaponId}] ${label}.${id} has an invalid shape`);
    if (!(hitbox.width > 0) || !(hitbox.height > 0)) errors.push(`[${weapon.weaponId}] ${label}.${id} needs positive dimensions`);
    if (hitbox.shape === 'sector' && (!(hitbox.outerRadius >= 0) || !(hitbox.arcWidthRad >= 0 && hitbox.arcWidthRad <= Math.PI * 2))) errors.push(`[${weapon.weaponId}] ${label}.${id} has invalid sector geometry`);
  }
}

function validateTrack(weapon, label, frameCount, track, hitboxes, forbidImpact) {
  if (!track) return;
  const byHitbox = new Map();
  for (const span of track.hitboxSpans ?? []) {
    if (!hitboxes?.[span.hitboxId]) errors.push(`[${weapon.weaponId}] ${label} references missing hitbox '${span.hitboxId}'`);
    if (!Number.isInteger(span.from) || !Number.isInteger(span.through) || span.from < 0 || span.through < span.from || span.through >= frameCount) errors.push(`[${weapon.weaponId}] ${label} has an invalid span`);
    const spans = byHitbox.get(span.hitboxId) ?? [];
    spans.push(span); byHitbox.set(span.hitboxId, spans);
  }
  for (const [id, spans] of byHitbox) {
    spans.sort((a, b) => a.from - b.from);
    for (let index = 1; index < spans.length; index += 1) if (spans[index].from <= spans[index - 1].through) errors.push(`[${weapon.weaponId}] ${label} has overlapping '${id}' spans`);
  }
  for (const event of track.events ?? []) {
    if (!Number.isInteger(event.at) || event.at < 0 || event.at >= frameCount) errors.push(`[${weapon.weaponId}] ${label} event '${event.eventId}' is outside the timeline`);
    if (forbidImpact && event.eventId === 'weapon.impact') errors.push(`[${weapon.weaponId}] ${label} retains forbidden weapon.impact`);
  }
}

function validateLayered(weapon, label, animation, allowLoop) {
  const frameCount = layeredFrameCount(weapon, label, animation);
  if (!allowLoop && animation.loop) errors.push(`[${weapon.weaponId}] ${label} must not loop`);
  for (const layer of animation.layers ?? []) {
    let previousThrough = -1;
    for (const block of [...(layer.blocks ?? [])].sort((a, b) => a.from - b.from)) {
      if (!Number.isInteger(block.from) || !Number.isInteger(block.through) || block.from < 0 || block.through < block.from || block.through >= frameCount) errors.push(`[${weapon.weaponId}] ${label}.${layer.layerId} has an invalid block`);
      if (block.from <= previousThrough) errors.push(`[${weapon.weaponId}] ${label}.${layer.layerId} has overlapping blocks`);
      previousThrough = block.through;
    }
  }
  return frameCount;
}

const weapons = files(weaponRoot).map((file) => JSON.parse(readFileSync(file, 'utf8')));
if (!weapons.length) errors.push('weapon catalog must not be empty');
for (const weapon of weapons) {
  if (ids.has(weapon.weaponId)) errors.push(`[${weapon.weaponId}] duplicate weapon ID`);
  ids.add(weapon.weaponId);
  if (![1, 2].includes(weapon.version)) errors.push(`[${weapon.weaponId}] version must be 1 or 2`);
  if (!['melee', 'ranged'].includes(weapon.category)) errors.push(`[${weapon.weaponId}] category must be melee or ranged`);
  if (!(weapon.characterActionId || weapon.animKey)) errors.push(`[${weapon.weaponId}] character action is required`);
  if (weapon.version === 1) {
    for (const animation of Object.values(weapon.animations ?? {})) if (!animation?.frames?.length) errors.push(`[${weapon.weaponId}] legacy animation needs frames`);
    const rootHitboxes = weapon.hitboxes ?? {};
    validateHitboxes(weapon, 'hitboxes', rootHitboxes);
    if (weapon.animations?.attack) validateTrack(weapon, 'attack', legacyFrameCount(weapon.animations.attack), weapon.attackTrack, rootHitboxes, false);
    continue;
  }
  for (const forbidden of ['assetId', 'visual', 'hitboxes', 'attackTrack', 'animKey']) if (forbidden in weapon) errors.push(`[${weapon.weaponId}] v2 forbids root ${forbidden}`);
  if ('impact' in (weapon.animations ?? {}) || 'attack' in (weapon.animations ?? {})) errors.push(`[${weapon.weaponId}] v2 animations may only contain idle`);
  if (weapon.onHitEffectId && !effectIds.has(weapon.onHitEffectId)) errors.push(`[${weapon.weaponId}] onHitEffectId '${weapon.onHitEffectId}' is missing`);
  validateLayered(weapon, 'idle', weapon.animations?.idle, true);
  for (const direction of ['right', 'up', 'down']) if (!weapon.directionalAttacks?.[direction]) errors.push(`[${weapon.weaponId}] missing ${direction} attack`);
  for (const [direction, attack] of Object.entries(weapon.directionalAttacks ?? {})) {
    const frameCount = validateLayered(weapon, `${direction} attack`, attack.animation, false);
    validateHitboxes(weapon, `${direction}.hitboxes`, attack.hitboxes);
    validateTrack(weapon, `${direction}.track`, frameCount, attack.attackTrack, attack.hitboxes, true);
  }
}
if (errors.length) { console.error(`weapons:check failed with ${errors.length} error(s):`); errors.forEach((error) => console.error(`  - ${error}`)); process.exit(1); }
console.log(`weapons:check OK - ${weapons.length} reusable weapon definition(s).`);
