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
    },
  },
  optimizeDeps: { noDiscovery: true },
  server: { middlewareMode: true, hmr: false },
});

const { CollectibleController } = await vite.ssrLoadModule('/src/game/features/collectibles/CollectibleController.ts');
const { CollectibleEventChannel } = await vite.ssrLoadModule('/src/game/features/collectibles/CollectibleEventChannel.ts');
const { CollectibleReactionController } = await vite.ssrLoadModule('/src/game/features/collectibles/CollectibleReactionController.ts');
const { InventoryDropController } = await vite.ssrLoadModule('/src/game/features/collectibles/InventoryDropController.ts');
const { findInventoryDropDestination } = await vite.ssrLoadModule('/src/game/features/collectibles/InventoryDropPlacement.ts');
const { resolveInventoryDropDefinition } = await vite.ssrLoadModule('/src/game/content/items/InventoryDropCatalog.ts');
const { getBaseItemDefinitions } = await vite.ssrLoadModule('/src/game/content/items/ItemCatalog.ts');
const {
  resolveWorldDropArcHeight,
  resolveWorldDropTrajectory,
} = await vite.ssrLoadModule('/src/game/features/collectibles/WorldDropMotion.ts');
const { completeDropPlacements } = await vite.ssrLoadModule('/src/game/features/resources/ResourceDropPlacement.ts');

test.after(async () => vite.close());

