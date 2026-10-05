/**
 * Conversion inputs: repository paths, every authored scene document, the
 * shared scene resources and `asset/assets.json`. Read-only; nothing here
 * writes to `src/` or `asset/`.
 */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
export const AUTHORED_ROOT = join(REPO_ROOT, 'src', 'game', 'content', 'scenes', 'authored');
export const CONTENT_ROOT = join(REPO_ROOT, 'src', 'game', 'content');
export const GODOT_ROOT = join(REPO_ROOT, 'godot');
export const GENERATED_ROOT = join(GODOT_ROOT, 'generated');

/** Folders under the authored root that hold no scenes the game loads. */
const SKIPPED_FOLDERS = new Set(['reports', '.scene-studio-transactions', 'resources']);

const toPosix = (path) => path.split(sep).join('/');

const readJson = (path) => JSON.parse(readFileSync(path, 'utf8'));

function walkFiles(directory, accept, found = []) {
  for (const entry of readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const full = join(directory, entry.name);
    if (entry.isDirectory()) walkFiles(full, accept, found);
    else if (accept(entry.name)) found.push(full);
  }
  return found;
}

/** `objects/foo.scene.json` → `res://generated/scenes/objects/foo.tscn`. */
export function sceneResPath(file) {
  return `res://generated/scenes/${file.replace(/\.scene\.json$/, '.tscn')}`;
}

/**
 * Every authored scene, keyed by sceneId, in path order:
 * { sceneId, file (posix path under the authored root), doc }.
 */
export function loadScenes() {
  const scenes = new Map();
  for (const entry of readdirSync(AUTHORED_ROOT, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    if (!entry.isDirectory() || SKIPPED_FOLDERS.has(entry.name)) continue;
    for (const path of walkFiles(join(AUTHORED_ROOT, entry.name), (name) => name.endsWith('.scene.json'))) {
      const doc = readJson(path);
      const file = toPosix(relative(AUTHORED_ROOT, path));
      if (scenes.has(doc.sceneId)) throw new Error(`Duplicate sceneId '${doc.sceneId}' in ${file} and ${scenes.get(doc.sceneId).file}`);
      scenes.set(doc.sceneId, { sceneId: doc.sceneId, file, doc });
    }
  }
  return scenes;
}

/** External scene resources (`*.resource.json`), keyed by resourceId. */
export function loadSharedResources() {
  const resources = new Map();
  for (const path of walkFiles(join(AUTHORED_ROOT, 'resources'), (name) => name.endsWith('.resource.json'))) {
    const doc = readJson(path);
    resources.set(doc.resourceId, doc);
  }
  return resources;
}

export function loadAssetManifest() {
  return readJson(join(REPO_ROOT, 'asset', 'assets.json'));
}

/** Data files copied verbatim into `generated/data/` (source → target name). */
export const DATA_COPIES = [
  ['game-constants.json', 'game-constants.json'],
  ['enemies/enemy-types.json', 'enemy-types.json'],
  ['items/items.json', 'items.json'],
  ['physics/collision-layers.json', 'collision-layers.json'],
];

export function readDataCopy(source) {
  const path = join(CONTENT_ROOT, source);
  if (!existsSync(path)) throw new Error(`Data file '${source}' is missing under src/game/content`);
  return readFileSync(path, 'utf8');
}

/**
 * Data the port reads from TypeScript content modules: [module under src/game/content, exported
 * constant, target name in `generated/data/`]. Only modules with no runtime imports (`import type`
 * is erased): Node 24 strips their types on import.
 */
export const TS_DATA_EXPORTS = [
  ['npcs/NpcDefinitions.ts', 'NPC_DEFINITIONS', 'npc-definitions.json'],
  ['recipes/RecipeCatalog.ts', 'RECIPE_CATALOG', 'recipes.json'],
  ['quests/quests/chapterOne.ts', 'CHAPTER_ONE_QUESTS', 'quests-chapter-1.json'],
  ['quests/quests/chapterTwo.ts', 'CHAPTER_TWO_QUESTS', 'quests-chapter-2.json'],
];

/** The `weapon.json` fields the port reads outside the weapon scenes (names, icons, stat lines). */
const WEAPON_CATALOG_FIELDS = ['weaponId', 'displayName', 'description', 'category', 'iconKey', 'iconFrame',
  'baseDamage', 'cooldownMs', 'harvestCapabilities'];

/**
 * `data/weapons.json`: every weapon in the definition order of `virtual-weapon-content.ts` (its
 * `import … from './<dir>/weapon.json'` lines; that module imports JSON without import attributes,
 * so it cannot be a TS export).
 */
export function readWeaponCatalog() {
  const weaponsRoot = join(CONTENT_ROOT, 'weapons');
  const index = readFileSync(join(weaponsRoot, 'virtual-weapon-content.ts'), 'utf8');
  const dirs = [...index.matchAll(/from '\.\/([^/']+)\/weapon\.json'/g)].map((match) => match[1]);
  if (dirs.length === 0) throw new Error('virtual-weapon-content.ts imports no weapon.json');
  return dirs.map((dir) => {
    const doc = readJson(join(weaponsRoot, dir, 'weapon.json'));
    const entry = {};
    for (const field of WEAPON_CATALOG_FIELDS) if (doc[field] !== undefined) entry[field] = doc[field];
    return entry;
  });
}

/**
 * `data/item-icons.json`: for every item `icon` and weapon `iconKey`, the sheet it names in
 * `asset/assets.json` ({path, frame [w, h], columns, rows}; an image is one frame), or
 * {procedural: true} for a procedural weapon icon. An unknown key fails the conversion.
 */
export function buildItemIcons(items, weapons, manifest) {
  const procedural = new Set(Object.values(readJson(join(CONTENT_ROOT, 'weapons', 'procedural-weapon-icons.json'))));
  const assets = Array.isArray(manifest.assets) ? manifest.assets : Object.values(manifest.assets ?? {});
  const byKey = new Map(assets.filter((asset) => asset.runtime?.textureKey).map((asset) => [asset.runtime.textureKey, asset]));
  const keys = [...Object.values(items).map((item) => item.icon), ...weapons.map((weapon) => weapon.iconKey)]
    .filter((key) => typeof key === 'string' && key.length > 0);
  const icons = {};
  for (const key of [...new Set(keys)].sort()) {
    if (procedural.has(key)) {
      icons[key] = { procedural: true };
      continue;
    }
    const asset = byKey.get(key);
    if (!asset) throw new Error(`Item icon '${key}' is not a textureKey in asset/assets.json`);
    const frame = asset.source.kind === 'spritesheet'
      ? asset.source.frame
      : { w: asset.source.expect.w, h: asset.source.expect.h, cols: 1, rows: 1 };
    icons[key] = { path: `res://asset/${asset.source.path}`, frame: [frame.w, frame.h], columns: frame.cols, rows: frame.rows };
  }
  return icons;
}

/** `TS_DATA_EXPORTS` as [target, JSON text] pairs. */
export async function readTsDataExports() {
  const outputs = [];
  for (const [source, exportName, target] of TS_DATA_EXPORTS) {
    const path = join(CONTENT_ROOT, source);
    if (!existsSync(path)) throw new Error(`Data module '${source}' is missing under src/game/content`);
    const module = await import(pathToFileURL(path).href);
    if (!(exportName in module)) throw new Error(`Data module '${source}' has no export '${exportName}'`);
    outputs.push([target, `${JSON.stringify(module[exportName], null, 2)}\n`]);
  }
  return outputs;
}

export function loadCollisionLayers() {
  return readJson(join(CONTENT_ROOT, 'physics', 'collision-layers.json'));
}
