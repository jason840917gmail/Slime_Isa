import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import path from 'node:path';
import test from 'node:test';
import { createServer } from 'vite';

// Exercise the actual scene, catalogs, preview adapter and mutations; only
// Phaser's browser drawing surface is replaced with recorded drawing calls.
const vite = await createServer({
  configFile: false,
  appType: 'custom',
  ssr: { noExternal: ['phaser'] },
  resolve: { alias: Object.fromEntries([
    ['character', 'characters'], ['projectile', 'projectiles'], ['weapon', 'weapons'],
    ['effect', 'effects'], ['animation', 'animations'],
  ].map(([kind, folder]) => [`virtual-${kind}-content`, path.resolve(`src/game/content/${folder}/virtual-${kind}-content.ts`)])) },
  plugins: [{
    name: 'phaser-drawing-fixture',
    enforce: 'pre',
    resolveId(id) { if (id === 'phaser') return '\0phaser-drawing-fixture'; },
    load(id) {
      if (id === '\0phaser-drawing-fixture') return `export default {
        Scene: class {},
        Scenes: { Events: { UPDATE: 'update', SHUTDOWN: 'shutdown' } },
        GameObjects: { Image: class {}, Events: { DESTROY: 'destroy' } },
        Math: { Clamp: (n, min, max) => Math.min(max, Math.max(min, n)),
          Distance: { Between: (x, y, a, b) => Math.hypot(x - a, y - b) } }
      };`;
    },
  }],
  optimizeDeps: { noDiscovery: true },
  server: { middlewareMode: true, hmr: false, watch: null, ws: false },
});
test.after(() => vite.close());

const { MapEditorScene } = await vite.ssrLoadModule('/src/game/editor/MapEditorScene.ts');
const { MapEditorState } = await vite.ssrLoadModule('/src/game/editor/MapEditorState.ts');
const { NpcPlacementPreview } = await vite.ssrLoadModule('/src/game/editor/NpcPlacementPreview.ts');
const { getAsset } = await vite.ssrLoadModule('/src/game/infrastructure/assets/manifest.ts');
const level = (await vite.ssrLoadModule('/src/game/content/maps/level-1.map.json')).default;
const elder = 'level-1-npc-village-elder-plop';
const mossy = 'level-1-npc-mossy-scout';

function drawingObject() {
  const object = new EventEmitter();
  const data = new Map();
  Object.assign(object, {
    active: true, visible: true, scaleX: 1, scaleY: 1,
    setData(key, value) { data.set(key, value); return this; },
    getData(key) { return data.get(key); },
    setPosition(x, y) { Object.assign(this, { x, y }); return this; },
    setOrigin(x, y = x) { Object.assign(this, { originX: x, originY: y }); return this; },
    setScale(x, y = x) { Object.assign(this, { scaleX: x, scaleY: y }); return this; },
    setDepth(depth) { this.depth = depth; return this; },
    setName(name) { this.name = name; return this; },
    setAlpha() { return this; },
    getBounds() {
      const frame = data.get('sourceFrame') ?? { width: 64, height: 64 };
      const width = frame.width * this.scaleX;
      const height = frame.height * this.scaleY;
      const x = this.x - width * this.originX;
      const y = this.y - height * this.originY;
      return { x, y, width, height, right: x + width, bottom: y + height, centerX: x + width / 2 };
    },
    destroy() { this.active = false; this.emit('destroy'); },
  });
  for (const method of ['lineStyle', 'lineBetween', 'fillStyle', 'fillCircle', 'strokeCircle', 'fillRect', 'strokeRect']) {
    object[method] = () => object;
  }
  return object;
}

function createScene(t) {
  const scene = new MapEditorScene();
  scene.editor = new MapEditorState(level, 'grass', 'npc.world', 'village-elder-plop');
  scene.loadedMap = { map: level };
  scene.events = new EventEmitter().setMaxListeners(0);
  scene.cameras = { main: { zoom: 1, setBounds() {} } };
  scene.labels = [];
  scene.add = {
    image(x, y, textureKey, frame) {
      return Object.assign(drawingObject().setPosition(x, y), { textureKey, frame });
    },
    graphics: drawingObject,
    text(x, y, text) { scene.labels.push(text); return drawingObject().setPosition(x, y); },
  };
  scene.children = { getByName: () => undefined };
  scene.npcPlacementPreview = new NpcPlacementPreview(scene);
  t.after(() => { scene.npcPlacementPreview.destroy(); scene.events.emit('shutdown'); });
  return scene;
}

function visibleAreaLabels(scene) {
  scene.labels = [];
  scene.renderMapMarkers(scene.editor.value.map);
  return scene.labels.filter((label) => label.startsWith('npc-area-')).map((label) => label.split('\n')[1]);
}

