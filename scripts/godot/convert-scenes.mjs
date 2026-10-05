#!/usr/bin/env node
/**
 * godot:convert — exports the game data the Godot project still reads from the Phaser content
 * into `godot/generated/data/` (git-ignored; docs/GODOT_MIGRATION.md):
 *
 *   data/*.json   game constants, enemy types, items, collision layers (copies), NPC definitions,
 *                 recipes and quests (exported from TS content modules), weapons.json and
 *                 item-icons.json (built from the weapon definitions and asset/assets.json)
 *
 * Until Phase 1 of the migration (2026-10-05) it also converted every scene JSON into
 * `generated/scenes/`; those scenes are now Godot's own in `godot/game/scenes/` (scene JSON is
 * frozen), so this only exports data and removes anything else it finds under `generated/`.
 *
 * Deterministic: the same inputs give byte-identical files, and unchanged
 * files are not rewritten (no needless Godot re-imports).
 * `--check` writes nothing and exits 1 when the generated output is stale.
 */
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import {
  DATA_COPIES, GENERATED_ROOT, loadAssetManifest, readDataCopy, readTsDataExports, readWeaponCatalog, buildItemIcons,
} from './lib/inputs.mjs';

const checkOnly = process.argv.includes('--check');
/** Data exported from TS content modules (`TS_DATA_EXPORTS`), loaded once before `generate`. */
const TS_DATA = await readTsDataExports();

const json = (value) => `${JSON.stringify(value, null, 2)}\n`;

/** Every output file: generated-relative posix path → text. */
function generate() {
  const outputs = new Map();
  for (const [source, target] of DATA_COPIES) outputs.set(`data/${target}`, readDataCopy(source));
  for (const [target, text] of TS_DATA) outputs.set(`data/${target}`, text);
  const weapons = readWeaponCatalog();
  outputs.set('data/weapons.json', json(weapons));
  outputs.set('data/item-icons.json', json(buildItemIcons(JSON.parse(readDataCopy('items/items.json')), weapons, loadAssetManifest())));
  return outputs;
}

const toPosix = (path) => path.split(sep).join('/');

/** Files on disk under `generated/` (the converter owns the folder; it never touches others). */
function existingOutputs() {
  const found = [];
  const walk = (directory) => {
    if (!existsSync(directory)) return;
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const full = join(directory, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (/\.(tscn|tres|json)$/.test(entry.name)) found.push(toPosix(relative(GENERATED_ROOT, full)));
    }
  };
  walk(GENERATED_ROOT);
  return found;
}

/** Removes directories left empty under `generated/` (the old scenes/ and resources/ trees). */
function removeEmptyDirectories(directory) {
  if (!existsSync(directory)) return;
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.isDirectory()) removeEmptyDirectories(join(directory, entry.name));
  }
  if (directory !== GENERATED_ROOT && readdirSync(directory).length === 0) rmSync(directory, { recursive: true });
}

function main() {
  const started = Date.now();
  const outputs = generate();
  const changed = [];
  for (const [path, text] of outputs) {
    const full = join(GENERATED_ROOT, path);
    if (existsSync(full) && readFileSync(full, 'utf8') === text) continue;
    changed.push(path);
    if (!checkOnly) {
      mkdirSync(dirname(full), { recursive: true });
      writeFileSync(full, text);
    }
  }
  const stale = existingOutputs().filter((path) => !outputs.has(path));
  if (checkOnly) {
    if (changed.length || stale.length) {
      console.error(`godot:convert --check — ${changed.length} file(s) stale or missing, ${stale.length} obsolete; run pnpm godot:convert.`);
      for (const path of [...changed, ...stale].slice(0, 20)) console.error(`  ${path}`);
      process.exit(1);
    }
    console.log(`godot:convert --check OK — ${outputs.size} file(s) up to date.`);
    return;
  }
  for (const path of stale) rmSync(join(GENERATED_ROOT, path));
  if (stale.length) removeEmptyDirectories(GENERATED_ROOT);
  console.log(`godot:convert — ${outputs.size} data file(s); ${changed.length} written, ${stale.length} removed (${Date.now() - started} ms).`);
}

main();
