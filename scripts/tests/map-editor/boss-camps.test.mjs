import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { createServer } from 'vite';

const contentRoot = path.resolve(process.cwd(), 'src/game/content');
const vite = await createServer({
  configFile: false, root: process.cwd(), appType: 'custom',
  resolve: { alias: {
    'virtual-character-content': path.join(contentRoot, 'characters/virtual-character-content.ts'),
    'virtual-projectile-content': path.join(contentRoot, 'projectiles/virtual-projectile-content.ts'),
    'virtual-weapon-content': path.join(contentRoot, 'weapons/virtual-weapon-content.ts'),
    'virtual-effect-content': path.join(contentRoot, 'effects/virtual-effect-content.ts'),
    'virtual-animation-content': path.join(contentRoot, 'animations/virtual-animation-content.ts'),
  } },
  optimizeDeps: { noDiscovery: true }, server: { middlewareMode: true, hmr: false },
});
const { MapEditorState } = await vite.ssrLoadModule('/src/game/editor/MapEditorState.ts');
const { getBossEditorPreview } = await vite.ssrLoadModule('/src/game/content/bosses/BossCatalog.ts');
const fixture = (await vite.ssrLoadModule('/src/game/content/maps/test-rectangle.map.json')).default;
test.after(async () => vite.close());

function editor() {
  const map = structuredClone(fixture);
  map.mapId = 'boss-editor';
  map.size = { columns: 40, rows: 30 };
  map.bossCamps = [];
  map.objects.push({ instanceId: 'chest-a', objectId: 'chest.wooden', visualId: 'wooden-closed', x: 1000, y: 900, initialState: { contents: [] } });
  map.objects.push({ instanceId: 'chest-b', objectId: 'chest.wooden', visualId: 'wooden-closed', x: 1100, y: 900, initialState: { contents: [] } });
  return new MapEditorState(map, 'grass', 'resource.stone-node', 'stone-node');
}

test('defaults, preview lookup, selection exclusivity, and independent updates', () => {
  const state = editor();
  assert.deepEqual(state.value.map.bossCamps, []);
  assert.equal(state.createBossCamp({ x: 900, y: 800 }), true);
  const camp = state.value.map.bossCamps[0];
  assert.equal(camp.id, 'boss-camp-01');
  assert.equal(camp.respawnMs, 180000);
  assert.equal(camp.guardedChestInstanceId, undefined);
  assert.equal(state.value.selectedBossCampId, camp.id);
  const preview = getBossEditorPreview(camp.bossId);
  assert.equal(preview.textureKey, 'boss-fatty-one-eye');
  assert.deepEqual(preview.origin, [0.5, 0.72]);
  assert.equal(state.updateBossCamp(camp.id, { arenaRadius: 200 }), true);
  assert.equal(state.value.map.bossCamps[0].activationPerimeter.radius, 416);
  assert.equal(state.value.map.bossCamps[0].arenaPerimeter.radius, 200);
  state.selectInstance('chest-a');
  assert.equal(state.value.selectedBossCampId, undefined);
});

test('move, chest ownership, deletion, and undo/redo preserve encounter ownership', () => {
  const state = editor();
  state.createBossCamp({ x: 900, y: 800 });
  const first = state.value.map.bossCamps[0].id;
  assert.equal(state.updateBossCamp(first, { guardedChestInstanceId: 'chest-a' }), true);
  assert.equal(state.moveBossCamp(first, { x: 1000, y: 900 }), true);
  assert.deepEqual(state.value.map.bossCamps[0].activationPerimeter, { shape: 'circle', x: 1000, y: 900, radius: 416 });
  assert.equal(state.createBossCamp({ x: 1700, y: 900 }), true);
  const second = state.value.map.bossCamps[1].id;
  assert.equal(state.updateBossCamp(second, { guardedChestInstanceId: 'chest-a' }), false);
  assert.equal(state.updateBossCamp(second, { guardedChestInstanceId: 'chest-b' }), true);
  assert.equal(state.updateBossCamp(second, { guardedChestInstanceId: null }), true);
  assert.equal(state.value.map.bossCamps[1].guardedChestInstanceId, undefined);
  assert.equal(state.updateBossCamp(second, { guardedChestInstanceId: 'chest-b' }), true);
  assert.equal(state.deleteBossCamp(second), true);
  assert.equal(state.value.map.objects.some((object) => object.instanceId === 'chest-b'), true);
  state.undo();
  assert.equal(state.value.map.bossCamps.length, 2);
  state.redo();
  assert.equal(state.value.map.bossCamps.length, 1);
});

