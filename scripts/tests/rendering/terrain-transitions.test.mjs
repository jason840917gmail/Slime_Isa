import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import { EventEmitter } from 'node:events';
import { build } from 'esbuild';

const phaserStub = `
class Image {
  constructor(scene,x,y,key,frame) {
    this.scene=scene; this.x=x; this.y=y; this.key=key; this.frame=frame; this.visible=true; this.cameraFilter=0;
    const size=scene.textures.getFrame?.(key, frame); this.width=size?.cutWidth??512; this.height=size?.cutHeight??512;
    scene.allImages.push(this);
  }
  setOrigin() { return this; }
  setDepth(d) { this.depth=d;return this; }
  setName(n) { this.name=n;return this; }
  setData(k,v) { (this.data??={})[k]=v;return this; }
  setScale(s) { this.scale=s;return this; }
  setFlipX(f) { this.flipX=f;return this; }
  willRender(camera) { return !this.destroyed && this.visible && !(this.cameraFilter & camera.id); }
  destroy() { this.destroyed=true; }
}
export default {GameObjects:{Image},Scenes:{Events:{SHUTDOWN:'shutdown'}}};`;
const stubPhaser = { name: 'phaser-double', setup(api) {
  api.onResolve({ filter: /^phaser$/ }, () => ({ path: 'phaser', namespace: 'stub' }));
  api.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({ contents: phaserStub }));
} };
async function load(entry) {
  const bundle = await build({ entryPoints: [entry], bundle: true, format: 'esm', platform: 'node', write: false, plugins: [stubPhaser] });
  return import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`);
}
const { default: { GameObjects: { Image: ChunkImage } } } = await import(`data:text/javascript;base64,${Buffer.from(phaserStub).toString('base64')}`);
const { renderTerrainBlend, terrainBlendLookup } = await load('src/game/features/world/TerrainTransitionRenderer.ts');
const AUTHORED_TILES = JSON.parse(fs.readFileSync('src/game/content/scenes/authored/resources/terrain/terrain.tile-set.resource.json', 'utf8')).tiles;
const { planTerrainBlendChunks } = await load('src/game/features/world/TerrainBlendField.ts');
const { mergeCellRectangles } = await load('src/game/infrastructure/phaser-nodes/TileMapLayer2DNode.ts');
const { resolveSheetWrapFrame } = await load('src/game/features/world/GroundSheetRegion.ts');

const dimensions = (columns, rows, tileSize = 64) => ({ width: columns * tileSize, height: rows * tileSize, tileSize, columns, rows });
const lookup = (tileId) => ({
  floor: { material: 'floor', priority: 10 },
  moss: { material: 'moss', priority: 20 },
  water: { material: 'water', priority: 5 },
}[tileId]);
const fill = (columns, rows, tileId) => Array.from({ length: rows }, () => Array(columns).fill(tileId));
const plan = (grid, options = {}) => planTerrainBlendChunks(grid, lookup, dimensions(grid[0].length, grid.length), { seed: 3, ...options });

/** Final composited share of `material` at world point (x, y), from the over-alphas. */
function shareAt(chunk, material, x, y) {
  const sx = Math.min(chunk.samplesX - 1, Math.floor((x - chunk.originX) / chunk.sampleStep));
  const sy = Math.min(chunk.samplesY - 1, Math.floor((y - chunk.originY) / chunk.sampleStep));
  const index = sy * chunk.samplesX + sx;
  let remaining = 1;
  let share = 0;
  for (let layer = chunk.layers.length - 1; layer >= 0; layer -= 1) {
    const alpha = chunk.layers[layer].alpha[index] / 255;
    if (chunk.layers[layer].material === material) share = remaining * alpha;
    remaining *= 1 - alpha;
  }
  return share;
}

test('uniform terrain needs no blend chunks', () => {
  assert.deepEqual(plan(fill(12, 12, 'floor')), []);
  assert.deepEqual(plan([[]]), []);
});

test('a lone cell becomes a rounded blob: centre kept, corners given to its neighbours', () => {
  const grid = fill(7, 7, 'floor');
  grid[3][3] = 'moss';
  const [chunk] = plan(grid, { seed: 0 });
  assert.ok(chunk);
  const centre = 3.5 * 64;
  assert.ok(shareAt(chunk, 'moss', centre, centre) > 0.95);
  for (const [dx, dy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
    assert.ok(shareAt(chunk, 'moss', centre + dx * 30, centre + dy * 30) < 0.5, `corner ${dx},${dy}`);
  }
  assert.ok(shareAt(chunk, 'floor', 20, 20) > 0.99, 'far floor untouched');
});

test('shares form a partition of unity and paint in ascending priority', () => {
  const grid = fill(8, 6, 'floor');
  for (let y = 0; y < 6; y += 1) { grid[y][0] = 'water'; grid[y][7] = 'moss'; }
  const [chunk] = plan(grid);
  assert.deepEqual(chunk.layers.map((layer) => layer.material), ['water', 'floor', 'moss']);
  for (let y = 4; y < chunk.textureHeight; y += 37) {
    for (let x = 4; x < chunk.textureWidth; x += 29) {
      const total = ['water', 'floor', 'moss'].reduce((sum, material) => sum + shareAt(chunk, material, chunk.originX + x, chunk.originY + y), 0);
      assert.ok(Math.abs(total - 1) < 0.02, `total ${total} at ${x},${y}`);
    }
  }
});

test('blending is deterministic per seed and the seed changes the border', () => {
  const grid = fill(8, 8, 'floor');
  for (let y = 0; y < 8; y += 1) for (let x = 4; x < 8; x += 1) grid[y][x] = 'moss';
  const [a] = plan(grid, { seed: 5 });
  const [b] = plan(grid, { seed: 5 });
  const [c] = plan(grid, { seed: 6 });
  assert.deepEqual(a.layers.map((layer) => [...layer.alpha]), b.layers.map((layer) => [...layer.alpha]));
  assert.notDeepEqual(a.layers.map((layer) => [...layer.alpha]), c.layers.map((layer) => [...layer.alpha]));
});

test('cells outside the blend group are excluded and keep their base tile', () => {
  const grid = fill(6, 4, 'floor');
  grid[1][1] = 'moss';
  grid[2][4] = 'stone-wall';
  const [chunk] = plan(grid);
  assert.deepEqual(chunk.excludedCells.filter((cell) => cell.x >= 0 && cell.y >= 0 && cell.x < 6 && cell.y < 4), [{ x: 4, y: 2 }]);
  assert.ok(chunk.layers.every((layer) => shareAt(chunk, layer.material, 4.5 * 64, 2.5 * 64) === 0));
});

test('chunks keep exact world bounds and a 2px gutter, and only borders get baked', () => {
  const grid = fill(21, 9, 'floor');
  grid[0][0] = 'moss';
  grid[8][20] = 'moss';
  const chunks = plan(grid);
  // Borders sit in the first and last columns of chunks; the middle chunk is two cells away from both.
  assert.deepEqual(chunks.map(({ x, y, width, height }) => [x, y, width, height]), [
    [0, 0, 512, 512], [1024, 0, 320, 512], [1024, 512, 320, 64],
  ]);
  for (const chunk of chunks) {
    assert.equal(chunk.x - chunk.originX, 2);
    assert.equal(chunk.textureWidth, chunk.width + 4);
    assert.ok(chunk.x + chunk.width <= 21 * 64 && chunk.y + chunk.height <= 9 * 64);
  }
});

function makeCanvasFactory({ failAtDraw = Infinity } = {}) {
  const log = { canvases: 0, draws: 0 };
  const factory = (width, height) => {
    log.canvases += 1;
    const context = {
      globalCompositeOperation: 'source-over', imageSmoothingEnabled: true,
      clearRect() {}, save() {}, restore() {}, translate() {}, scale() {}, putImageData() {},
      createImageData: (w, h) => ({ data: new Uint8ClampedArray(w * h * 4) }),
      drawImage() { if (++log.draws === failAtDraw) throw new Error('simulated canvas failure'); },
    };
    return { width, height, getContext: () => context };
  };
  return { factory, log };
}

function makeScene() {
  const textures = new Map();
  const scene = { events: new EventEmitter(), allImages: [], chunks: [] };
  scene.add = {
    image(x, y, key, frame) {
      if (scene.ImageClass) return new scene.ImageClass(scene, x, y, key, frame);
      const image = new ChunkImage(scene, x, y, key, frame);
      scene.chunks.push(image);
      return image;
    },
  };
  scene.textures = {
    exists: (key) => textures.has(key),
    getFrame: (key, frame) => (key === 'sheet' ? { cutX: 0, cutY: 0, cutWidth: 64, cutHeight: 64, source: { image: {} } } : textures.get(key)?.frames?.[frame]),
    create(key, canvas) {
      const texture = { canvas, frames: {}, add(name, source, x, y, width, height) { this.frames[name] = { cutX: x, cutY: y, cutWidth: width, cutHeight: height }; } };
      textures.set(key, texture);
      return texture;
    },
    remove(key) { textures.delete(key); },
  };
  scene.textureCount = () => textures.size;
  return scene;
}
const resolveVisual = () => ({ textureKey: 'sheet', frame: 0, flipX: false, flipY: false });

function render(grid, scene = makeScene(), canvas = makeCanvasFactory()) {
  const layer = renderTerrainBlend({
    scene, grid, lookup: terrainBlendLookup(AUTHORED_TILES), resolveVisual, seed: 42,
    dimensions: dimensions(grid[0].length, grid.length), createCanvas: canvas.factory,
  });
  return { scene, layer, canvas };
}

test('baked chunks own their canvas textures and release them on destroy and shutdown', () => {
  const { scene, layer } = render([['forest-floor', 'forest-moss']]);
  assert.equal(layer.chunkCount, 1);
  assert.equal(scene.textureCount(), 1);
  assert.equal(scene.chunks[0].name, 'terrain-transition-chunk');
  layer.destroy();
  assert.equal(scene.textureCount(), 0);
  assert.ok(scene.chunks.every((image) => image.destroyed));
  assert.equal(scene.events.listenerCount('shutdown'), 0);

  const second = render([['forest-floor', 'forest-moss']], scene);
  scene.events.emit('shutdown');
  assert.equal(scene.textureCount(), 0);
  assert.ok(second.scene.chunks.every((image) => image.destroyed));
});

test('a failed bake releases every partially created texture and the shutdown listener', () => {
  const grid = [Array.from({ length: 20 }, (_, x) => (x % 2 ? 'forest-moss' : 'forest-floor'))];
  const complete = render(grid);
  assert.ok(complete.layer.chunkCount > 1);
  const totalDraws = complete.canvas.log.draws;
  for (const failAtDraw of [3, totalDraws]) {
    const scene = makeScene();
    assert.throws(() => render(grid, scene, makeCanvasFactory({ failAtDraw })), /simulated canvas failure/);
    if (failAtDraw === totalDraws) assert.ok(scene.chunks.length > 0, 'failure follows a completed chunk');
    assert.equal(scene.textureCount(), 0);
    assert.ok(scene.chunks.every((image) => image.destroyed));
    assert.equal(scene.events.listenerCount('shutdown'), 0);
  }
});

test('chunks use final per-camera bounds without overriding visibility or UI filtering', () => {
  const { scene, layer } = render([['forest-floor', 'forest-moss']]);
  const image = scene.chunks[0];
  image.width = 128; image.height = 64;
  const camera = { id: 1, rotation: 0, worldView: { x: 0, y: 0, width: 80, height: 64 } };
  assert.equal(image.willRender(camera), true);
  camera.worldView.x = 200;
  assert.equal(image.willRender(camera), false);
  camera.rotation = 0.5;
  assert.equal(image.willRender(camera), true);
  image.cameraFilter = 1;
  assert.equal(image.willRender(camera), false);
  layer.destroy();
});

test('shorelines blend: ground, water and walls join the group; interior floors stay hard-edged', () => {
  const lookupAuthored = terrainBlendLookup(AUTHORED_TILES);
  assert.ok(lookupAuthored('water').priority < lookupAuthored('forest-floor').priority);
  assert.ok(lookupAuthored('deep-water').priority < lookupAuthored('water').priority);
  assert.equal(lookupAuthored('crystal-wall'), undefined, 'walls are placed objects, not ground tiles');
  assert.equal(lookupAuthored('tree-wall'), undefined, 'walls are placed objects, not ground tiles');
  assert.equal(lookupAuthored('wood-floor'), undefined);
});

test('water and deep water are solid barriers with a shoreline inset', () => {
  for (const tileId of ['water', 'deep-water']) {
    assert.equal(AUTHORED_TILES[tileId].physics?.body, 'static', tileId);
    assert.ok(Object.values(AUTHORED_TILES[tileId].physics.inset).every((inset) => inset > 0 && inset < 32), tileId);
  }
});

test('the blend layer follows the tile layer origin and visibility', () => {
  const { scene, layer } = render([['forest-floor', 'forest-moss']]);
  const image = scene.chunks[0];
  image.setPosition = function (x, y) { this.x = x; this.y = y; return this; };
  image.setVisible = function (visible) { this.visible = visible; return this; };
  layer.setOrigin(100, 40);
  assert.deepEqual([image.x, image.y], [100, 40]);
  layer.setVisible(false);
  assert.equal(image.visible, false);
  layer.destroy();
});

test('all authored worlds plan bounded chunks within a load-time budget', () => {
  const tiles = JSON.parse(fs.readFileSync('src/game/content/scenes/authored/resources/terrain/terrain.tile-set.resource.json', 'utf8')).tiles;
  const worldLookup = (tileId) => (tiles[tileId]?.transition?.group === 'natural-ground'
    ? { material: tiles[tileId].transition.material, priority: tiles[tileId].transition.priority } : undefined);
  for (const file of fs.readdirSync('src/game/content/scenes/authored/worlds').filter((name) => name.endsWith('.scene.json'))) {
    const scene = JSON.parse(fs.readFileSync(`src/game/content/scenes/authored/worlds/${file}`, 'utf8'));
    const data = (scene.subresources ?? []).find((resource) => resource.kind === 'tile-data');
    if (!data) continue;
    const grid = Array.from({ length: data.rows }, () => Array(data.columns).fill('floor'));
    for (const cell of data.cells) grid[cell.y][cell.x] = cell.tileId;
    const started = performance.now();
    const chunks = planTerrainBlendChunks(grid, worldLookup, dimensions(data.columns, data.rows), { seed: 1 });
    assert.ok(performance.now() - started < 2500, `${file} planning is too slow`);
    assert.ok(chunks.every((chunk) => chunk.textureWidth <= 516 && chunk.textureHeight <= 516), file);
    assert.ok(chunks.length <= Math.ceil(data.columns * 64 / 512) * Math.ceil(data.rows * 64 / 512), file);
  }
});

test('sheet-wrap repeats the sheet in order without mirroring', () => {
  assert.deepEqual(resolveSheetWrapFrame(19, 19, 0, 0), { frame: 0, flipX: false, flipY: false });
  assert.deepEqual(resolveSheetWrapFrame(19, 19, 19, 0), { frame: 0, flipX: false, flipY: false });
  assert.deepEqual(resolveSheetWrapFrame(19, 19, 20, 19), { frame: 1, flipX: false, flipY: false });
  assert.deepEqual(resolveSheetWrapFrame(19, 19, -1, -1), { frame: 18 * 19 + 18, flipX: false, flipY: false });
});

test('solid cells merge into few rectangles that cover every cell exactly once', () => {
  const lake = [];
  for (let y = 2; y < 6; y += 1) for (let x = 3; x < 9; x += 1) lake.push({ x, y });
  lake.push({ x: 9, y: 2 }, { x: 20, y: 20 });
  const rectangles = mergeCellRectangles(lake);
  assert.deepEqual(rectangles, [
    { x: 3, y: 2, width: 7, height: 1 }, { x: 3, y: 3, width: 6, height: 3 }, { x: 20, y: 20, width: 1, height: 1 },
  ]);
  const covered = new Set();
  for (const rect of rectangles) for (let y = rect.y; y < rect.y + rect.height; y += 1) for (let x = rect.x; x < rect.x + rect.width; x += 1) {
    assert.ok(!covered.has(`${x},${y}`), 'no overlap');
    covered.add(`${x},${y}`);
  }
  assert.equal(covered.size, lake.length);
  assert.deepEqual(mergeCellRectangles([]), []);
});

test('cave and forest walls are placed objects whose footprints leave no gap the player fits through', () => {
  const player = { width: 30, height: 26 };
  const dir = 'src/game/content/scenes/authored/worlds';
  let walls = 0;
  for (const file of fs.readdirSync(dir).filter((name) => name.endsWith('.scene.json'))) {
    const scene = JSON.parse(fs.readFileSync(`${dir}/${file}`, 'utf8'));
    const data = (scene.subresources ?? []).find((resource) => resource.kind === 'tile-data');
    assert.ok(!data?.cells.some((cell) => cell.tileId === 'crystal-wall' || cell.tileId === 'tree-wall'), `${file} still uses wall tiles`);
    for (const instance of scene.instances ?? []) {
      if (!/^object\.(crystal-cluster-wall|tree-forest-wall)\./.test(instance.sceneId)) continue;
      walls += 1;
      const [family, variant] = instance.sceneId.split('.').slice(1);
      const prop = JSON.parse(fs.readFileSync(`src/game/content/scenes/authored/objects/${family}--${variant}.scene.json`, 'utf8'));
      const shape = prop.subresources.find((resource) => resource.kind === 'collision-shape').value;
      assert.ok(64 - shape.width < player.width && 64 - shape.height < player.height, `${instance.sceneId} footprint leaves a walkable gap`);
      const position = instance.overrides.find((entry) => entry.sourceNodeId === 'body' && entry.property === 'position').value;
      assert.ok(position[0] % 64 === 32 && position[1] % 64 === 54, `${instance.instanceId} body is off the cell grid`);
      const scale = instance.overrides.find((entry) => entry.sourceNodeId === 'visual' && entry.property === 'scale')?.value ?? [1, 1];
      assert.ok(scale[0] > 0 && scale[1] > 0, `${instance.instanceId} must mirror with flipX, not a negative scale`);
    }
  }
  assert.ok(walls >= 250, `expected the converted cave and forest walls, found ${walls}`);
});

test('scene validation rejects non-positive scales, which the runtime cannot mount', async () => {
  const { validateSceneDocument } = await load('src/game/content/scenes/validation.ts');
  const { createCoreDescriptorRegistry } = await load('src/game/content/scenes/propertyDescriptors.ts');
  const registry = createCoreDescriptorRegistry();
  const scene = (scale) => ({
    version: 1, sceneId: 'world.scale-check', rootNodeId: 'world',
    nodes: [{ id: 'world', name: 'World', type: 'Node2D', parentId: null, order: 0, properties: { position: [0, 0] } }],
    instances: [{ instanceId: 'prop-1', name: 'prop-1', sceneId: 'object.crystal-cluster-wall.01', parentNodeId: 'world', order: 0,
      overrides: [{ sourceInstancePath: [], sourceNodeId: 'visual', property: 'scale', value: scale }] }],
  });
  const scaleIssues = (scale) => validateSceneDocument(scene(scale), { registry }).filter((issue) => /scale must be positive/.test(issue.message));
  assert.equal(scaleIssues([-1.1, 1.1]).length, 1);
  assert.equal(scaleIssues([1.1, 0]).length, 1);
  assert.equal(scaleIssues([1.1, 1.1]).length, 0);
});

test('water blocks walkers but projectiles fly over it', () => {
  const layers = JSON.parse(fs.readFileSync('src/game/content/physics/collision-layers.json', 'utf8')).layers;
  const bit = (name) => 2 ** (layers.find((entry) => entry.name === name).layer - 1);
  for (const tileId of ['water', 'deep-water']) assert.equal(AUTHORED_TILES[tileId].physics.layer, 'water', tileId);
  const bodies = (folder) => fs.readdirSync(`src/game/content/scenes/authored/${folder}`).filter((name) => name.endsWith('.scene.json'))
    .flatMap((name) => JSON.parse(fs.readFileSync(`src/game/content/scenes/authored/${folder}/${name}`, 'utf8')).nodes
      .filter((node) => node.type === 'CharacterBody2D').map((node) => [name, node.properties.collisionMask]));
  const walkers = bodies('characters');
  const projectiles = bodies('projectiles');
  assert.ok(walkers.length > 0 && projectiles.length > 0);
  for (const [name, mask] of walkers) assert.ok(mask & bit('water'), `${name} should be blocked by water`);
  for (const [name, mask] of projectiles) assert.ok(!(mask & bit('water')), `${name} should fly over water`);
});
