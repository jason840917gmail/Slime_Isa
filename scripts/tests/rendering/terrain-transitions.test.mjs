import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import { EventEmitter } from 'node:events';
import { build } from 'esbuild';
import { planTerrainTransitionChunks } from '../../../src/game/features/world/TerrainTransitionChunks.ts';

const phaserStub = `
class Image {
  constructor(scene,x,y,key,frame) {
    this.scene=scene; this.x=x; this.y=y; this.visible=true; this.cameraFilter=0;
    scene.allImages.push(this); this.setTexture(key,frame);
  }
  setTexture(key,frame) { this.key=key; this.frame=frame; const size=this.scene.textures.get(key)?.frame;
    this.width=size?.width??64; this.height=size?.height??64; return this; }
  setPosition(x,y) { this.x=x;this.y=y;return this; }
  setOrigin() { return this; }
  setFlip(x,y) { this.flipX=x;this.flipY=y;return this; }
  setAlpha(a) { this.alpha=a;return this; }
  setDepth(d) { this.depth=d;return this; }
  setName(n) { this.name=n;return this; }
  setData(k,v) { (this.data??={})[k]=v;return this; }
  setMask(m) { this.mask=m;return this; }
  clearMask() { this.mask=null;return this; }
  willRender(camera) { return !this.destroyed && this.visible && !(this.cameraFilter & camera.id); }
  destroy() { this.destroyed=true; }
}
export default {GameObjects:{Image},Scenes:{Events:{SHUTDOWN:'shutdown'}},Math:{
  Vector2: class { constructor(x,y){this.x=x;this.y=y;} },
  Clamp:(v,min,max)=>Math.max(min,Math.min(max,v))
}};`;
const bundle = await build({
  entryPoints: ['src/game/features/world/TerrainTransitionRenderer.ts'],
  bundle: true, format: 'esm', platform: 'node', write: false,
  plugins: [{ name: 'terrain-engine-double', setup(api) {
    api.onResolve({ filter: /^phaser$/ }, () => ({ path: 'phaser', namespace: 'stub' }));
    api.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({ contents: phaserStub }));
  } }],
});
const { TerrainTransitionRenderer } = await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`);

const dimensions = (width, height, tileSize = 64) => ({ width, height, tileSize, columns: width / tileSize, rows: height / tileSize });
const command = (x, y, width, height, alpha = 0.16) => ({ tileId: 'forest-moss', tileX: 0, tileY: 0, alpha,
  polygon: [{ x, y }, { x: x + width, y }, { x: x + width, y: y + height }, { x, y: y + height }] });

function makeScene(failAtDraw = Infinity) {
  const textures = new Map();
  const scene = { events: new EventEmitter(), allImages: [], graphics: [], chunks: [], captures: [], drawCount: 0 };
  scene.add = { existing(image) { scene.chunks.push(image); } };
  scene.make = { graphics() {
    const graphic = { destroyed: false,
      clear() { return this; }, fillStyle() { return this; },
      fillPoints(points) { this.points = points; return this; },
      createGeometryMask() { return this.mask = { graphic, destroy() { this.destroyed = true; } }; },
      destroy() { this.destroyed = true; },
    };
    scene.graphics.push(graphic); return graphic;
  } };
  scene.textures = {
    exists: (key) => textures.has(key), get: (key) => textures.get(key),
    addDynamicTexture(key, width, height) {
      const texture = { width: width + width % 2, height: height + height % 2, commands: [],
        camera: { setScroll(x,y) { texture.scroll = { x, y }; } },
        clear() {}, beginDraw() { this.open = true; }, endDraw() { this.open = false; },
        batchDraw(image) {
          if (++scene.drawCount === failAtDraw) throw new Error('simulated GPU failure');
          this.commands.push({ x: image.x, y: image.y, key: image.key, frame: image.frame,
            flipX: image.flipX, flipY: image.flipY, alpha: image.alpha,
            polygon: image.mask.graphic.points.map((point) => ({ ...point })) });
        },
        add(name, source, x, y, width, height) { this.frame = { name, source, x, y, width, height }; },
      };
      textures.set(key, texture); scene.captures.push(texture); return texture;
    },
    remove(key) {
      assert.ok(scene.chunks.filter((image) => image.key === key).every((image) => image.destroyed));
      textures.delete(key);
    },
  };
  scene.textureCount = () => textures.size;
  return scene;
}
const tileFactory = { resolveVisual(tileId, x, y) {
  return { textureKey: tileId, frame: x + y, flipX: x % 2 === 1, flipY: y % 2 === 1 };
} };
function render(grid, scene = makeScene(), tileSize = 64, seed = 42) {
  const layer = new TerrainTransitionRenderer({ scene, tileFactory, seed,
    dimensions: dimensions(grid[0].length * tileSize, grid.length * tileSize, tileSize),
  }).render(grid);
  return { scene, layer };
}

test('chunk gutters include neighboring artwork and retain global blend order', () => {
  const commands = [command(500, 20, 10, 20), command(512, 20, 8, 20, 0.72)];
  const chunks = planTerrainTransitionChunks(commands, dimensions(1024, 64));
  assert.equal(chunks.length, 2);
  for (const chunk of chunks) assert.deepEqual(chunk.commands, commands);
});

test('nonstandard tiles crossing chunks and odd rectangular edges retain exact world bounds', () => {
  const chunks = planTerrainTransitionChunks([command(500, 500, 137, 89)], dimensions(637, 589, 1));
  assert.deepEqual(chunks.map(({ x,y,width,height }) => [x,y,width,height]), [
    [0,0,512,512], [512,0,125,512], [0,512,512,77], [512,512,125,77],
  ]);
  assert.deepEqual(planTerrainTransitionChunks([], dimensions(1, 1, 1)), []);
});

test('same-material, water, and single-cell maps allocate no transition textures', () => {
  for (const grid of [[['grass-a','grass-b']], [['water','forest-floor']], [['forest-floor']]]) {
    const { scene, layer } = render(grid);
    assert.equal(scene.textureCount(), 0);
    assert.equal(scene.allImages.length, 0);
    layer.destroy();
    assert.equal(scene.events.listenerCount('shutdown'), 0);
  }
});

test('overlapping edges preserve band-major order, seeded polygons, source frames and flips', () => {
  const grid = [['forest-moss','forest-floor'],['forest-floor','forest-moss']];
  const a = render(grid), b = render(grid);
  const draws = a.scene.captures[0].commands;
  assert.equal(draws.length, 12);
  assert.deepEqual(draws.map((draw) => draw.alpha), [...Array(4).fill(0.16), ...Array(4).fill(0.28), ...Array(4).fill(0.72)]);
  assert.ok(draws.every((draw) => draw.key === 'forest-moss'));
  assert.deepEqual(draws, b.scene.captures[0].commands);
  assert.deepEqual(draws.slice(0,4).map(({ x,y,frame,flipX,flipY }) => [x,y,frame,flipX,flipY]), [
    [64,0,1,true,false], [0,64,1,false,true], [64,0,1,true,false], [0,64,1,false,true],
  ]);
  a.layer.destroy(); b.layer.destroy();
});

test('baking owns detached scratch objects and releases textures on rebuild/shutdown', () => {
  const scene = makeScene();
  const a = render([['forest-floor','forest-moss']], scene);
  const keys = scene.chunks.map((image) => image.key);
  assert.ok(scene.chunks.every((image) => !image.mask));
  assert.ok(scene.allImages.filter((image) => !scene.chunks.includes(image)).every((image) => image.destroyed));
  assert.ok(scene.graphics.every((graphic) => graphic.destroyed && graphic.mask.destroyed));
  a.layer.destroy(); a.layer.destroy();
  assert.equal(scene.textureCount(), 0);
  assert.equal(scene.events.listenerCount('shutdown'), 0);
  render([['forest-floor','forest-moss']], scene);
  assert.ok(!keys.includes(scene.chunks.at(-1).key));
  scene.events.emit('shutdown');
  assert.equal(scene.textureCount(), 0);
});

test('a failed bake closes the batch and releases all partially created resources', () => {
  const grid = [Array.from({ length: 20 }, (_, x) => x % 2 ? 'forest-moss' : 'forest-floor')];
  for (const draw of [5, 30]) {
    const scene = makeScene(draw);
    assert.throws(() => render(grid, scene), /simulated GPU failure/);
    if (draw === 30) assert.ok(scene.chunks.length > 0, 'failure follows a completed chunk');
    assert.equal(scene.textureCount(), 0);
    assert.equal(scene.events.listenerCount('shutdown'), 0);
    assert.ok(scene.captures.every((texture) => !texture.open));
    assert.ok(scene.allImages.every((image) => image.destroyed));
    assert.ok(scene.graphics.every((graphic) => graphic.destroyed && graphic.mask.destroyed));
  }
});

test('scratch allocation failure releases earlier scratch objects and the shutdown listener', () => {
  const scene = makeScene();
  scene.make.graphics = () => { throw new Error('graphics allocation failure'); };
  assert.throws(() => render([['forest-floor','forest-moss']], scene), /graphics allocation failure/);
  assert.ok(scene.allImages.every((image) => image.destroyed));
  assert.equal(scene.events.listenerCount('shutdown'), 0);
});

test('equal-priority materials retain the original stable material tie break', () => {
  const { scene, layer } = render([['cavern-floor','forest-floor']]);
  assert.ok(scene.captures[0].commands.every((draw) => draw.key === 'forest-floor' && draw.x === 0));
  layer.destroy();
});

test('chunks use final per-camera bounds without overriding visibility or UI filtering', () => {
  const { scene, layer } = render([['forest-floor','forest-moss']]);
  const image = scene.chunks[0];
  const camera = { id: 1, rotation: 0, worldView: { x: 0, y: 0, width: 80, height: 64 } };
  assert.equal(image.willRender(camera), true);
  camera.worldView.x = 200;
  assert.equal(image.willRender(camera), false);
  camera.rotation = 0.5;
  assert.equal(image.willRender(camera), true);
  image.cameraFilter = 1;
  assert.equal(image.willRender(camera), false);
  image.cameraFilter = 0; image.visible = false;
  assert.equal(image.willRender(camera), false);
  layer.destroy();
});

test('all authored maps use bounded chunks with no retained terrain masks', () => {
  for (const file of fs.readdirSync('src/game/content/maps').filter((name) => name.endsWith('.map.json'))) {
    const map = JSON.parse(fs.readFileSync(`src/game/content/maps/${file}`, 'utf8'));
    const source = map.layers.at(-1);
    const grid = source.rows.map((row) => [...row].map((symbol) => source.legend[symbol]));
    const { scene, layer } = render(grid, makeScene(), map.tileSize);
    assert.ok(scene.captures.every((texture) => texture.width <= 516 && texture.height <= 516), file);
    assert.ok(scene.captures.every((texture) => texture.frame.x === 2 && texture.frame.y === 2), file);
    assert.ok(scene.chunks.every((image) => !image.mask), file);
    if (file === 'gloop-forest.map.json' || file === 'crystal-caverns.map.json') {
      assert.ok(scene.chunks.length > 0 && scene.chunks.length <= 49, file);
    }
    layer.destroy();
    assert.equal(scene.textureCount(), 0, file);
  }
});
