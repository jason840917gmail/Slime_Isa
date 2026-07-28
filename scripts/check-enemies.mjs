#!/usr/bin/env node
/** Validates enemy package gameplay and manifest references. */
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const characterRoot = join(root, 'src', 'game', 'content', 'characters');
const manifest = JSON.parse(readFileSync(join(root, 'asset', 'assets.json'), 'utf8'));
const errors = [];
function files(directory) { const output = []; for (const entry of readdirSync(directory, { withFileTypes: true })) { if (entry.name.startsWith('.')) continue; const path = join(directory, entry.name); if (entry.isDirectory()) output.push(...files(path)); else if (entry.name === 'character.json') output.push(path); } return output; }
const enemies = files(characterRoot).map((file) => JSON.parse(readFileSync(file, 'utf8'))).filter((value) => value.kind === 'enemy');
if (enemies.length === 0) errors.push('enemy package catalog must not be empty');
for (const enemy of enemies) {
  if (enemy.characterId !== enemy.characterId.toLowerCase()) errors.push(`[${enemy.characterId}] ID must be lowercase`);
  const asset = manifest.assets[enemy.enemy?.projectile?.assetId];
  if (enemy.enemy?.ai?.isRanged && (!asset || asset.status !== 'ready' || asset.source?.kind !== 'image')) errors.push(`[${enemy.characterId}] ranged enemy requires a ready image projectile`);
  if (enemy.enemy?.impactEffect && !enemy.enemy.impactEffect.clipId) errors.push(`[${enemy.characterId}] impact effect requires a clip`);
  if (!(enemy.enemy?.ai?.attackCooldownMs >= 0)) errors.push(`[${enemy.characterId}] attack cooldown must be non-negative`);
}
if (errors.length) { console.error(`enemies:check failed with ${errors.length} error(s):`); errors.forEach((error) => console.error(`  - ${error}`)); process.exit(1); }
console.log(`enemies:check OK - ${enemies.length} complete enemy package(s).`);
