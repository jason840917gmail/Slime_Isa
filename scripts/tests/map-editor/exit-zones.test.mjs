import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { createServer } from 'vite';

const contentRoot = path.resolve(process.cwd(), 'src/game/content');
const vite = await createServer({
  configFile: false,
  root: process.cwd(),
  appType: 'custom',
  resolve: {
    alias: {
      'virtual-character-content': path.join(contentRoot, 'characters/virtual-character-content.ts'),
      'virtual-projectile-content': path.join(contentRoot, 'projectiles/virtual-projectile-content.ts'),
      'virtual-weapon-content': path.join(contentRoot, 'weapons/virtual-weapon-content.ts'),
      'virtual-effect-content': path.join(contentRoot, 'effects/virtual-effect-content.ts'),
      'virtual-animation-content': path.join(contentRoot, 'animations/virtual-animation-content.ts'),
    },
  },
  optimizeDeps: { noDiscovery: true },
  server: { middlewareMode: true, hmr: false },
});

const { MapEditorState } = await vite.ssrLoadModule('/src/game/editor/MapEditorState.ts');
const { edgeDirectionForZone, edgeExitZone, exitDirection, connectionAt } = await vite.ssrLoadModule('/src/game/editor/MapConnections.ts');
const mapFixture = (await vite.ssrLoadModule('/src/game/content/maps/test-rectangle.map.json')).default;

test.after(async () => vite.close());

function mapWithExit(exit, size = { columns: 24, rows: 18 }, tileSize = 64) {
  const map = structuredClone(mapFixture);
  map.mapId = 'test-exits';
  map.size = size;
  map.tileSize = tileSize;
  map.exits = [structuredClone(exit)];
  return map;
}

function editorFor(map) {
  return new MapEditorState(map, 'grass', 'resource.stone-node', 'stone-node');
}

test('exit direction uses connection entry even when geometry is stale', () => {
  const map = { size: { columns: 56, rows: 56 }, tileSize: 64 };
  const staleZone = { x: 1504, y: 0, w: 32, h: 1152 };
  assert.equal(edgeDirectionForZone(staleZone, map), 'north');
  assert.equal(exitDirection({ entry: 'west', zone: staleZone }, map), 'east');
  assert.equal(exitDirection({ entry: 'invalid', zone: staleZone }, map), undefined);
});

test('edge zones have a positive lane even on tiny tile sizes', () => {
  assert.deepEqual(edgeExitZone('east', { size: { columns: 3, rows: 2 }, tileSize: 1 }), {
    x: 2, y: 0, w: 1, h: 2,
  });
  assert.deepEqual(edgeExitZone('south', { size: { columns: 3, rows: 2 }, tileSize: 3 }), {
    x: 0, y: 5, w: 9, h: 1,
  });
});

test('constructor repairs a stale resolved exit without creating an undo command', () => {
  const editor = editorFor(mapWithExit({
    zone: { x: 1504, y: 0, w: 32, h: 1152 }, to: 'gloop-forest', entry: 'west',
  }, { columns: 56, rows: 56 }));
  assert.deepEqual(editor.value.map.exits[0].zone, { x: 3552, y: 0, w: 32, h: 1152 });
  assert.equal(editor.value.dirty, true);
  assert.equal(editor.value.revision, 0);
  assert.equal(editor.value.canUndo, false);
});

test('resizing keeps a partial exit on the same edge and scales its lane', () => {
  const editor = editorFor(mapWithExit({
    zone: { x: 1472, y: 512, w: 64, h: 128 }, to: 'gloop-forest', entry: 'west',
  }));
  assert.equal(editor.updateMapDimensions(56, 56, 64), true);
  assert.deepEqual(editor.value.map.exits[0].zone, { x: 3520, y: 512, w: 64, h: 128 });
});

test('resizing keeps a full-height exit full-height on the same edge', () => {
  const editor = editorFor(mapWithExit({
    zone: { x: 1504, y: 0, w: 32, h: 1152 }, to: 'gloop-forest', entry: 'west',
  }));
  assert.equal(editor.updateMapDimensions(56, 56, 64), true);
  assert.deepEqual(editor.value.map.exits[0].zone, { x: 3552, y: 0, w: 32, h: 3584 });
});

test('connection controls use one authoritative exit and remove duplicate records', () => {
  const map = mapWithExit({ zone: { x: 1472, y: 512, w: 64, h: 128 }, to: 'old', entry: 'west' });
  map.exits.push({ zone: { x: 1504, y: 0, w: 32, h: 1152 }, to: 'duplicate', entry: 'west' });
  const editor = editorFor(map);
  editor.setConnection('east', 'gloop-forest');
  assert.equal(editor.value.map.exits.filter((exit) => exitDirection(exit, editor.value.map) === 'east').length, 1);
  assert.equal(connectionAt('east', editor.value.map)?.to, 'gloop-forest');
});

test('exit movement uses a revision guard and keeps selection indexed to the exit', () => {
  const editor = editorFor(mapWithExit({
    zone: { x: 1472, y: 512, w: 64, h: 128 }, to: 'gloop-forest', entry: 'west',
  }));
  editor.selectExit(0);
  const expected = structuredClone(editor.value.map.exits[0]);
  const initialRevision = editor.value.revision;
  assert.equal(editor.updateExitZone(0, initialRevision, expected, { x: 1472, y: 704, w: 64, h: 128 }), true);
  assert.equal(editor.value.selectedExitIndex, 0);
  assert.equal(editor.value.map.exits[0].zone.y, 704);
  assert.equal(editor.updateExitZone(0, initialRevision, expected, { x: 1472, y: 768, w: 64, h: 128 }), false);
  assert.equal(editor.value.selectedExitIndex, undefined);
});

test('network save failures preserve dirty state and warn before retry', async () => {
  const editor = editorFor(mapWithExit({
    zone: { x: 1472, y: 512, w: 64, h: 128 }, to: 'gloop-forest', entry: 'west',
  }));
  editor.mutate('move exit', (map) => { map.exits[0].zone.y = 576; });
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => { throw new TypeError('offline'); };
  try {
    await editor.save();
  } finally {
    globalThis.fetch = originalFetch;
  }
  assert.equal(editor.value.dirty, true);
  assert.match(editor.value.status, /outcome unknown/i);
});
