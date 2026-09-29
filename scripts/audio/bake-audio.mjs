#!/usr/bin/env node
/**
 * audio:bake — renders the synthesized SFX catalog and syncs the manifest.
 *
 *   node scripts/audio/bake-audio.mjs [--library <dir-with-unpacked-kenney-packs>] [--report]
 *
 * 1. Renders every cue take in scripts/audio/cues.mjs to
 *    asset/audio/sfx/synth/<category>/<cue>[-<n>].wav (deterministic).
 * 2. With --library, copies the cue's CC0 library files (Kenney, OpenGameArt; see
 *    asset/audio/CREDITS.md) into asset/audio/sfx/library/<category>/<cue>[-<n>].ogg|wav.
 *    Without it, existing library files are kept as-is.
 * 3. Rewrites the generated `audio.sfx.*` block of asset/assets.json and the
 *    `audio` bundle. Library files become `source.alternates.library`.
 *
 * Asset IDs: audio.sfx.<category>.<cue>.<n> (n starts at 1).
 */

import { copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { basename, dirname, extname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import { CUES, variantPitch } from './cues.mjs';
import { describe, encodeWav, hashSeed, renderRecipe } from './synth.mjs';

const repoRoot = fileURLToPath(new URL('../..', import.meta.url));
const assetRoot = join(repoRoot, 'asset');
const manifestPath = join(assetRoot, 'assets.json');
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
  rmSync(libraryRoot, { recursive: true, force: true });
}
rmSync(synthRoot, { recursive: true, force: true });

const entries = [];
const rows = [];
let synthBytes = 0;
for (const [category, cues] of Object.entries(CUES)) {
  for (const [cue, definition] of Object.entries(cues)) {
    const variants = definition.variants ?? 1;
    for (let variant = 0; variant < variants; variant += 1) {
      const suffix = variants > 1 ? `-${variant + 1}` : '';
      const stem = `${cue}${suffix}`;
      const synthPath = `audio/sfx/synth/${category}/${stem}.wav`;
      const samples = renderRecipe(definition.synth(variantPitch(variant), variant), hashSeed(`${category}/${stem}`));
      const wav = encodeWav(samples);
      synthBytes += wav.length;
      mkdirSync(join(assetRoot, dirname(synthPath)), { recursive: true });
      writeFileSync(join(assetRoot, synthPath), wav);
      rows.push({ id: `${category}/${stem}`, ...describe(samples) });

      if (libraryPackDir && definition.library?.length) {
        const sourceName = definition.library[variant % definition.library.length];
        if (ambiguousNames.has(sourceName)) throw new Error(`Library file '${sourceName}' for ${category}/${cue} exists in several packs; use '<pack>/${sourceName}'`);
        const source = libraryIndex.get(sourceName);
        if (!source) throw new Error(`Library file '${sourceName}' for ${category}/${cue} not found under ${libraryPackDir}`);
        const target = join(assetRoot, `audio/sfx/library/${category}/${stem}${extname(source).toLowerCase()}`);
        mkdirSync(dirname(target), { recursive: true });
        copyFileSync(source, target);
      }
      const libraryPath = LIBRARY_EXTENSIONS.map((extension) => `audio/sfx/library/${category}/${stem}${extension}`)
        .find((candidate) => existsSync(join(assetRoot, candidate)));
      const hasLibrary = libraryPath !== undefined;

      entries.push({
        id: `audio.sfx.${category}.${cue}.${variant + 1}`,
        textureKey: `sfx-${category}-${cue}-${variant + 1}`,
        path: synthPath,
        library: hasLibrary ? libraryPath : undefined,
        category,
      });
    }
  }
}

// ── Manifest sync (text splice keeps the hand-formatted manifest intact) ────

const raw = readFileSync(manifestPath, 'utf8');
const crlf = raw.includes('\r\n');
let text = raw.replace(/\r\n/g, '\n');

/** Removes the generated `audio` bundle and every `audio.sfx.*` entry, leaving hand-authored entries (music) alone. */
function removeGenerated(source) {
  let result = source.replace(/,\n {4}"audio": \[[\s\S]*?\n {4}\]/, '');
  const entryStart = /\n {4}"([^"]+)": \{/g;
  const generated = [];
  for (let match = entryStart.exec(result); match; match = entryStart.exec(result)) {
    if (!match[1].startsWith('audio.sfx.')) continue;
    const end = result.indexOf('\n    }', match.index) + '\n    }'.length;
    const comma = result.lastIndexOf(',', match.index);
    generated.push([comma, end]);
  }
  for (const [start, end] of generated.reverse()) result = result.slice(0, start) + result.slice(end);
  return result;
}

function sectionClose(source, key) {
  const start = source.indexOf(`\n  "${key}": {`);
  if (start < 0) throw new Error(`assets.json has no top-level "${key}" object`);
  return source.indexOf('\n  }', start);
}

text = removeGenerated(text);
const entryText = entries.map((entry) => {
  const alternates = entry.library ? `,\n        "alternates": { "library": "${entry.library}" }` : '';
  return `    "${entry.id}": {\n      "source": {\n        "kind": "audio",\n        "path": "${entry.path}"${alternates}\n      },\n      "runtime": { "textureKey": "${entry.textureKey}" },\n      "tags": ["audio", "sfx", "${entry.category}"],\n      "status": "draft",\n      "notes": "Generated by pnpm audio:bake (scripts/audio/cues.mjs)."\n    }`;
}).join(',\n');
const assetsClose = sectionClose(text, 'assets');
text = `${text.slice(0, assetsClose)},\n${entryText}${text.slice(assetsClose)}`;
const bundleText = `    "audio": [\n${entries.map((entry) => `      "${entry.id}"`).join(',\n')}\n    ]`;
const bundlesClose = sectionClose(text, 'bundles');
text = `${text.slice(0, bundlesClose)},\n${bundleText}${text.slice(bundlesClose)}`;
JSON.parse(text);
writeFileSync(manifestPath, crlf ? text.replace(/\n/g, '\r\n') : text);

const libraryCount = entries.filter((entry) => entry.library).length;
const libraryBytes = existsSync(libraryRoot) ? listFiles(libraryRoot).reduce((sum, file) => sum + statSync(file).size, 0) : 0;
if (report) console.table(rows);
console.log(`audio:bake OK — ${entries.length} takes (${(synthBytes / 1024).toFixed(0)} KiB synth WAV), ${libraryCount} with library alternates (${(libraryBytes / 1024).toFixed(0)} KiB library audio).`);
