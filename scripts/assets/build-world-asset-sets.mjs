/**
 * Works out which images each world needs on its own, so the game loads them
 * only when the player enters that world (roadmap 10.1).
 *
 *   node scripts/assets/build-world-asset-sets.mjs          # write the file
 *   node scripts/assets/build-world-asset-sets.mjs --check  # fail when stale
 *
 * For every world scene (`world.<id>`) it walks the scene graph the way the
 * game mounts it: instances, inline and external resources (sprite sheets,
 * textures, tile sets through the tile data a world paints), scene references
 * (a boss camp's boss), enemy spawn areas (`data.enemies[].type` →
 * `character.<type>`), and enemy projectiles and effects.
 *
 * An image is **world-only** when it is in the `boot` or `interiors` bundle,
 * some world uses it, and nothing that can appear anywhere uses it: the
 * player, collectibles, weapons, effects, projectiles, UI and audio scenes,
 * placeable furniture (items.json), item icons (items.json `icon`), and the
 * pinned families below. The result, `src/game/content/worldAssetSets.generated.json`,
 * lists each world's world-only images. Boot loads every other `boot` and
 * `interiors` image, so an asset this file does not know about is still
 * loaded at boot: a stale file costs download size, never a missing texture.
 */
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));
const authoredRoot = join(root, 'src/game/content/scenes/authored');
const outputPath = join(root, 'src/game/content/worldAssetSets.generated.json');
const manifest = JSON.parse(readFileSync(join(root, 'asset/assets.json'), 'utf8'));
const items = JSON.parse(readFileSync(join(root, 'src/game/content/items/items.json'), 'utf8'));

/** Scenes mounted anywhere, whatever the world: their images always load at boot. */
const CORE_SCENES = [
  /^character\.player-slime$/,
  /^(ui|shell|effect|weapon|projectile|audio)\./,
  /^object\.collectible-/,
];
/** Images code draws by key anywhere (icons, the lash, HUD art): always loaded at boot. */
const PINNED_ASSETS = [
  /^character\.player\./,
  /^(ui|weapon|effect)\./,
  /^enemy\.projectile\./,
  /^sheet\.(items|resources)\./,
];

function listFiles(dir, suffix) {
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...listFiles(full, suffix));
    else if (entry.name.endsWith(suffix)) out.push(full);
  }
  return out;
}

const scenes = new Map();
for (const file of listFiles(authoredRoot, '.scene.json')) {
  const document = JSON.parse(readFileSync(file, 'utf8'));
  scenes.set(document.sceneId, document);
}
const externalResources = new Map();
for (const file of listFiles(join(authoredRoot, 'resources'), '.resource.json')) {
  const resource = JSON.parse(readFileSync(file, 'utf8'));
  externalResources.set(resource.resourceId, resource);
}

const parsed = (value) => (typeof value === 'string' ? JSON.parse(value) : value);

/** Every object value in a JSON tree (node properties, overrides, script data). */
function* objectsIn(value) {
  if (Array.isArray(value)) {
    for (const entry of value) yield* objectsIn(entry);
  } else if (value && typeof value === 'object') {
    yield value;
    for (const entry of Object.values(value)) yield* objectsIn(entry);
  }
}