test('invalid radii and boundary edits are rejected without mutation', () => {
  const state = editor();
  state.createBossCamp({ x: 900, y: 800 });
  const camp = state.value.map.bossCamps[0];
  assert.equal(state.updateBossCampRadius(camp.id, 'arena', 500), false);
  assert.equal(state.moveBossCamp(camp.id, { x: 10, y: 10 }), false);
  assert.deepEqual(state.value.map.bossCamps[0].spawn, { x: 900, y: 800 });
});

test('resize scales only with tile size and rejects a row/column shrink that clips a circle', () => {
  const state = editor();
  state.createBossCamp({ x: 900, y: 800 });
  assert.equal(state.updateMapDimensions(40, 30, 32), true);
  assert.deepEqual(state.value.map.bossCamps[0].spawn, { x: 450, y: 400 });
  assert.equal(state.value.map.bossCamps[0].activationPerimeter.radius, 208);
  assert.equal(state.updateMapDimensions(42, 31, 32), true);
  assert.deepEqual(state.value.map.bossCamps[0].spawn, { x: 450, y: 400 });
  assert.equal(state.value.map.bossCamps[0].activationPerimeter.radius, 208);
  assert.equal(state.updateMapDimensions(10, 10, 32), false);
});

test('serialized map reload preserves the complete optional boss-camp record', () => {
  const state = editor();
  state.createBossCamp({ x: 900, y: 800 });
  const campId = state.value.map.bossCamps[0].id;
  state.updateBossCamp(campId, {
    spawn: { x: 1000, y: 900 },
    activationRadius: 430,
    arenaRadius: 275,
    respawnMs: 240000,
    guardedChestInstanceId: 'chest-a',
  });
  const serialized = JSON.parse(JSON.stringify(state.value.map));
  const reloaded = new MapEditorState(serialized, 'grass', 'resource.stone-node', 'stone-node');
  assert.deepEqual(reloaded.value.map.bossCamps, state.value.map.bossCamps);
});

test('canvas, panel, and inspector expose first-class boss-camp routing and cleanup', async () => {
  const { readFile } = await import('node:fs/promises');
  const scene = await readFile(new URL('../../../src/game/editor/MapEditorScene.ts', import.meta.url), 'utf8');
  const panel = await readFile(new URL('../../../src/game/editor/MapEditorPanel.ts', import.meta.url), 'utf8');
  const inspector = await readFile(new URL('../../../src/game/editor/MapEditorInspector.ts', import.meta.url), 'utf8');
  assert.match(scene, /renderedBosses = new Map/);
  assert.match(scene, /getBossEditorPreview\(camp\.bossId\)/);
  assert.ok(scene.indexOf('const bossHit = this.bossCampAt') < scene.indexOf("if (this.editor.value.tool === 'terrain')"));
  assert.match(scene, /Discard the unsaved visual template draft and select this boss camp/);
  assert.match(scene, /this\.templateEditor\.clearSelection\(\)/);
  assert.doesNotMatch(scene, /gameplayEditor\.resetChanges\(\).*selectBossCamp/s);
  assert.match(scene, /renderedBosses\.clear\(\)/);
  assert.match(panel, /data-boss-camp-count/);
  for (const field of ['bossId', 'spawnX', 'spawnY', 'activationRadius', 'arenaRadius', 'respawnSeconds', 'guardedChestInstanceId']) {
    assert.match(inspector, new RegExp(`data-boss-camp-field=\\"${field}\\"`));
  }
  assert.match(inspector, />None<\/option>/);
  assert.match(inspector, /delete-boss-camp/);
  assert.match(inspector, /Number\(target\.value\) \* 1000/);
});
