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

const { CollectibleController } = await vite.ssrLoadModule('/src/game/features/collectibles/CollectibleController.ts');
const { CollectibleEventChannel } = await vite.ssrLoadModule('/src/game/features/collectibles/CollectibleEventChannel.ts');
const { CollectibleReactionController } = await vite.ssrLoadModule('/src/game/features/collectibles/CollectibleReactionController.ts');
const { WorldDropSpawner } = await vite.ssrLoadModule('/src/game/features/collectibles/WorldDropSpawner.ts');
const {
  resolveWorldDropArcHeight,
  resolveWorldDropTrajectory,
  WORLD_DROP_FLIGHT_MS,
  WORLD_DROP_REBOUND_MS,
  WORLD_DROP_SETTLE_MS,
  WORLD_DROP_STAGGER_MS,
} = await vite.ssrLoadModule('/src/game/features/collectibles/WorldDropMotion.ts');
const { completeDropPlacements } = await vite.ssrLoadModule('/src/game/features/resources/ResourceDropPlacement.ts');

test.after(async () => vite.close());

function harness(capacities, savedState) {
  const children = [];
  const persisted = new Map();
  const messages = [];
  const published = [];
  const handlers = new Set();
  const image = {
    active: true,
    x: 120,
    y: 160,
    data: new Map(),
    setData(key, value) { this.data.set(key, value); return this; },
    destroy() { this.active = false; },
  };
  const group = {
    getChildren: () => children,
    add(value) { children.push(value); },
    remove(value, _remove, destroy) {
      const index = children.indexOf(value);
      if (index >= 0) children.splice(index, 1);
      if (destroy) value.destroy();
    },
  };
  const progress = {
    collectibleState: () => savedState,
    setCollectibleState(_mapId, instanceId, state) { persisted.set(instanceId, state); },
  };
  const eventBus = {
    emit(event, payload) {
      published.push({ event, payload, imageActive: image.active });
      for (const handler of handlers) handler(payload);
    },
    on(_event, handler) { handlers.add(handler); },
    off(_event, handler) { handlers.delete(handler); },
  };
  const events = new CollectibleEventChannel(eventBus);
  const controller = new CollectibleController({
    scene: { time: { now: 10_000 } },
    mapId: 'level-1',
    group,
    inventory: { add: (_itemId, requested) => Math.min(requested, capacities.shift() ?? 0) },
    progress,
    publisher: events,
    showMessage: (...message) => messages.push(message),
  });
  controller.register({ image, objectId: 'collectible.wood-pile', instanceId: 'wood-01' });
  return { controller, image, persisted, messages, published };
}

test('walk-over transfer handles full pickup and exact-once depletion', () => {
  const state = harness([10, 10]);
  state.controller.collect(state.image);
  state.controller.collect(state.image);
  assert.equal(state.image.active, false);
  assert.equal(state.persisted.get('wood-01').remaining, 0);
  assert.equal(state.published.length, 1);
  assert.deepEqual(state.published[0], {
    event: 'collectible.collected',
    imageActive: false,
    payload: {
      mapId: 'level-1', instanceId: 'wood-01', objectId: 'collectible.wood-pile', itemId: 'wood', quantity: 10,
    },
  });
});

test('walk-over transfer preserves partial and zero-capacity quantities', () => {
  const state = harness([0, 4, 6]);
  state.controller.collect(state.image);
  assert.equal(state.persisted.size, 0);
  assert.equal(state.published.length, 0);
  assert.equal(state.messages.at(-1)[2], 'Inventory full');
  state.controller.collect(state.image);
  assert.equal(state.persisted.get('wood-01').remaining, 6);
  assert.equal(state.image.active, true);
  assert.equal(state.published.length, 1);
  assert.equal(state.published[0].event, 'collectible.collected');
  assert.equal(state.published[0].payload.quantity, 4);
  assert.equal(state.published[0].imageActive, true);
  state.controller.collect(state.image);
  assert.equal(state.persisted.get('wood-01').remaining, 0);
  assert.equal(state.image.active, false);
  assert.equal(state.published.length, 2);
  assert.equal(state.published[1].event, 'collectible.collected');
  assert.equal(state.published[1].payload.quantity, 6);
  assert.equal(state.published[1].imageActive, false);
});

