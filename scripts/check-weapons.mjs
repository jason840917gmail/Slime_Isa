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
  for (const field of ['baseDamage', 'cooldownMs', 'hitboxWidth', 'hitboxHeight', 'hitboxDurationMs', 'knockStrength']) {
    if (!(weapon[field] >= 0)) errors.push(`[${weapon.weaponId}] ${field} must be zero or greater`);
  }
}
if (errors.length) { console.error(`weapons:check failed with ${errors.length} error(s):`); errors.forEach((error) => console.error(`  - ${error}`)); process.exit(1); }
console.log(`weapons:check OK - ${weapons.length} reusable weapon definition(s).`);

