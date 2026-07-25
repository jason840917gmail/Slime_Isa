#!/usr/bin/env node
/** Validates the active enemy catalog and its visual/media contracts. */

import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const catalog = JSON.parse(readFileSync(join(root, 'src/game/content/enemies/enemy-types.json'), 'utf8'));
const manifest = JSON.parse(readFileSync(join(root, 'asset/assets.json'), 'utf8'));
const visualRoot = join(root, 'src/game/content/visuals');
const requiredClips = [
  'idle-side', 'idle-up', 'idle-down',
  'walk-side', 'walk-up', 'walk-down',
  'attack-side', 'attack-up', 'attack-down',
  'knockback-side', 'knockback-up', 'knockback-down',
  'die-side', 'die-up', 'die-down',
];
const errors = [];

function collectVisuals(directory, output = new Map()) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) collectVisuals(path, output);
    if (entry.isFile() && entry.name === 'visual-set.json') {
      const visual = JSON.parse(readFileSync(path, 'utf8'));
      output.set(visual.visualSetId, visual);
    }
  }
  return output;
}

const visuals = collectVisuals(visualRoot);
const types = catalog.types ?? {};
const ids = Object.keys(types).sort();
if (ids.length === 0) errors.push('active enemy catalog must not be empty');

for (const [id, config] of Object.entries(types)) {
  if (config.id !== id) errors.push(`[${id}] id must match its catalog key`);
  const visual = visuals.get(config.visualSetId);
  if (!visual) {
    errors.push(`[${id}] unknown visualSetId '${config.visualSetId}'`);
    continue;
  }
  const asset = manifest.assets[visual.assetId];
  if (!asset || asset.status !== 'ready' || asset.source?.kind !== 'spritesheet') {
    errors.push(`[${id}] visual must reference a ready spritesheet asset`);
  }
  for (const clip of requiredClips) {
    if (!visual.clips?.[clip]) errors.push(`[${id}] missing required clip '${clip}'`);
  }
  for (const field of ['attackCooldownMs', 'attackWindupMs', 'attackRecoveryMs']) {
    if (!(config.ai?.[field] > 0)) errors.push(`[${id}] ai.${field} must be > 0`);
  }
  for (const field of ['contactDamage', 'knockbackStrength']) {
    if (!(config.ai?.[field] > 0)) errors.push(`[${id}] ai.${field} must be > 0`);
  }
  if (config.ai?.isRanged) {
    const projectile = manifest.assets[config.projectile?.assetId];
    if (!projectile || projectile.status !== 'ready' || projectile.source?.kind !== 'image') {
      errors.push(`[${id}] ranged enemy requires a ready image projectile`);
    }
  }
  if (config.impactEffect) {
    const effect = visuals.get(config.impactEffect.visualSetId);
    if (!effect?.clips?.[config.impactEffect.clipId]) {
      errors.push(`[${id}] invalid impact effect visual/clip`);
    }
  }
}

if (errors.length) {
  console.error(`enemies:check failed with ${errors.length} error(s):`);
  errors.forEach((error) => console.error(`  - ${error}`));
  process.exit(1);
}
console.log(`enemies:check OK - ${ids.length} complete active enemy type(s).`);
