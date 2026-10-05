#!/usr/bin/env node
/**
 * godot:convert — converts every authored scene JSON
 * (`src/game/content/scenes/authored/**\/*.scene.json`) into Godot 4 text
 * scenes under `godot/generated/` (git-ignored; docs/GODOT_MIGRATION.md):
 *
 *   scenes/<path>.tscn               one per scene, same folder layout
 *   resources/terrain_tileset.tres   the `terrain.tiles` TileSet
 *   resources/ui_theme.tres          a minimal Theme from `ui.field-kit.theme`
 *   scene_index.json                 { sceneId: res:// path }
 *   data/*.json                      game constants, enemy types, items, layers, and data
 *                                    exported from TS content modules (NPC definitions)
 *   conversion_report.json           dropped properties, unported scripts, warnings
 *
 * Scene JSON stays the source of truth until Phase 1 ends: fix content there
 * and re-run; never hand-edit the output. Scripts under `godot/game/scripts/`
 * are read for their `@export`s, so re-run after porting a script.
 *
 * Deterministic: the same inputs give byte-identical files, and unchanged
 * files are not rewritten (no needless Godot re-imports).
 * `--check` writes nothing and exits 1 when the generated output is stale.
 */
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import {
  DATA_COPIES, GENERATED_ROOT, GODOT_ROOT, loadAssetManifest, loadCollisionLayers, loadScenes,
  loadSharedResources, readDataCopy, readTsDataExports, readWeaponCatalog, buildItemIcons, sceneResPath,
} from './lib/inputs.mjs';
import { AssetCatalog } from './lib/assets.mjs';
import { ScriptIndex, scriptResPath } from './lib/gdscript.mjs';
import { SceneModel } from './lib/scene-model.mjs';
import { ConversionReport } from './lib/report.mjs';
import { convertScene } from './lib/scene.mjs';
import { buildTileSet } from './lib/tiles.mjs';
import { buildUiTheme } from './lib/controls.mjs';
import { godotType } from './lib/nodes.mjs';
import { scriptIdOf } from './lib/script-props.mjs';
import { writeTres } from './lib/tscn.mjs';

const checkOnly = process.argv.includes('--check');
/** Data exported from TS content modules (`TS_DATA_EXPORTS`), loaded once before `generate`. */
const TS_DATA = await readTsDataExports();

/** Everything a scene conversion may look up, shared across scenes. */
function createProject() {
  const sceneEntries = loadScenes();
  const sharedResources = loadSharedResources();
  const assets = new AssetCatalog(loadAssetManifest());
  const scripts = new ScriptIndex(GODOT_ROOT);
  const models = new Map();
  const project = {
    sceneEntries,
    sharedResources,
    assets,
    scripts,
    collisionLayerBits: new Map(loadCollisionLayers().layers.map(({ layer, name }) => [name, 2 ** (layer - 1)])),
    themeValues: sharedResources.get('ui.field-kit.theme')?.values ?? {},
    tileSetResource: sharedResources.get('terrain.tiles'),
    tileSources: new Map(),
    signalsBySource: new Map(),
    sceneModel(sceneId) {
      if (!models.has(sceneId)) {
        const entry = sceneEntries.get(sceneId);
        if (!entry) throw new Error(`Unknown scene '${sceneId}'`);
        models.set(sceneId, new SceneModel(entry, project));
      }
      return models.get(sceneId);
    },
    scriptPath: scriptResPath,
    godotTypeOf: godotType,
  };
  collectConnectedSignals(project);
  return project;
}

/**
 * Signals each script id emits through some connection, anywhere. Unported
 * scripts register them as user signals so every connection loads.
 */
function collectConnectedSignals(project) {
  for (const sceneId of project.sceneEntries.keys()) {
    const scene = project.sceneModel(sceneId);
    for (const connection of scene.doc.connections ?? []) {
      let source;
      try {
        source = scene.resolveReference(connection.source);
      } catch {
        continue;
      }
      if (source.node.type !== 'ScriptNode') continue;
      const scriptId = scriptIdOf(source.node);
      if (!project.signalsBySource.has(scriptId)) project.signalsBySource.set(scriptId, new Set());
      project.signalsBySource.get(scriptId).add(connection.signal);
    }
  }
}

/**
 * Nodes Godot should build when a scene is instantiated: its authored and
 * generated nodes plus every instanced scene's tree (an instance root
 * replaces the instance placeholder).
 */