test('all placed NPCs render from their character packages regardless of selection or tool', (t) => {
  const scene = createScene(t);
  // Keep the real placements; terrain and ordinary object artwork are outside this regression.
  const map = scene.editor.value.map;
  map.objects = map.objects.filter((object) => object.objectId.startsWith('npc.'));
  map.layers[0].rows = [];
  scene.renderOverlays = () => {};
  for (const tool of ['pan', 'select', 'npc-area', 'erase']) {
    scene.editor.selectInstance(elder);
    scene.editor.setTool(tool);
    for (const selected of [elder, mossy, undefined]) {
      scene.editor.selectInstance(selected);
      scene.renderDocument();
      assert.equal(scene.renderedInstances.size, map.objects.length);
      for (const [instanceId, assetId] of [[elder, 'character.npc.village-elder-plop'], [mossy, 'character.npc.mossy-scout']]) {
        const image = scene.renderedInstances.get(instanceId);
        assert.ok(image?.active && image.visible, `${instanceId} missing in ${tool}`);
        assert.equal(image.textureKey, getAsset(assetId).runtime.textureKey);
      }
    }
  }
});

test('only the selected NPC area is drawn, including when an explicit area selection is stale', (t) => {
  const scene = createScene(t);
  const editor = scene.editor;
  assert.deepEqual(visibleAreaLabels(scene), []);
  editor.setTool('select');
  for (const id of [elder, mossy]) {
    editor.selectInstance(id);
    assert.deepEqual(visibleAreaLabels(scene), [id]);
  }
  editor.setTool('npc-area');
  editor.selectNpcWanderArea(editor.getNpcWanderArea(elder).id);
  assert.equal(editor.value.selectedInstanceId, elder);
  assert.deepEqual(visibleAreaLabels(scene), [elder]);
  editor.selectInstance(mossy);
  assert.deepEqual(visibleAreaLabels(scene), [mossy]);
  editor.selectInstance(undefined);
  assert.deepEqual(visibleAreaLabels(scene), []);
  assert.equal(scene.selectedNpcArea(), undefined, 'stale area must not expose resize handles');
  editor.selectInstance(level.objects.find((object) => !object.objectId.startsWith('npc.')).instanceId);
  assert.deepEqual(visibleAreaLabels(scene), []);
  editor.selectInstance(mossy);
  editor.deleteNpcWanderArea(editor.getNpcWanderArea(mossy).id);
  assert.deepEqual(visibleAreaLabels(scene), [], 'an NPC without an area has no overlay');
});

test('erase hits the visible NPC sprite above its anchor and undo restores the NPC and area together', (t) => {
  const scene = createScene(t);
  const editor = scene.editor;
  const original = structuredClone(editor.value.map);
  const object = original.objects.find((object) => object.instanceId === elder);
  const image = drawingObject().setPosition(object.x, object.y).setOrigin(0.5, 1).setDepth(1);
  image.setData('sourceFrame', { width: 100, height: 200 });
  scene.renderedInstances.set(elder, image);
  editor.selectNpcWanderArea(editor.getNpcWanderArea(elder).id);
  editor.setTool('erase');
  let observed;
  editor.subscribe((state) => { observed = state; });
  scene.eraseDragStart = { x: object.x, y: object.y - 150 };
  scene.finishEraseDrag(object.x, object.y - 150);
  assert.equal(editor.value.map.objects.some((object) => object.instanceId === elder), false);
  assert.equal(editor.getNpcWanderArea(elder), undefined);
  assert.equal(observed.selectedInstanceId, undefined, 'deletion notification must already clear selection');
  assert.deepEqual(editor.value.map.layers, original.layers, 'sprite click must not erase terrain');
  assert.ok(editor.getNpcWanderArea(mossy));
  editor.undo();
  assert.deepEqual(editor.value.map, original);
  editor.redo();
  assert.equal(editor.getNpcWanderArea(elder), undefined);
});

test('box erase removes mixed ordinary objects and NPCs with their areas in one undo step', (t) => {
  const scene = createScene(t);
  const editor = scene.editor;
  const original = structuredClone(editor.value.map);
  editor.setTool('erase');
  scene.eraseDragStart = { x: 0, y: 0 };
  scene.finishEraseDrag(level.size.columns * level.tileSize, level.size.rows * level.tileSize);
  assert.deepEqual(editor.value.map.objects, []);
  assert.deepEqual(editor.value.map.npcWanderAreas, []);
  editor.undo();
  assert.deepEqual(editor.value.map, original);
});

test('the selected NPC area can still move and resize using its area ID', (t) => {
  const scene = createScene(t);
  const editor = scene.editor;
  editor.selectInstance(mossy);
  editor.setTool('npc-area');
  const original = structuredClone(editor.getNpcWanderArea(mossy));
  scene.beginNpcAreaMove(original, original.perimeter.x, original.perimeter.y);
  scene.updateNpcAreaMove(original.perimeter.x + 16, original.perimeter.y + 16);
  scene.finishNpcAreaMove();
  assert.equal(editor.getNpcWanderArea(mossy).perimeter.x, original.perimeter.x + 16);
  editor.undo();
  editor.selectInstance(mossy);
  editor.setTool('npc-area');
  scene.beginNpcAreaResize(editor.getNpcWanderArea(mossy), 'se');
  scene.finishNpcAreaResize(960, 768);
  assert.deepEqual(editor.getNpcWanderArea(mossy).perimeter, { shape: 'rectangle', x: 672, y: 640, w: 288, h: 128 });
  assert.deepEqual(visibleAreaLabels(scene), [mossy]);
  editor.undo();
  assert.deepEqual(editor.getNpcWanderArea(mossy), original);
});