test('managed scene pickup publishes committed transaction feedback and remaining state', () => {
  let state;
  const messages = [];
  const published = [];
  const changes = [];
  const controller = new CollectibleController({
    scene: { time: { now: 10_000 } },
    mapId: 'level-1',
    group: { getChildren: () => [] },
    inventory: { add: () => 0 },
    transaction: {
      collectWorldItem: (input) => {
        const moved = Math.min(3, input.remaining, input.requested);
        state = { remaining: input.remaining - moved };
        return moved;
      },
    },
    progress: {
      collectibleState: () => state,
      setCollectibleState: () => {},
    },
    publisher: { publishCollected: (payload) => published.push(payload) },
    showMessage: (...message) => messages.push(message),
    onStateChanged: (change) => changes.push(change),
  });
  controller.ensureInitialized('level-1', 'wood-01', 5);
  assert.equal(controller.remaining('level-1', 'wood-01'), 5);
  const request = {
    mapId: 'level-1', instanceId: 'wood-01', objectId: 'collectible.wood-pile', itemId: 'wood',
    requested: 5, collectorAreaNodeId: 'managed-player/PickupArea', x: 120, y: 160,
  };
  assert.deepEqual(controller.pickup(request), { status: 'partial', moved: 3, remaining: 2 });
  assert.deepEqual(changes, [{ instanceId: 'wood-01', remaining: 2 }]);
  assert.equal(messages[0][2], '+3 wood');
  assert.deepEqual(published[0], {
    mapId: 'level-1', instanceId: 'wood-01', objectId: 'collectible.wood-pile', itemId: 'wood', quantity: 3,
  });
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

function inventoryDropProgress(initial = [], nextSequence = 1) {
  const records = new Map(initial.map((record) => [record.id, { ...record }]));
  let sequence = nextSequence;
  return {
    inventoryDrops: () => [...records.values()].map((record) => ({ ...record })),
    createInventoryDrop(_mapId, drop) {
      const record = { ...drop, id: `inventory-drop-${sequence}` };
      sequence += 1;
      records.set(record.id, record);
      return { ...record };
    },
    setInventoryDropAmount(_mapId, instanceId, amount) {
      const record = records.get(instanceId);
      if (!record) return;
      if (amount > 0) records.set(instanceId, { ...record, amount });
      else records.delete(instanceId);
    },
  };
}

function inventoryDropHarness({ blocked = false, throwOnSpawn = false, throwOnPersist = false } = {}) {
  const progress = inventoryDropProgress();
  if (throwOnPersist) progress.createInventoryDrop = () => { throw new Error('persist failed'); };
  const slots = [{ itemId: 'wood', count: 12 }];
  const requests = [];
  const messages = [];
  const inventory = {
    getSlots: () => slots,
    removeFromSlot(index, count) {
      const slot = slots[index];
      if (!slot) return 0;
      const removed = Math.min(slot.count, count);
      slot.count -= removed;
      if (slot.count === 0) slots.splice(index, 1);
      return removed;
    },
    add(itemId, count) {
      const slot = slots.find((entry) => entry.itemId === itemId);
      if (slot) slot.count += count;
      else slots.push({ itemId, count });
      return count;
    },
  };
  const controller = new InventoryDropController({
    mapId: 'level-1',
    dimensions: { tileSize: 64, columns: 20, rows: 20, width: 1280, height: 1280 },
    inventory,
    getPlayerAnchor: () => ({ x: 160, y: 192 }),
    getFacing: () => 'right',
    inspectCell: () => ({ kind: blocked ? 'blocked' : 'open' }),
    spawnWorldDrop(request) {
      if (throwOnSpawn) throw new Error('spawn failed');
      requests.push(request);
      return { active: true };
    },
    showMessage: (message) => messages.push(message),
    progress,
  });
  return { controller, slots, requests, messages, progress };
}

test('every current non-equipment item has an explicit valid world-drop presentation', () => {
  const stackableItems = Object.values(getBaseItemDefinitions()).filter((item) => !item.equipment);
  assert.ok(stackableItems.length > 0);
  for (const item of stackableItems) {
    assert.ok(resolveInventoryDropDefinition(item.id), `missing world drop for ${item.id}`);
  }
  assert.equal(resolveInventoryDropDefinition('wooden-axe'), undefined);
});

test('inventory drop placement searches outward, favors facing, and accepts compatible stacks', () => {
  const dimensions = { tileSize: 64, columns: 20, rows: 20, width: 1280, height: 1280 };
  assert.deepEqual(
    findInventoryDropDestination({ x: 160, y: 192 }, 'right', dimensions, () => ({ kind: 'open' })),
    { x: 288, y: 192 },
  );
  assert.deepEqual(
    findInventoryDropDestination(
      { x: 160, y: 192 },
      'right',
      dimensions,
      (x, y) => ({ kind: x === 5 && y === 2 ? 'open' : 'blocked' }),
    ),
    { x: 352, y: 192 },
  );
  assert.deepEqual(
    findInventoryDropDestination(
      { x: 160, y: 192 },
      'right',
      dimensions,
      (x, y) => x === 4 && y === 1
        ? { kind: 'compatible-stack', destination: { x: 301, y: 190 } }
        : { kind: 'open' },
    ),
    { x: 301, y: 190 },
  );
  assert.equal(
    findInventoryDropDestination({ x: 160, y: 192 }, 'right', dimensions, () => ({ kind: 'blocked' })),
    undefined,
  );
});

test('inventory drops remove, persist, launch, update after collection, and keep IDs monotonic', () => {
  const state = inventoryDropHarness();
  assert.equal(state.controller.dropFromSlot(0, 5), true);
  assert.deepEqual(state.slots, [{ itemId: 'wood', count: 7 }]);
  assert.equal(state.requests.length, 1);
  assert.equal(state.requests[0].mode, 'launch');
  assert.equal(state.requests[0].drop.initialState.remaining, 5);
  assert.equal(state.requests[0].drop.instanceId, 'inventory-drop-1');
  assert.equal(state.progress.inventoryDrops('level-1')[0].amount, 5);

  state.controller.onCollectibleStateChanged({
    instanceId: 'inventory-drop-1',
    sourceInventoryDropId: 'inventory-drop-1',
    remaining: 2,
  });
  assert.equal(state.progress.inventoryDrops('level-1')[0].amount, 2);
  state.controller.onCollectibleStateChanged({
    instanceId: 'inventory-drop-1',
    sourceInventoryDropId: 'inventory-drop-1',
    remaining: 0,
  });
  assert.equal(state.progress.inventoryDrops('level-1').length, 0);

  assert.equal(state.controller.dropFromSlot(0, 1), true);
  assert.equal(state.requests[1].drop.instanceId, 'inventory-drop-2');
});

test('rapid same-item inventory drops converge on the earlier landing cell', () => {
  const state = inventoryDropHarness();
  assert.equal(state.controller.dropFromSlot(0, 1), true);
  assert.equal(state.controller.dropFromSlot(0, 1), true);
  assert.deepEqual(state.requests.map((request) => request.destination), [
    { x: 288, y: 192 },
    { x: 288, y: 192 },
  ]);
});

test('inventory drop failure and blocked placement preserve inventory', () => {
  const blocked = inventoryDropHarness({ blocked: true });
  assert.equal(blocked.controller.dropFromSlot(0, 5), false);
  assert.deepEqual(blocked.slots, [{ itemId: 'wood', count: 12 }]);
  assert.equal(blocked.messages.at(-1), 'No ground space available');

  const failed = inventoryDropHarness({ throwOnSpawn: true });
  assert.equal(failed.controller.dropFromSlot(0, 5), false);
  assert.deepEqual(failed.slots, [{ itemId: 'wood', count: 12 }]);
  assert.equal(failed.progress.inventoryDrops('level-1').length, 0);
  assert.equal(failed.messages.at(-1), 'Could not drop item');

  const persistFailed = inventoryDropHarness({ throwOnPersist: true });
  assert.equal(persistFailed.controller.dropFromSlot(0, 5), false);
  assert.deepEqual(persistFailed.slots, [{ itemId: 'wood', count: 12 }]);
  assert.equal(persistFailed.messages.at(-1), 'Could not drop item');
});

test('inventory drop restoration uses settled mode and persisted quantities', () => {
  const progress = inventoryDropProgress([{
    id: 'inventory-drop-4', itemId: 'stone', amount: 9,
    objectId: 'collectible.stone-pile', visualId: 'stone-pile', x: 320, y: 448,
  }], 5);
  const requests = [];
  const controller = new InventoryDropController({
    mapId: 'level-1',
    dimensions: { tileSize: 64, columns: 20, rows: 20, width: 1280, height: 1280 },
    inventory: { getSlots: () => [], removeFromSlot: () => 0, add: () => 0 },
    getPlayerAnchor: () => ({ x: 0, y: 0 }), getFacing: () => 'down',
    inspectCell: () => ({ kind: 'open' }),
    spawnWorldDrop: (request) => { requests.push(request); return { active: true }; },
    showMessage: () => {},
    progress,
  });
  controller.restore();
  assert.equal(requests.length, 1);
  assert.equal(requests[0].mode, 'settled');
  assert.equal(requests[0].drop.initialState.remaining, 9);
});