test('berry reactions consume the event once and unsubscribe on disposal', () => {
  const handlers = new Set();
  const eventBus = {
    emit(_event, payload) { for (const handler of handlers) handler(payload); },
    on(_event, handler) { handlers.add(handler); },
    off(_event, handler) { handlers.delete(handler); },
  };
  const events = new CollectibleEventChannel(eventBus);
  const reactions = [];
  const controller = new CollectibleReactionController({
    events,
    awardCoins: (amount) => reactions.push(['coins', amount]),
    playEatAnimation: () => reactions.push(['animation']),
    flashCoins: () => reactions.push(['flash']),
  });

  events.publishCollected({
    mapId: 'level-1', instanceId: 'berry-01', objectId: 'collectible.purple-berry', itemId: 'purple-berry-mat', quantity: 2,
  });
  assert.deepEqual(reactions, [['animation'], ['coins', 10], ['flash']]);

  events.publishCollected({
    mapId: 'level-1', instanceId: 'wood-01', objectId: 'collectible.wood-pile', itemId: 'wood', quantity: 10,
  });
  assert.equal(reactions.length, 3);

  controller.dispose();
  assert.equal(handlers.size, 0);
  events.publishCollected({
    mapId: 'level-1', instanceId: 'berry-02', objectId: 'collectible.purple-berry', itemId: 'purple-berry-mat', quantity: 1,
  });
  assert.equal(reactions.length, 3);
});

test('fallback resource drops use stable distinct offsets', () => {
  const placements = completeDropPlacements([], { cellX: 4, cellY: 7 }, 6, 64);
  assert.equal(placements.length, 6);
  assert.equal(new Set(placements.map((entry) => `${entry.cellX}:${entry.cellY}:${entry.offsetX}:${entry.offsetY}`)).size, 6);
  assert.deepEqual(placements, completeDropPlacements([], { cellX: 4, cellY: 7 }, 6, 64));
});

function worldDropHarness({ throwOnTween = false } = {}) {
  const created = [];
  const registered = [];
  const anchors = [];
  const depthModes = [];
  const tweenEntries = [];
  const image = {
    active: true,
    x: 0,
    y: 0,
    depth: 1234,
    scaleX: 0.6,
    scaleY: 0.75,
    body: { enable: true },
    setScale(x, y = x) { this.scaleX = x; this.scaleY = y; return this; },
    destroy() { this.active = false; },
  };
  const scene = {
    tweens: {
      add(config) {
        if (throwOnTween) throw new Error('tween setup failed');
        const tween = {
          removed: false,
          remove() { this.removed = true; },
        };
        tweenEntries.push({ config, tween });
        return tween;
      },
    },
  };
  const spawner = new WorldDropSpawner({
    scene,
    createObject(objectId, options) {
      created.push({ objectId, options });
      image.x = options.x;
      image.y = options.y;
      return image;
    },
    setObjectAnchor(target, x, y) {
      target.x = x;
      target.y = y;
      anchors.push({ x, y });
    },
    setObjectDepthMode(_target, mode, depth) { depthModes.push({ mode, depth }); },
    registerCollectible(registration) { registered.push(registration); },
  });
  return { spawner, image, created, registered, anchors, depthModes, tweenEntries };
}

function worldDropRequest(overrides = {}) {
  return {
    mode: 'launch',
    source: { x: 100, y: 140 },
    destination: { x: 180, y: 200 },
    launchIndex: 1,
    drop: {
      objectId: 'collectible.wood-pile',
      visualId: 'wood-pile',
      instanceId: 'tree-01-drop-1',
      initialState: { remaining: 10, sourceResourceInstanceId: 'tree-01' },
    },
    ...overrides,
  };
}

function updateTween(entry, progress) {
  entry.config.targets.progress = progress;
  entry.config.onUpdate?.();
}

function finishTween(entry) {
  updateTween(entry, 1);
  entry.config.onComplete?.();
}

