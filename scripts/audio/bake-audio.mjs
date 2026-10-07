#!/usr/bin/env node
/**
 * audio:bake — renders the synthesized SFX catalog into the Godot project.
 *
 *   node scripts/audio/bake-audio.mjs [--library <dir-with-unpacked-kenney-packs>] [--report]
 *
 * Each cue ships one flavour, picked by the owner (scripts/audio/picks.json,
 * roadmap 3.8): `synth` or `library`.
 *
 * 1. Renders the synth-picked cues' takes from scripts/audio/cues.mjs to
 *    godot/asset/audio/sfx/synth/<category>/<cue>[-<n>].wav (deterministic).
 * 2. With --library, copies the library-picked cues' files (Kenney, OpenGameArt,
 *    Magnific; see godot/asset/audio/CREDITS.md) into
 *    godot/asset/audio/sfx/library/<category>/<cue>[-<n>].ogg|wav. Without it, existing
 *    library files are kept as-is.
 * 3. Removes takes it no longer produces (and their Godot `.import` files); a take it
 *    rewrites keeps its `.import` file, so Godot keeps its uid.
 *
 * Godot scenes reference the takes by path (res://asset/audio/sfx/...), so a cue's
 * file name must not change. Until the Godot cutover (2026-10-05) this also wrote the
 * `audio.sfx.*` entries of asset/assets.json.
 */

import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { basename, dirname, extname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import { CUES, variantPitch } from './cues.mjs';

/** Owner's flavour per cue ("synth" | "library"); cues missing from it ship their library take when one exists. */
const PICKS = JSON.parse(readFileSync(new URL('./picks.json', import.meta.url), 'utf8')).cues;
import { describe, encodeWav, hashSeed, renderRecipe } from './synth.mjs';

const repoRoot = fileURLToPath(new URL('../..', import.meta.url));
const assetRoot = join(repoRoot, 'godot', 'asset');
const synthRoot = join(assetRoot, 'audio', 'sfx', 'synth');
const libraryRoot = join(assetRoot, 'audio', 'sfx', 'library');

const args = process.argv.slice(2);
const libraryPackDir = args.includes('--library') ? args[args.indexOf('--library') + 1] : undefined;
const report = args.includes('--report');

function listFiles(dir) {
  const files = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) files.push(...listFiles(full));
    else files.push(full);
  }
  return files;
}

/**
 * Library files are referenced by bare file name (`chop`) or, when the name exists in
 * more than one pack, by `<pack-folder>/<name>` (`rubberduck-slime/slime_01`).
 */
const LIBRARY_EXTENSIONS = ['.ogg', '.wav'];
const libraryIndex = new Map();
const ambiguousNames = new Set();
if (libraryPackDir) {
  for (const file of listFiles(libraryPackDir)) {
    const extension = extname(file).toLowerCase();
    if (!LIBRARY_EXTENSIONS.includes(extension) || basename(file).startsWith('._')) continue;
    const name = basename(file, extname(file));
    const pack = relative(libraryPackDir, file).split(sep)[0];
    libraryIndex.set(`${pack}/${name}`, file);
    if (libraryIndex.has(name) && libraryIndex.get(name) !== file) ambiguousNames.add(name);
    else libraryIndex.set(name, file);
  }
}
/** Every take this run writes or keeps (absolute paths); anything else under the roots is stale. */
const kept = new Set();

const entries = [];
const rows = [];
let synthBytes = 0;
for (const [category, cues] of Object.entries(CUES)) {
  for (const [cue, definition] of Object.entries(cues)) {
    const variants = definition.variants ?? 1;
    const pick = PICKS[`${category}.${cue}`] ?? (definition.library?.length ? 'library' : 'synth');
    if (pick === 'library' && !definition.library?.length) throw new Error(`${category}/${cue} is picked as library but lists no library take`);
    for (let variant = 0; variant < variants; variant += 1) {
      const suffix = variants > 1 ? `-${variant + 1}` : '';
      const stem = `${cue}${suffix}`;
      const synthPath = `audio/sfx/synth/${category}/${stem}.wav`;
      if (pick === 'synth') {
        const samples = renderRecipe(definition.synth(variantPitch(variant), variant), hashSeed(`${category}/${stem}`));
        const wav = encodeWav(samples);
        synthBytes += wav.length;
        mkdirSync(join(assetRoot, dirname(synthPath)), { recursive: true });
        writeFileSync(join(assetRoot, synthPath), wav);
        kept.add(join(assetRoot, synthPath));
        rows.push({ id: `${category}/${stem}`, ...describe(samples) });
      }

      if (pick === 'library' && libraryPackDir) {
        const sourceName = definition.library[variant % definition.library.length];
        if (ambiguousNames.has(sourceName)) throw new Error(`Library file '${sourceName}' for ${category}/${cue} exists in several packs; use '<pack>/${sourceName}'`);
        const source = libraryIndex.get(sourceName);
        if (!source) throw new Error(`Library file '${sourceName}' for ${category}/${cue} not found under ${libraryPackDir}`);
        const target = join(assetRoot, `audio/sfx/library/${category}/${stem}${extname(source).toLowerCase()}`);
        mkdirSync(dirname(target), { recursive: true });
        copyFileSync(source, target);
      }
      const libraryPath = pick === 'library'
        ? LIBRARY_EXTENSIONS.map((extension) => `audio/sfx/library/${category}/${stem}${extension}`).find((candidate) => existsSync(join(assetRoot, candidate)))
        : undefined;
      if (pick === 'library' && !libraryPath) throw new Error(`${category}/${stem}: the picked library take is missing (run with --library)`);
      if (libraryPath) kept.add(join(assetRoot, libraryPath));

      entries.push({
        id: `audio.sfx.${category}.${cue}.${variant + 1}`,
        textureKey: `sfx-${category}-${cue}-${variant + 1}`,
        path: libraryPath ?? synthPath,
        library: libraryPath !== undefined,
        category,
      });
    }
  }
}

// ── Stale takes: remove what this run no longer produces, with its Godot .import ────

/** Removes the files under `root` that are not in `kept` (and orphaned `.import` files). */
function pruneStale(root) {
  if (!existsSync(root)) return;
  for (const file of listFiles(root)) {
    const take = file.endsWith('.import') ? file.slice(0, -'.import'.length) : file;
    if (kept.has(take)) continue;
    rmSync(file, { force: true });
  }
}
pruneStale(synthRoot);
if (libraryPackDir) pruneStale(libraryRoot);

const libraryCount = entries.filter((entry) => entry.library).length;
const libraryBytes = existsSync(libraryRoot) ? listFiles(libraryRoot).reduce((sum, file) => sum + statSync(file).size, 0) : 0;
if (report) console.table(rows);
console.log(`audio:bake OK — ${entries.length} takes: ${entries.length - libraryCount} synth (${(synthBytes / 1024).toFixed(0)} KiB WAV), ${libraryCount} library (${(libraryBytes / 1024).toFixed(0)} KiB).`);