function expectedTreeSizes(project, generatedNodes) {
  const memo = new Map();
  const size = (sceneId) => {
    if (memo.has(sceneId)) return memo.get(sceneId);
    const scene = project.sceneModel(sceneId);
    let total = scene.doc.nodes.length + (generatedNodes.get(sceneId) ?? 0);
    for (const instance of scene.instances.values()) total += size(instance.sceneId);
    memo.set(sceneId, total);
    return total;
  };
  return size;
}

const json = (value) => `${JSON.stringify(value, null, 2)}\n`;

/** Every output file: generated-relative posix path → text. */
function generate() {
  const project = createProject();
  const report = new ConversionReport();
  const outputs = new Map();
  if (!project.tileSetResource) throw new Error("Shared resource 'terrain.tiles' is missing");
  const tileSet = buildTileSet(project.tileSetResource, project.assets, report);
  project.tileSources = tileSet.sources;
  outputs.set('resources/terrain_tileset.tres', tileSet.text);
  outputs.set('resources/ui_theme.tres', writeTres('Theme', buildUiTheme(project.sharedResources.get('ui.field-kit.theme'))));
  const index = {};
  const generatedNodes = new Map();
  const reports = new Map();
  for (const [sceneId, entry] of [...project.sceneEntries].sort(([, a], [, b]) => a.file.localeCompare(b.file))) {
    const scene = project.sceneModel(sceneId);
    const sceneReport = report.scene(sceneId, entry.file);
    reports.set(sceneId, sceneReport);
    try {
      const converted = convertScene(project, scene, sceneReport);
      outputs.set(`scenes/${entry.file.replace(/\.scene\.json$/, '.tscn')}`, converted.text);
      generatedNodes.set(sceneId, converted.generatedNodes);
      index[sceneId] = sceneResPath(entry.file);
    } catch (error) {
      sceneReport.warn('scene-failed', `${entry.file}: ${error.stack ?? error.message}`);
    }
  }
  const treeSize = expectedTreeSizes(project, generatedNodes);
  for (const [sceneId, sceneReport] of reports) sceneReport.setExpectedTreeNodes(treeSize(sceneId));
  outputs.set('scene_index.json', json(Object.fromEntries(Object.entries(index).sort(([a], [b]) => a.localeCompare(b)))));
  for (const [source, target] of DATA_COPIES) outputs.set(`data/${target}`, readDataCopy(source));
  for (const [target, text] of TS_DATA) outputs.set(`data/${target}`, text);
  const weapons = readWeaponCatalog();
  outputs.set('data/weapons.json', json(weapons));
  outputs.set('data/item-icons.json', json(buildItemIcons(JSON.parse(readDataCopy('items/items.json')), weapons, loadAssetManifest())));
  outputs.set('conversion_report.json', json(report.toJSON()));
  return { outputs, report: report.toJSON() };
}

const toPosix = (path) => path.split(sep).join('/');

/** Generated files on disk that the converter owns (it never touches others). */
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

function main() {
  const started = Date.now();
  const { outputs, report } = generate();
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
  if (!checkOnly) for (const path of stale) rmSync(join(GENERATED_ROOT, path));
  const summary = report.summary;
  const failed = summary.warningsByKind['scene-failed'] ?? 0;
  const warnings = Object.entries(summary.warningsByKind).map(([kind, count]) => `${kind} ${count}`).join(', ') || 'none';
  if (checkOnly) {
    if (changed.length || stale.length) {
      console.error(`godot:convert --check — ${changed.length} file(s) stale or missing, ${stale.length} obsolete; run pnpm godot:convert.`);
      for (const path of [...changed, ...stale].slice(0, 20)) console.error(`  ${path}`);
      process.exit(1);
    }
    console.log(`godot:convert --check OK — ${outputs.size} file(s) up to date.`);
    return;
  }
  console.log(`godot:convert — ${summary.scenes} scenes, ${summary.nodes} nodes, ${summary.instances} instances, ${summary.connections} connections; ${changed.length} file(s) written, ${stale.length} removed (${Date.now() - started} ms).`);
  console.log(`  warnings: ${warnings}`);
  if (failed) {
    console.error(`godot:convert — ${failed} scene(s) failed; see generated/conversion_report.json.`);
    process.exit(1);
  }
}

main();
