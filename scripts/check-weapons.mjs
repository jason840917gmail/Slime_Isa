#!/usr/bin/env node
/** Validates reusable weapon definitions. */
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const weaponRoot = join(root, 'src', 'game', 'content', 'weapons');
const errors = [];
function timelineFrameCount(animation) {
  return animation?.keyframeTimes !== undefined && animation?.durationSeconds !== undefined
    ? Math.max(1, Math.round(animation.durationSeconds * animation.framesPerSecond))
    : Math.max(1, animation?.frames?.length ?? 0);
}
function files(directory) {
  const output = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) output.push(...files(path));
    else if (entry.name === 'weapon.json') output.push(path);
  }
  return output;
}
const weapons = files(weaponRoot).map((file) => JSON.parse(readFileSync(file, 'utf8')));
if (weapons.length === 0) errors.push('weapon catalog must not be empty');
const ids = new Set();
function validateAnimation(weapon, label, animation) {
  const frameCount = animation?.frames?.length ?? 0;
  const timelineFrames = timelineFrameCount(animation);
  if (frameCount < 1) errors.push(`[${weapon.weaponId}] ${label} must contain at least one tile`);
  const hasTimes = animation?.keyframeTimes !== undefined;
  const hasDuration = animation?.durationSeconds !== undefined;
  if (hasTimes !== hasDuration) errors.push(`[${weapon.weaponId}] ${label} keyframeTimes and durationSeconds must be authored together`);
  if (hasDuration && (!(animation.durationSeconds > 0) || !Number.isFinite(animation.durationSeconds))) errors.push(`[${weapon.weaponId}] ${label} durationSeconds must be positive`);
  if (hasTimes) {
    if (!Array.isArray(animation.keyframeTimes) || animation.keyframeTimes.length !== frameCount) errors.push(`[${weapon.weaponId}] ${label} keyframeTimes must match frames length`);
    for (let index = 0; index < (animation.keyframeTimes ?? []).length; index += 1) {
      const time = animation.keyframeTimes[index];
      if (!Number.isInteger(time) || time < 0 || time >= timelineFrames) errors.push(`[${weapon.weaponId}] ${label} keyframeTimes[${index}] outside timeline`);
      if (index === 0 && time !== 0) errors.push(`[${weapon.weaponId}] ${label} keyframeTimes must start at 0`);
      if (index > 0 && time <= animation.keyframeTimes[index - 1]) errors.push(`[${weapon.weaponId}] ${label} keyframeTimes must be strictly increasing`);
    }
    if (frameCount > timelineFrames) errors.push(`[${weapon.weaponId}] ${label} has more keyframes than timeline frames`);
  }
  for (const [position, transform] of Object.entries(animation?.frameTransforms ?? {})) {
    if (!/^\d+$/.test(position) || Number(position) >= frameCount) errors.push(`[${weapon.weaponId}] ${label} transform '${position}' is outside the animation`);
    for (const field of ['offset', 'scale']) {
      if (transform[field] !== undefined && (!Array.isArray(transform[field]) || transform[field].length !== 2 || transform[field].some((value) => !Number.isFinite(value)))) errors.push(`[${weapon.weaponId}] ${label} transform '${position}.${field}' must be two finite numbers`);
      if (field === 'scale' && transform[field]?.some((value) => value <= 0)) errors.push(`[${weapon.weaponId}] ${label} transform '${position}.scale' must be positive`);
    }
    if (transform.rotationDeg !== undefined && !Number.isFinite(transform.rotationDeg)) errors.push(`[${weapon.weaponId}] ${label} transform '${position}.rotationDeg' must be finite`);
  }
}
function validateTrack(weapon, label, animation, track, hitboxes) {
  if (!track) return;
  const frameCount = timelineFrameCount(animation);
  const spansByHitbox = new Map();
  for (const span of track.hitboxSpans ?? []) {
    if (!hitboxes[span.hitboxId]) errors.push(`[${weapon.weaponId}] ${label} span references missing hitbox '${span.hitboxId}'`);
    if (!Number.isInteger(span.from) || !Number.isInteger(span.through) || span.from > span.through || span.through >= frameCount) errors.push(`[${weapon.weaponId}] invalid ${label} span for '${span.hitboxId}'`);
    const spans = spansByHitbox.get(span.hitboxId) ?? [];
    spans.push(span);
    spansByHitbox.set(span.hitboxId, spans);
  }
  for (const [hitboxId, spans] of spansByHitbox) {
    spans.sort((left, right) => left.from - right.from);
    for (let index = 1; index < spans.length; index += 1) {
      if (spans[index].from <= spans[index - 1].through) errors.push(`[${weapon.weaponId}] overlapping ${label} spans for '${hitboxId}'`);
    }
  }
  for (const event of track.events ?? []) {
    if (!Number.isInteger(event.at) || event.at < 0 || event.at >= frameCount) errors.push(`[${weapon.weaponId}] ${label} event '${event.eventId}' is outside the attack clip`);
  }
}
function validateHitboxSet(weapon, label, hitboxes) {
  for (const [hitboxId, hitbox] of Object.entries(hitboxes)) {
    if (!['rectangle', 'circle', 'ellipse', 'sector'].includes(hitbox.shape)) errors.push(`[${weapon.weaponId}] ${label} hitbox '${hitboxId}' has an invalid shape`);
    if (!(hitbox.width > 0) || !(hitbox.height > 0)) errors.push(`[${weapon.weaponId}] ${label} hitbox '${hitboxId}' must have positive dimensions`);
    if (hitbox.shape === 'sector' && !(hitbox.outerRadius >= 0)) errors.push(`[${weapon.weaponId}] ${label} sector hitbox '${hitboxId}' needs an outerRadius`);
  }
}
for (const weapon of weapons) {
  if (ids.has(weapon.weaponId)) errors.push(`[${weapon.weaponId}] duplicate weapon ID`);
  ids.add(weapon.weaponId);
  if (!['melee', 'ranged'].includes(weapon.category)) errors.push(`[${weapon.weaponId}] category must be melee or ranged`);
  if (!(weapon.characterActionId || weapon.animKey)) errors.push(`[${weapon.weaponId}] characterActionId or animKey is required`);
  for (const field of ['baseDamage', 'cooldownMs', 'hitboxWidth', 'hitboxHeight', 'hitboxDurationMs', 'knockStrength']) {
    if (!(weapon[field] >= 0)) errors.push(`[${weapon.weaponId}] ${field} must be zero or greater`);
  }
  const hitboxes = weapon.hitboxes ?? {};
  for (const [animationId, animation] of Object.entries(weapon.animations ?? {})) validateAnimation(weapon, `animations.${animationId}`, animation);
  validateTrack(weapon, 'attack', weapon.animations?.attack, weapon.attackTrack, hitboxes);
  for (const direction of ['right', 'left', 'up', 'down', 'side']) {
    const attack = weapon.directionalAttacks?.[direction];
    if (!attack) continue;
    const directionHitboxes = attack.hitboxes ?? (direction === 'left' ? weapon.directionalAttacks?.right?.hitboxes : undefined) ?? hitboxes;
    validateAnimation(weapon, `directionalAttacks.${direction}.animation`, attack.animation);
    validateTrack(weapon, `${direction} attack`, attack.animation, attack.attackTrack ?? weapon.attackTrack, directionHitboxes);
    if (attack.hitboxes) validateHitboxSet(weapon, `directionalAttacks.${direction}`, attack.hitboxes);
  }
  validateHitboxSet(weapon, 'root', hitboxes);
}
if (errors.length) { console.error(`weapons:check failed with ${errors.length} error(s):`); errors.forEach((error) => console.error(`  - ${error}`)); process.exit(1); }
console.log(`weapons:check OK - ${weapons.length} reusable weapon definition(s).`);

