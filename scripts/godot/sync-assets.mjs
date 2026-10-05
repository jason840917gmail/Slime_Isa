#!/usr/bin/env node
/**
 * godot:sync — copies every file `asset/assets.json` maps into `godot/asset/`
 * at the same relative path, so the Godot project imports it as
 * `res://asset/<path>`. `asset/` stays the source of truth until the cutover
 * (docs/GODOT_MIGRATION.md); `godot/asset/` is git-ignored.
 *
 * Unchanged files (same size, copy not older than the source) are skipped.
 * `--check` copies nothing and exits 1 when a copy is missing or stale.
 * Files in `godot/asset/` that the manifest no longer maps are only reported.
 */
import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const sourceRoot = join(repoRoot, 'asset');
const targetRoot = join(repoRoot, 'godot', 'asset');
const checkOnly = process.argv.includes('--check');

const manifest = JSON.parse(readFileSync(join(sourceRoot, 'assets.json'), 'utf8'));
const mappedPaths = new Set();
for (const [assetId, asset] of Object.entries(manifest.assets)) {
  const path = asset?.source?.path;
  if (typeof path !== 'string') throw new Error(`Asset '${assetId}' has no source.path`);
  mappedPaths.add(path.split('/').join(sep));
}

let copied = 0;
let unchanged = 0;
const missingSources = [];
const outOfDate = [];
for (const path of [...mappedPaths].sort()) {
  const source = join(sourceRoot, path);
  const target = join(targetRoot, path);
  if (!existsSync(source)) {
    missingSources.push(path);
    continue;
  }
  const sourceStat = statSync(source);
  if (existsSync(target)) {
    const targetStat = statSync(target);
    if (targetStat.size === sourceStat.size && targetStat.mtimeMs >= sourceStat.mtimeMs) {
      unchanged += 1;
      continue;
    }
  }
  if (checkOnly) {
    outOfDate.push(path);
    continue;
  }
  mkdirSync(dirname(target), { recursive: true });
  copyFileSync(source, target);
  copied += 1;
}

const unmapped = [];
const walk = (directory) => {
  if (!existsSync(directory)) return;
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const full = join(directory, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (!entry.name.endsWith('.import')) {
      const path = relative(targetRoot, full);
      if (!mappedPaths.has(path)) unmapped.push(path);
    }
  }
};
walk(targetRoot);

if (missingSources.length) {
  console.error(`godot:sync — ${missingSources.length} mapped file(s) missing from asset/:\n  ${missingSources.join('\n  ')}`);
  process.exit(1);
}
if (unmapped.length) console.warn(`godot:sync — ${unmapped.length} file(s) in godot/asset are no longer mapped (left in place):\n  ${unmapped.join('\n  ')}`);
if (checkOnly) {
  if (outOfDate.length) {
    console.error(`godot:sync --check — ${outOfDate.length} copy(ies) missing or stale; run pnpm godot:sync.`);
    process.exit(1);
  }
  console.log(`godot:sync --check OK — ${unchanged} file(s) in sync.`);
} else {
  console.log(`godot:sync OK — ${copied} copied, ${unchanged} unchanged (${mappedPaths.size} mapped).`);
}
