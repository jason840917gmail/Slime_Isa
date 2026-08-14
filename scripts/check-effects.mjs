#!/usr/bin/env node
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const effectRoot = join(root, 'src', 'game', 'content', 'effects');
const manifest = JSON.parse(readFileSync(join(root, 'asset', 'assets.json'), 'utf8'));
const boot = new Set(manifest.bundles?.boot ?? []);
const errors = [];
const ids = new Set();
const files = [];
function discover(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const target = join(directory, entry.name);
    if (entry.isDirectory()) discover(target);
    else if (entry.name === 'effect.json') files.push(target);
  }
}
discover(effectRoot);
function validateAnimation(effect, label, animation) {
  if (!animation) return;
  if (animation.loop) errors.push(`[${effect.effectId}] ${label} must not loop`);
  const timelineFrames = Math.round(animation.durationSeconds * animation.framesPerSecond);
  if (!(timelineFrames >= 1) || Math.abs(animation.durationSeconds * animation.framesPerSecond - timelineFrames) > 1e-6) errors.push(`[${effect.effectId}] ${label} duration and FPS must resolve to whole frames`);
  for (const layer of animation.layers ?? []) {
    const asset = manifest.assets?.[layer.assetId];
    if (!asset || asset.source?.kind !== 'spritesheet') errors.push(`[${effect.effectId}] ${label}.${layer.layerId} needs a spritesheet asset`);
    if (!boot.has(layer.assetId)) errors.push(`[${effect.effectId}] ${label}.${layer.layerId} asset '${layer.assetId}' is not in boot`);
    const frameCount = (asset?.source?.frame?.cols ?? 0) * (asset?.source?.frame?.rows ?? 0);
    for (const block of layer.blocks ?? []) if (block.sourceFrame < 0 || block.sourceFrame >= frameCount) errors.push(`[${effect.effectId}] ${label}.${layer.layerId} source frame ${block.sourceFrame} is outside the asset`);
  }
}
for (const file of files) {
  const effect = JSON.parse(readFileSync(file, 'utf8'));
  if (ids.has(effect.effectId)) errors.push(`[${effect.effectId}] duplicate effect ID`);
  ids.add(effect.effectId);
  validateAnimation(effect, 'default', effect.default);
  for (const [direction, animation] of Object.entries(effect.directions ?? {})) validateAnimation(effect, direction, animation);
  const resolves = (direction) => effect.directions?.[direction]
    ?? (direction === 'left' && effect.mirrorLeftFromRight ? effect.directions?.right : undefined)
    ?? (direction === 'up' && effect.mirrorUpFromDown ? effect.directions?.down : undefined)
    ?? effect.default;
  if (effect.mirrorLeftFromRight && !effect.directions?.left && !effect.directions?.right) errors.push(`[${effect.effectId}] mirrorLeftFromRight requires a Right variant when LEFT is not authored`);
  if (effect.mirrorUpFromDown && !effect.directions?.up && !effect.directions?.down) errors.push(`[${effect.effectId}] mirrorUpFromDown requires a Down variant when UP is not authored`);
  for (const direction of ['right', 'left', 'up', 'down']) if (!resolves(direction)) errors.push(`[${effect.effectId}] direction '${direction}' does not resolve`);
  if (effect.effectId !== relative(effectRoot, file).split(/[\\/]/)[0]) errors.push(`[${effect.effectId}] directory ID mismatch`);
}
if (errors.length) { console.error(`effects:check failed with ${errors.length} error(s):`); errors.forEach((error) => console.error(`  - ${error}`)); process.exit(1); }
console.log(`effects:check OK - ${files.length} reusable effect definition(s).`);