/** Asset IDs a scene and everything it mounts use. */
function sceneAssets(sceneId, assets = new Set(), visited = new Set()) {
  if (visited.has(sceneId)) return assets;
  visited.add(sceneId);
  const document = scenes.get(sceneId);
  if (!document) return assets;
  const inline = new Map((document.subresources ?? []).map((resource) => [resource.resourceId, resource]));
  const resource = (resourceId) => inline.get(resourceId) ?? externalResources.get(resourceId);
  const addResource = (entry) => {
    if (!entry) return;
    if (typeof entry.assetId === 'string') assets.add(entry.assetId);
    for (const variant of entry.variants ?? []) if (typeof variant === 'string') assets.add(variant);
    if (entry.kind === 'tile-data') {
      const tileSet = resource(entry.tileSet);
      const tiles = parsed(tileSet?.tiles) ?? {};
      for (const cell of parsed(entry.cells) ?? []) {
        for (const assetId of tiles[cell.tileId]?.assetIds ?? []) assets.add(assetId);
      }
    }
  };
  for (const entry of document.subresources ?? []) if (entry.kind !== 'tile-set') addResource(entry);
  const trees = [...document.nodes.map((node) => node.properties ?? {}), ...(document.instances ?? []).map((instance) => instance.overrides ?? [])];
  for (const tree of trees) {
    for (const object of objectsIn(tree)) {
      if (typeof object.resourceId === 'string' && !inline.has(object.resourceId)) addResource(externalResources.get(object.resourceId));
      if (typeof object.sceneId === 'string') sceneAssets(object.sceneId, assets, visited);
      if (typeof object.assetId === 'string') assets.add(object.assetId);
      if (typeof object.projectileId === 'string') sceneAssets(`projectile.${object.projectileId}`, assets, visited);
      if (Array.isArray(object.enemies)) {
        for (const enemy of object.enemies) if (typeof enemy?.type === 'string') sceneAssets(`character.${enemy.type}`, assets, visited);
      }
      for (const [key, value] of Object.entries(object)) {
        if (/effectid$/i.test(key) && typeof value === 'string' && value) sceneAssets(`effect.${value}`, assets, visited);
      }
    }
  }
  for (const instance of document.instances ?? []) sceneAssets(instance.sceneId, assets, visited);
  return assets;
}

const textureKeyToAsset = new Map(Object.entries(manifest.assets).map(([id, asset]) => [asset.runtime?.textureKey, id]));
const itemList = Array.isArray(items) ? items : Object.values(items.items ?? items);
const core = new Set();
for (const sceneId of scenes.keys()) {
  if (CORE_SCENES.some((pattern) => pattern.test(sceneId))) sceneAssets(sceneId, core);
}
for (const item of itemList) {
  const icon = item?.icon;
  const key = typeof icon === 'string' ? icon : icon?.textureKey ?? icon?.key;
  if (textureKeyToAsset.has(key)) core.add(textureKeyToAsset.get(key));
  for (const sceneId of item?.placeable?.sceneIds ?? []) sceneAssets(sceneId, core);
}
for (const assetId of Object.keys(manifest.assets)) {
  if (PINNED_ASSETS.some((pattern) => pattern.test(assetId))) core.add(assetId);
}

const deferrable = new Set([...(manifest.bundles.boot ?? []), ...(manifest.bundles.interiors ?? [])]
  .filter((assetId) => manifest.assets[assetId]?.source?.kind !== 'audio'));
const worlds = {};
for (const sceneId of [...scenes.keys()].filter((id) => id.startsWith('world.')).sort()) {
  const own = [...sceneAssets(sceneId)].filter((assetId) => deferrable.has(assetId) && !core.has(assetId)).sort();
  if (own.length > 0) worlds[sceneId.slice('world.'.length)] = own;
}

const result = `${JSON.stringify({
  note: 'Generated by scripts/assets/build-world-asset-sets.mjs; do not edit. Images each world loads when entered (roadmap 10.1).',
  worlds,
}, null, 2)}\n`;
const previous = (() => { try { return readFileSync(outputPath, 'utf8'); } catch { return ''; } })();
const deferred = new Set(Object.values(worlds).flat());
const bytes = (ids) => [...ids].reduce((sum, id) => {
  try { return sum + readFileSync(join(root, 'asset', manifest.assets[id].source.path)).length; } catch { return sum; }
}, 0);
const summary = `${Object.keys(worlds).length} worlds, ${deferred.size} world-only images (${(bytes(deferred) / 1e6).toFixed(1)} MB) out of ${deferrable.size} boot/interior images (${(bytes(deferrable) / 1e6).toFixed(1)} MB)`;
if (process.argv.includes('--check')) {
  if (previous.replace(/\r\n/g, '\n') !== result) {
    console.error(`world-assets check failed: ${relative(root, outputPath)} is stale. Run node scripts/assets/build-world-asset-sets.mjs`);
    process.exit(1);
  }
  console.log(`world-assets check OK — ${summary}.`);
} else {
  writeFileSync(outputPath, result);
  console.log(`wrote ${relative(root, outputPath)} — ${summary}.`);
}
