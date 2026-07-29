#!/usr/bin/env node
/** Validates reusable projectile profiles and their manifest references. */
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const projectileRoot = join(root, 'src', 'game', 'content', 'projectiles');
const manifest = JSON.parse(readFileSync(join(root, 'asset', 'assets.json'), 'utf8'));
const errors = [];
function files(directory) {
  const output = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) output.push(...files(path));
    else if (entry.name === 'projectile.json') output.push(path);
  }
  return output;
}
const projectiles = files(projectileRoot).map((file) => JSON.parse(readFileSync(file, 'utf8')));
if (projectiles.length === 0) errors.push('projectile catalog must not be empty');
const ids = new Set();
for (const projectile of projectiles) {
  if (ids.has(projectile.projectileId)) errors.push(`[${projectile.projectileId}] duplicate projectile ID`);
  ids.add(projectile.projectileId);
  const asset = manifest.assets[projectile.assetId];
  if (!asset || asset.status !== 'ready' || !asset.tags?.includes('projectile')) errors.push(`[${projectile.projectileId}] must reference a ready projectile-tagged asset`);
  const shape = projectile.body?.shape ?? 'rectangle';
  if (!['rectangle', 'circle', 'ellipse'].includes(shape)) errors.push(`[${projectile.projectileId}] body shape must be rectangle, circle, or ellipse`);
  if (shape === 'circle' && !(projectile.body?.radius > 0)) errors.push(`[${projectile.projectileId}] circle body radius must be positive`);
  if (shape === 'ellipse' && (!(projectile.body?.radiusX > 0) || !(projectile.body?.radiusY > 0))) errors.push(`[${projectile.projectileId}] ellipse body radii must be positive`);
  if (!(projectile.body?.width > 0) || !(projectile.body?.height > 0)) errors.push(`[${projectile.projectileId}] body dimensions must be positive`);
  if (!(projectile.movement?.defaultSpeed > 0) || !(projectile.movement?.lifetimeMs > 0)) errors.push(`[${projectile.projectileId}] movement values must be positive`);
  if (projectile.animation && (!Array.isArray(projectile.animation.frames) || projectile.animation.frames.length === 0)) errors.push(`[${projectile.projectileId}] animation frames must be non-empty`);
}
if (errors.length) { console.error(`projectiles:check failed with ${errors.length} error(s):`); errors.forEach((error) => console.error(`  - ${error}`)); process.exit(1); }
console.log(`projectiles:check OK - ${projectiles.length} reusable projectile profile(s).`);
