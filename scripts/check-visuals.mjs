#!/usr/bin/env node
/** Validates every discovered version-1 visual set, including character packages. */
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const roots = [join(root, 'src', 'game', 'content', 'characters'), join(root, 'src', 'game', 'content', 'visuals')];
const manifest = JSON.parse(readFileSync(join(root, 'asset', 'assets.json'), 'utf8'));
const errors = [];
const ids = new Set();
const runtimeKeys = new Set();
const idPattern = /^[a-z0-9]+(?:[.-][a-z0-9-]+)+$/;
function timelineFrameCount(clip) {
  return clip.keyframeTimes !== undefined && clip.durationSeconds !== undefined
    ? Math.max(1, Math.round(clip.durationSeconds * clip.framesPerSecond))
    : Math.max(1, clip.frames.length);
}
function files(directory) { const output = []; for (const entry of readdirSync(directory, { withFileTypes: true })) { if (entry.name.startsWith('.') || entry.name.startsWith('.character-studio-')) continue; const path = join(directory, entry.name); if (entry.isDirectory()) output.push(...files(path)); else if (entry.name === 'visual-set.json') output.push(path); } return output; }
for (const file of roots.flatMap(files).sort()) {
  let value; try { value = JSON.parse(readFileSync(file, 'utf8')); } catch (error) { errors.push(`${file}: ${error.message}`); continue; }
  if (value.version !== 1) errors.push(`${file}: version must be 1`);
  if (!idPattern.test(value.visualSetId ?? '')) errors.push(`${file}: invalid visualSetId`);
  if (ids.has(value.visualSetId)) errors.push(`${file}: duplicate visualSetId '${value.visualSetId}'`); ids.add(value.visualSetId);
  const asset = manifest.assets[value.assetId];
  if (!asset) { errors.push(`${file}: unknown asset '${value.assetId}'`); continue; }
  const count = asset.source.kind === 'spritesheet' ? asset.source.frame.count ?? asset.source.frame.cols * asset.source.frame.rows : 1;
  for (const [clipId, clip] of Object.entries(value.clips ?? {})) {
    if (!Array.isArray(clip.frames) || clip.frames.length === 0) errors.push(`${file}: ${clipId} frames must be non-empty`);
    for (const frame of clip.frames ?? []) if (!Number.isInteger(frame) || frame < 0 || frame >= count) errors.push(`${file}: ${clipId} frame ${frame} outside 0..${count - 1}`);
    if (!Number.isFinite(clip.framesPerSecond) || clip.framesPerSecond <= 0 || clip.framesPerSecond > 240) errors.push(`${file}: ${clipId} framesPerSecond invalid`);
    const hasTimes = clip.keyframeTimes !== undefined;
    const hasDuration = clip.durationSeconds !== undefined;
    if (hasTimes !== hasDuration) errors.push(`${file}: ${clipId} keyframeTimes and durationSeconds must be authored together`);
    if (hasDuration && (!Number.isFinite(clip.durationSeconds) || clip.durationSeconds <= 0)) errors.push(`${file}: ${clipId} durationSeconds invalid`);
    if (hasTimes) {
      const timelineFrames = timelineFrameCount(clip);
      if (!Array.isArray(clip.keyframeTimes) || clip.keyframeTimes.length !== (clip.frames?.length ?? 0)) errors.push(`${file}: ${clipId} keyframeTimes must match frames length`);
      for (let index = 0; index < (clip.keyframeTimes ?? []).length; index += 1) {
        const time = clip.keyframeTimes[index];
        if (!Number.isInteger(time) || time < 0 || time >= timelineFrames) errors.push(`${file}: ${clipId} keyframeTimes[${index}] outside 0..${timelineFrames - 1}`);
        if (index === 0 && time !== 0) errors.push(`${file}: ${clipId} keyframeTimes must start at 0`);
        if (index > 0 && time <= clip.keyframeTimes[index - 1]) errors.push(`${file}: ${clipId} keyframeTimes must be strictly increasing`);
      }
      if ((clip.frames?.length ?? 0) > timelineFrames) errors.push(`${file}: ${clipId} has more keyframes than timeline frames`);
    }
    if (typeof clip.loop !== 'boolean') errors.push(`${file}: ${clipId} loop must be boolean`);
    if (clip.loopMode !== undefined && clip.loopMode !== 'wrap' && clip.loopMode !== 'ping-pong') errors.push(`${file}: ${clipId} loopMode must be 'wrap' or 'ping-pong'`);
    const runtimeKey = `visual:${value.visualSetId.length}:${value.visualSetId}:${clipId}`;
    if (runtimeKeys.has(runtimeKey)) errors.push(`${file}: duplicate runtime key '${runtimeKey}'`); runtimeKeys.add(runtimeKey);
  }
}
if (errors.length) { console.error(`visuals:check failed with ${errors.length} error(s):`); errors.forEach((error) => console.error(`  - ${error}`)); process.exit(1); }
console.log(`visuals:check OK - ${ids.size} visual set(s), ${runtimeKeys.size} unique derived runtime key(s).`);