test('world drop trajectory is deterministic, clamped, and supports an in-place hop', () => {
  const source = { x: 10, y: 20 };
  const destination = { x: 110, y: 20 };
  assert.deepEqual(resolveWorldDropTrajectory(source, destination, 0), source);
  assert.deepEqual(resolveWorldDropTrajectory(source, destination, 1), destination);
  assert.deepEqual(resolveWorldDropTrajectory(source, destination, 0.5), { x: 60, y: -25 });
  assert.equal(resolveWorldDropArcHeight(source, destination), 45);
  assert.equal(resolveWorldDropArcHeight(source, { x: 10, y: 20 }), 28);
  assert.equal(resolveWorldDropArcHeight(source, { x: 1010, y: 20 }), 56);
  assert.deepEqual(resolveWorldDropTrajectory(source, source, 0.5), { x: 10, y: -8 });
});

test('settled world drops register immediately without creating motion', () => {
  const state = worldDropHarness();
  state.spawner.spawn({
    mode: 'settled',
    destination: { x: 240, y: 320 },
    drop: {
      objectId: 'collectible.stone-pile',
      visualId: 'stone-pile',
      instanceId: 'stone-01-drop-1',
    },
  });
  assert.equal(state.created.length, 1);
  assert.equal(state.registered.length, 1);
  assert.equal(state.image.body.enable, true);
  assert.equal(state.tweenEntries.length, 0);
});

test('launched world drops stay disabled through flight and activate after landing settle', () => {
  const state = worldDropHarness();
  state.spawner.spawn(worldDropRequest());

  assert.equal(state.image.body.enable, false);
  assert.equal(state.registered.length, 0);
  assert.deepEqual(state.anchors.at(-1), { x: 100, y: 140 });
  assert.equal(state.tweenEntries[0].config.delay, WORLD_DROP_STAGGER_MS);
  assert.equal(state.tweenEntries[0].config.duration, WORLD_DROP_FLIGHT_MS);

  updateTween(state.tweenEntries[0], 0.5);
  assert.equal(state.image.x, 140);
  assert.ok(state.image.y < 140);

  finishTween(state.tweenEntries[0]);
  assert.equal(state.tweenEntries[1].config.duration, WORLD_DROP_REBOUND_MS);
  assert.equal(state.image.body.enable, false);
  finishTween(state.tweenEntries[1]);
  assert.equal(state.tweenEntries[2].config.duration, WORLD_DROP_SETTLE_MS);
  assert.equal(state.image.body.enable, false);
  finishTween(state.tweenEntries[2]);

  assert.equal(state.registered.length, 1);
  assert.equal(state.image.body.enable, true);
  assert.deepEqual({ x: state.image.x, y: state.image.y }, { x: 180, y: 200 });
  assert.deepEqual({ x: state.image.scaleX, y: state.image.scaleY }, { x: 0.6, y: 0.75 });
  assert.deepEqual(state.depthModes, [
    { mode: 'explicit', depth: 1234 },
    { mode: 'world-sorted', depth: undefined },
  ]);

  state.tweenEntries[2].config.onComplete?.();
  assert.equal(state.registered.length, 1);
});

test('world drop validation fails before object creation', () => {
  const state = worldDropHarness();
  assert.throws(
    () => state.spawner.spawn(worldDropRequest({ launchIndex: -1 })),
    /zero-based non-negative integer/,
  );
  assert.throws(
    () => state.spawner.spawn(worldDropRequest({
      drop: { objectId: 'tree.world.solid', visualId: 'tree', instanceId: 'invalid' },
    })),
    /walk-over collectible/,
  );
  assert.throws(
    () => state.spawner.spawn(worldDropRequest({
      destination: { x: Number.NaN, y: 10 },
    })),
    /finite coordinates/,
  );
  assert.equal(state.created.length, 0);
});

test('world drop motion failure settles safely and teardown cancels delayed launches', () => {
  const fallback = worldDropHarness({ throwOnTween: true });
  fallback.spawner.spawn(worldDropRequest());
  assert.equal(fallback.registered.length, 1);
  assert.equal(fallback.image.body.enable, true);
  assert.deepEqual({ x: fallback.image.x, y: fallback.image.y }, { x: 180, y: 200 });

  const delayed = worldDropHarness();
  delayed.spawner.spawn(worldDropRequest({ launchIndex: 4 }));
  delayed.spawner.destroy();
  delayed.spawner.destroy();
  assert.equal(delayed.tweenEntries[0].tween.removed, true);
  assert.equal(delayed.image.active, false);
  assert.equal(delayed.registered.length, 0);
  assert.throws(() => delayed.spawner.spawn(worldDropRequest()), /after destroy/);
});
