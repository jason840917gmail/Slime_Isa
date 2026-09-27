import assert from 'node:assert/strict';
import { mkdtemp, readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { ConversionRunner } from '../../lib/scene-conversion/ConversionRunner.mjs';
import { objectSceneAdapter } from '../../lib/scene-conversion/objects.mjs';
import { validateSceneWriteSet } from '../../lib/scene-conversion/validate-scene-write-set.mjs';

const repositoryRoot = fileURLToPath(new URL('../../..', import.meta.url));
const collectibleUnitKeys = [
  'object:collectible.charcoal-pile',
  'object:collectible.crystal-shard',
  'object:collectible.energy-potion',
  'object:collectible.green-key',
  'object:collectible.hp-potion',
  'object:collectible.iron-ore-pile',
  'object:collectible.purple-berry',
  'object:collectible.silk-clump',
  'object:collectible.small-stone-pile',
  'object:collectible.small-wood-pile',
  'object:collectible.stone-pile',
  'object:collectible.wood-pile',
];
const passiveUnitKeys = [
  'object:decoration.world.floor',
  'object:decoration.world.solid',
  'object:house.world.solid',
  'object:rock.world-wall.decorative',
  'object:rock.world-wall.solid',
  'object:wall.stone.solid',
];
const unitKeys = ['object:resource.stone-node', 'object:tree.world.solid', 'object:rock.amber-ore.mineable', ...collectibleUnitKeys, ...passiveUnitKeys];

async function createRunner() {
  const productionLedger = JSON.parse(await readFile(path.join(repositoryRoot, 'scripts/migrations/universal-scene-conversion-ledger.json'), 'utf8'));
  const selected = new Set(unitKeys);
  const ledger = { ...productionLedger, rows: productionLedger.rows.map((row) => selected.has(row.key) ? { ...row, writerState: 'legacy' } : row) };
  const manifest = JSON.parse(await readFile(path.join(repositoryRoot, 'asset/assets.json'), 'utf8'));
  return new ConversionRunner({
    repositoryRoot,
    ledger,
    adapters: { object: objectSceneAdapter },
    outputRoot: await mkdtemp(path.join(os.tmpdir(), 'object-scene-conversion-')),
    validateWriteSet: (outputs) => validateSceneWriteSet(outputs, { hasAsset: (assetId) => Object.hasOwn(manifest.assets, assetId) }),
  });
}

test('resource object conversion is deterministic and emits every stone and tree visual variant', async () => {
  const runner = await createRunner();
  const first = await runner.run({ unitKeys, mode: 'dry-run' });
  const replay = await runner.run({ unitKeys: [...unitKeys].reverse(), mode: 'dry-run' });
  assert.deepEqual(replay.outputs, first.outputs);
  assert.equal(first.outputs.length, 174);
  assert.ok(first.outputs.some((output) => output.path === 'objects/resource-stone-node.scene.json'));
  assert.ok(first.outputs.some((output) => output.path === 'objects/tree-world-solid.scene.json'));
  assert.ok(first.outputs.some((output) => output.path === 'objects/tree-world-solid--tree-autumn-01.scene.json'));
});

test('mineable amber ore preserves durability and resolves item drops to a collectible scene', async () => {
  const runner = await createRunner();
  await runner.run({ unitKeys, mode: 'apply' });
  await runner.run({ unitKeys, mode: 'check' });
  const converted = JSON.parse(await readFile(path.join(runner.outputRoot, 'objects/rock-amber-ore-mineable.scene.json'), 'utf8'));
  const authored = JSON.parse(await readFile(path.join(repositoryRoot, 'src/game/content/scenes/authored/objects/rock-amber-ore-mineable.scene.json'), 'utf8'));
  const script = converted.nodes.find((node) => node.scriptId === 'game.resource-node');

  assert.equal(converted.sceneId, 'object.rock-amber-ore-mineable');
  assert.equal(script.properties.maxHealth, 30);
  assert.deepEqual(script.properties.tags, ['rock', 'solid', 'mineable']);
  assert.deepEqual(script.properties.drop, {
    objectId: 'collectible.crystal-shard', visualId: 'crystal-shard', pieces: 1,
  });
  assert.equal(script.properties.persistHealth, true);
  assert.deepEqual(authored, converted);
});

test('passive object scenes preserve collision, occlusion, offsets, and decorative walkability', async () => {
  const runner = await createRunner();
  await runner.run({ unitKeys, mode: 'apply' });
  await runner.run({ unitKeys, mode: 'check' });
  const load = async (relativePath) => JSON.parse(await readFile(path.join(runner.outputRoot, relativePath), 'utf8'));
  const house = await load('objects/house-world-solid.scene.json');
  const corner = await load('objects/wall-stone-solid--corner-01.scene.json');
  const floor = await load('objects/decoration-world-floor.scene.json');

  assert.equal(house.sceneId, 'object.house-world-solid');
  assert.equal(house.nodes[0].type, 'StaticBody2D');
  assert.deepEqual(house.nodes.find((node) => node.id === 'visual').properties.occlusionBounds, {
    width: 300, height: 160, offsetX: 10, offsetY: 10,
  });
  // Legacy collider offsets were the body's top-left from the frame's top-left; scenes store the shape centre.
  assert.deepEqual(corner.nodes.find((node) => node.id === 'body-shape').properties.position, [5.5, -32]);
  assert.deepEqual(corner.subresources.find((resource) => resource.kind === 'collision-shape').value, {
    shape: 'rectangle', width: 47, height: 60,
  });
  assert.equal(floor.nodes[0].type, 'Node2D');
  assert.equal(floor.nodes.some((node) => node.type === 'CollisionShape2D'), false);
  assert.equal(floor.subresources.some((resource) => resource.kind === 'collision-shape'), false);
});

test('collectible scenes preserve inventory identity, visuals, and isolated pickup collision', async () => {
  const runner = await createRunner();
  await runner.run({ unitKeys, mode: 'apply' });
  await runner.run({ unitKeys, mode: 'check' });
  const load = async (relativePath) => JSON.parse(await readFile(path.join(runner.outputRoot, relativePath), 'utf8'));
  const wood = await load('objects/collectible-wood-pile.scene.json');
  const potion = await load('objects/collectible-hp-potion.scene.json');

  assert.equal(wood.sceneId, 'object.collectible-wood-pile');
  assert.equal(wood.nodes.find((node) => node.id === 'visual').properties.texture.resourceId, 'collectible-wood-pile.wood-pile.sprite');
  assert.deepEqual(wood.nodes.find((node) => node.id === 'pickup-area').properties, {
    collisionLayer: 64, collisionMask: 32, monitoring: false, monitorable: true,
  });
  assert.equal(wood.connections, undefined);
  const woodScript = wood.nodes.find((node) => node.scriptId === 'game.collectible');
  assert.equal(woodScript.properties.itemId, 'wood');
  assert.equal(woodScript.properties.quantity, 10);
  assert.equal(potion.subresources.find((resource) => resource.kind === 'texture').assetId, 'collectible.hp-potion');
  assert.equal(potion.nodes.find((node) => node.scriptId === 'game.collectible').properties.itemId, 'hp-potion');

  for (const unitKey of collectibleUnitKeys) {
    const objectId = unitKey.slice('object:'.length);
    const relativePath = `${objectId.replaceAll('.', '-')}.scene.json`;
    assert.deepEqual(
      JSON.parse(await readFile(path.join(repositoryRoot, 'src/game/content/scenes/authored/objects', relativePath), 'utf8')),
      await load(`objects/${relativePath}`),
    );
  }
});

test('stone resource scenes preserve visual, collision, harvest, drop, and script data', async () => {
  const runner = await createRunner();
  await runner.run({ unitKeys, mode: 'apply' });
  await runner.run({ unitKeys, mode: 'check' });
  const load = async (relativePath) => JSON.parse(await readFile(path.join(runner.outputRoot, relativePath), 'utf8'));
  const base = await load('objects/resource-stone-node.scene.json');
  const alternate = await load('objects/resource-stone-node--big-stone-mine.scene.json');

  assert.equal(base.sceneId, 'object.resource-stone-node');
  assert.equal(alternate.sceneId, 'object.resource-stone-node.big-stone-mine');
  assert.equal(base.nodes.find((node) => node.id === 'visual').properties.frame, 1);
  assert.equal(base.nodes.find((node) => node.id === 'damage-area').properties.collisionLayer, 8);
  assert.equal(base.nodes.find((node) => node.id === 'damage-shape').properties.shape.resourceId, 'resource-stone-node.stone-node.shape');
  const script = base.nodes.find((node) => node.scriptId === 'game.resource-node');
  assert.equal(script.properties.maxHealth, 80);
  assert.deepEqual(script.properties.drop, { objectId: 'collectible.stone-pile', visualId: 'stone-pile', pieces: 3 });
  assert.deepEqual(script.properties.harvestRequirement, { targetTag: 'stone', minimumTier: 1, failureMessage: 'Requires a Pickaxe' });
  assert.equal(script.properties.persistHealth, false);

  for (const relativePath of ['resource-stone-node.scene.json', 'resource-stone-node--big-stone-mine.scene.json']) {
    assert.deepEqual(
      JSON.parse(await readFile(path.join(repositoryRoot, 'src/game/content/scenes/authored/objects', relativePath), 'utf8')),
      await load(`objects/${relativePath}`),
    );
  }
});

test('tree resource scenes preserve occlusion, animation, durability, harvest, and drops', async () => {
  const runner = await createRunner();
  await runner.run({ unitKeys, mode: 'apply' });
  await runner.run({ unitKeys, mode: 'check' });
  const load = async (relativePath) => JSON.parse(await readFile(path.join(runner.outputRoot, relativePath), 'utf8'));
  const staticTree = await load('objects/tree-world-solid.scene.json');
  const animatedTree = await load('objects/tree-world-solid--tree-autumn-01.scene.json');

  assert.equal(staticTree.sceneId, 'object.tree-world-solid');
  assert.deepEqual(staticTree.nodes.find((node) => node.id === 'visual').properties.occlusionBounds, {
    width: 110, height: 130, offsetX: 8, offsetY: 0,
  });
  const script = animatedTree.nodes.find((node) => node.scriptId === 'game.resource-node');
  assert.equal(script.properties.maxHealth, 40);
  assert.deepEqual(script.properties.tags, ['wood', 'resource', 'tree', 'solid']);
  assert.deepEqual(script.properties.drop, { objectId: 'collectible.wood-pile', visualId: 'wood-pile', pieces: 1 });
  assert.deepEqual(script.properties.harvestRequirement, { targetTag: 'wood', minimumTier: 1, failureMessage: 'Requires an Axe' });
  assert.equal(script.properties.idleAnimationId, 'object.tree.autumn.idle');
  assert.equal(script.properties.onHitAnimationId, 'object.tree.autumn.leaf-fall');
  assert.deepEqual(script.properties.animation, { nodeId: 'animation' });
  const animation = animatedTree.nodes.find((node) => node.id === 'animation');
  assert.equal(animation.properties.autoplay, 'object.tree.autumn.idle');
  const library = animatedTree.subresources.find((resource) => resource.kind === 'animation-library');
  assert.ok(library.animations['object.tree.autumn.idle']);
  assert.ok(library.animations['object.tree.autumn.leaf-fall']);
  assert.deepEqual(
    library.animations['object.tree.autumn.leaf-fall'].tracks.find((track) => track.property === 'visualOffset').keys[1],
    { at: 1, value: [2.5, 6] },
  );
});
