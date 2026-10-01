#!/usr/bin/env node
// Gives world objects an ambient idle loop (docs/assets/AMBIENT_ANIMATION.md):
// - decorations with a row in the ambient sheet play its 8 frames;
// - every tree sways its canopy (baked frames; the trunk stays still).
// Each clip autoplays with `randomizeStart` so placed copies never move in sync.
// Idempotent: re-running rewrites the same nodes/resources. Dry run by default.
//   node scripts/props/wire-ambient-animations.mjs [--write]
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const OBJECTS = 'src/game/content/scenes/authored/objects';
const write = process.argv.includes('--write');

const AMBIENT_SHEET = 'sheet.decorations.ambient.8x5';
// Row order matches scripts/art/build-ambient-decoration-sheets.py.
const DECORATIONS = {
  campfire: { row: 0, fps: 10 },
  'cooking-cauldron': { row: 1, fps: 8 },
  'lantern-post': { row: 2, fps: 6 },
  'village-banner': { row: 3, fps: 7 },
  'stone-birdbath': { row: 4, fps: 6 },
};
const FRAMES = 8;
const IDLE = 'object.ambient.idle';
const AMBIENT_PLAYER_ID = 'ambient-animation';

function frameClip(row, fps) {
  return {
    durationSeconds: FRAMES / fps,
    framesPerSecond: fps,
    loop: true,
    loopMode: 'wrap',
    tracks: [{ binding: '../Visual', property: 'frame', keys: Array.from({ length: FRAMES }, (_, i) => ({ at: i, value: row * FRAMES + i })) }],
  };
}

// Trees play canopy-only sway frames baked by scripts/art/build-tree-sway-sheets.py:
// the source frame f becomes frames f*8 .. f*8+7 of the sway sheet. The trunk is
// identical in every frame, so only the leaves move.
const TREE_SWAY = { 'sheet.trees.8x6': 'sheet.trees.sway.16x22', 'sheet.trees.3x1': 'sheet.trees.3x1.sway.8x3' };
const SWAY_SHEETS = new Set(Object.values(TREE_SWAY));
const TREE_SWAY_FPS = 4;
// Leafless trees have nothing to sway: they stay on the static sheet with no
// ambient player. Keep in sync with BARE in scripts/art/build-tree-sway-sheets.py.
const BARE_TREE_FRAMES = { 'sheet.trees.8x6': new Set([0, 1, 2, 3, 4, 5, 6, 7, 8]) };
const STATIC_OF = Object.fromEntries(Object.entries(TREE_SWAY).map(([still, sway]) => [sway, still]));

function removeAmbientPlayer(scene) {
  const player = scene.nodes.find((node) => node.id === AMBIENT_PLAYER_ID);
  if (!player) return;
  const libraryId = player.properties.library?.resourceId;
  scene.nodes = scene.nodes.filter((node) => node !== player);
  scene.subresources = scene.subresources.filter((resource) => resource.resourceId !== libraryId);
  // Keep sibling order dense.
  scene.nodes.filter((node) => node.parentId === player.parentId).sort((a, b) => a.order - b.order).forEach((node, index) => { node.order = index; });
}

function treeSwayClip(base) {
  return frameClip(base, TREE_SWAY_FPS);
}

function upsertPlayer(scene, resourceId, autoplay) {
  const body = scene.nodes.find((node) => node.parentId === null);
  let player = scene.nodes.find((node) => node.type === 'AnimationPlayer' && node.parentId === body.id);
  if (!player) {
    player = { id: AMBIENT_PLAYER_ID, name: 'AmbientAnimation', type: 'AnimationPlayer', parentId: body.id, order: 0, properties: {} };
    const siblings = scene.nodes.filter((node) => node.parentId === body.id);
    player.order = Math.max(...siblings.map((node) => node.order)) + 1;
    scene.nodes.push(player);
  }
  player.properties = { ...player.properties, library: { resourceId }, domain: player.properties.domain ?? 'render', autoplay, randomizeStart: true };
  return player;
}

function upsertLibrary(scene, resourceId, animations) {
  const existing = scene.subresources.find((resource) => resource.resourceId === resourceId);
  if (existing) existing.animations = animations;
  else scene.subresources.push({ version: 1, resourceId, kind: 'animation-library', animations });
}

function visualOf(scene) {
  return scene.nodes.find((node) => node.type === 'Sprite2D' && node.name === 'Visual');
}

const changed = [];
for (const file of readdirSync(OBJECTS).filter((name) => name.endsWith('.scene.json'))) {
  const path = join(OBJECTS, file);
  const before = readFileSync(path, 'utf8');
  const scene = JSON.parse(before);
  const visual = visualOf(scene);
  if (!visual) continue;
  const spriteId = visual.properties.texture?.resourceId;
  const sprite = scene.subresources.find((resource) => resource.resourceId === spriteId);
  if (!sprite) continue;
  const prefix = spriteId.replace(/\.sprite$/, '');

  const decoration = file.match(/^decoration-world-solid--(.+)\.scene\.json$/)?.[1];
  if (decoration && DECORATIONS[decoration]) {
    const { row, fps } = DECORATIONS[decoration];
    sprite.assetId = AMBIENT_SHEET;
    visual.properties.frame = row * FRAMES;
    const libraryId = `${prefix}.ambient-animations`;
    upsertLibrary(scene, libraryId, { [IDLE]: frameClip(row, fps) });
    upsertPlayer(scene, libraryId, IDLE);
  } else if (/^tree-/.test(file)) {
    const player = scene.nodes.find((node) => node.type === 'AnimationPlayer');
    const library = player && scene.subresources.find((resource) => resource.resourceId === player.properties.library?.resourceId);
    if (TREE_SWAY[sprite.assetId] || SWAY_SHEETS.has(sprite.assetId)) {
      let base;
      if (SWAY_SHEETS.has(sprite.assetId)) base = Math.floor((visual.properties.frame ?? 0) / FRAMES);
      else {
        // A single-key frame track in an existing idle clip picks the art (snow pine).
        const frameTrack = library?.animations?.[player.properties.autoplay]?.tracks.find((track) => track.property === 'frame');
        base = frameTrack?.keys.length === 1 ? frameTrack.keys[0].value : (visual.properties.frame ?? 0);
        sprite.assetId = TREE_SWAY[sprite.assetId];
      }
      const stillSheet = STATIC_OF[sprite.assetId];
      if (BARE_TREE_FRAMES[stillSheet]?.has(base) && (!player || player.id === AMBIENT_PLAYER_ID)) {
        sprite.assetId = stillSheet;
        visual.properties.frame = base;
        removeAmbientPlayer(scene);
      } else if (player && player.id !== AMBIENT_PLAYER_ID && library) {
        visual.properties.frame = base * FRAMES;
        library.animations[player.properties.autoplay] = treeSwayClip(base);
        player.properties = { ...player.properties, randomizeStart: true };
      } else {
        visual.properties.frame = base * FRAMES;
        const libraryId = `${prefix}.ambient-animations`;
        upsertLibrary(scene, libraryId, { [IDLE]: treeSwayClip(base) });
        upsertPlayer(scene, libraryId, IDLE);
      }
    } else if (player) {
      // Trees with their own authored frame animation (the autumn tree) keep it.
      player.properties = { ...player.properties, randomizeStart: true };
    }
  } else continue;

  const after = `${JSON.stringify(scene, null, 2)}\n`;
  if (after !== before) {
    changed.push(file);
    if (write) writeFileSync(path, after);
  }
}
console.log(`${write ? 'Updated' : 'Would update'} ${changed.length} object scene(s)`);
for (const file of changed) console.log(`  ${file}`);
