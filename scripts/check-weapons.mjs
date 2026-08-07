#!/usr/bin/env node
/** Validates reusable weapon definitions. */
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const weaponRoot = join(root, 'src', 'game', 'content', 'weapons');
const errors = [];
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
for (const weapon of weapons) {
  if (ids.has(weapon.weaponId)) errors.push(`[${weapon.weaponId}] duplicate weapon ID`);
  ids.add(weapon.weaponId);
  if (!['melee', 'ranged'].includes(weapon.category)) errors.push(`[${weapon.weaponId}] category must be melee or ranged`);
  if (!(weapon.characterActionId || weapon.animKey)) errors.push(`[${weapon.weaponId}] characterActionId or animKey is required`);
  for (const field of ['baseDamage', 'cooldownMs', 'hitboxWidth', 'hitboxHeight', 'hitboxDurationMs', 'knockStrength']) {
    if (!(weapon[field] >= 0)) errors.push(`[${weapon.weaponId}] ${field} must be zero or greater`);
  }
  const hitboxes = weapon.hitboxes ?? {};
  if (weapon.attackTrack) {
    const frameCount = weapon.animations?.attack?.frames?.length ?? 0;
    const spansByHitbox = new Map();
    for (const span of weapon.attackTrack.hitboxSpans ?? []) {
      if (!hitboxes[span.hitboxId]) errors.push(`[${weapon.weaponId}] attack span references missing hitbox '${span.hitboxId}'`);
      if (!Number.isInteger(span.from) || !Number.isInteger(span.through) || span.from > span.through || span.through >= frameCount) errors.push(`[${weapon.weaponId}] invalid attack span for '${span.hitboxId}'`);
      const spans = spansByHitbox.get(span.hitboxId) ?? [];
      spans.push(span);
      spansByHitbox.set(span.hitboxId, spans);
    }
    for (const [hitboxId, spans] of spansByHitbox) {
      spans.sort((left, right) => left.from - right.from);
      for (let index = 1; index < spans.length; index += 1) {
        if (spans[index].from <= spans[index - 1].through) errors.push(`[${weapon.weaponId}] overlapping attack spans for '${hitboxId}'`);
      }
    }
    for (const event of weapon.attackTrack.events ?? []) {
      if (!Number.isInteger(event.at) || event.at < 0 || event.at >= frameCount) errors.push(`[${weapon.weaponId}] attack event '${event.eventId}' is outside the attack clip`);
    }
  }
  for (const [hitboxId, hitbox] of Object.entries(hitboxes)) {
    if (!['rectangle', 'circle', 'ellipse', 'sector'].includes(hitbox.shape)) errors.push(`[${weapon.weaponId}] hitbox '${hitboxId}' has an invalid shape`);
    if (!(hitbox.width > 0) || !(hitbox.height > 0)) errors.push(`[${weapon.weaponId}] hitbox '${hitboxId}' must have positive dimensions`);
    if (hitbox.shape === 'sector' && !(hitbox.outerRadius >= 0)) errors.push(`[${weapon.weaponId}] sector hitbox '${hitboxId}' needs an outerRadius`);
  }
}
if (errors.length) { console.error(`weapons:check failed with ${errors.length} error(s):`); errors.forEach((error) => console.error(`  - ${error}`)); process.exit(1); }
console.log(`weapons:check OK - ${weapons.length} reusable weapon definition(s).`);

