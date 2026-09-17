import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { createServer } from 'vite';

const contentRoot = path.resolve(process.cwd(), 'src/game/content');
const eventBusStubId = '\0inventory-world-event-bus-stub';
const vite = await createServer({
  configFile: false, root: process.cwd(), appType: 'custom',
  plugins: [{
    name: 'inventory-world-event-bus-stub', enforce: 'pre',
    resolveId(source) { return source.endsWith('/EventBus') || source.endsWith('core/EventBus') ? eventBusStubId : undefined; },
    load(id) { return id === eventBusStubId ? 'export const emittedEvents = []; export const gameEvents = { emit(event, payload) { emittedEvents.push({ event, payload }); return this; }, on() { return this; }, once() { return this; }, off() { return this; } };' : undefined; },
  }],
  resolve: { alias: {
    'virtual-character-content': path.join(contentRoot, 'characters/virtual-character-content.ts'),
    'virtual-projectile-content': path.join(contentRoot, 'projectiles/virtual-projectile-content.ts'),
    'virtual-weapon-content': path.join(contentRoot, 'weapons/virtual-weapon-content.ts'),
    'virtual-effect-content': path.join(contentRoot, 'effects/virtual-effect-content.ts'),
    'virtual-animation-content': path.join(contentRoot, 'animations/virtual-animation-content.ts'),
  } },
  optimizeDeps: { noDiscovery: true }, server: { middlewareMode: true, hmr: false },
});
const { Inventory, itemRegistry } = await vite.ssrLoadModule('/src/game/systems/Inventory.ts');
const { WorldProgress } = await vite.ssrLoadModule('/src/game/features/progression/WorldProgress.ts');
const { InventoryWorldTransaction } = await vite.ssrLoadModule('/src/game/features/progression/InventoryWorldTransaction.ts');
const { emittedEvents } = await vite.ssrLoadModule(eventBusStubId);
test.after(async () => vite.close());

const emptyWorld = () => ({ discoveredAreas: [], defeatedBossIds: [], completedDungeonIds: [], maps: {} });
function setup(contents, inventorySnapshot = { maxSlots: 24, slots: [] }) {
  const inventory = new Inventory();
  inventory.installTransactionSnapshot(inventorySnapshot);
  const progress = new WorldProgress();
  progress.load(emptyWorld());
  progress.setChestRemaining('level-1', 'chest', contents);
  emittedEvents.length = 0;
  return { inventory, progress, transaction: new InventoryWorldTransaction(inventory, progress) };
}

test('full and final transfers commit inventory plus permanent empty chest once', () => {
  const { inventory, progress, transaction } = setup({ 'green-key': 1 });
  assert.equal(transaction.transferChestStack('level-1', 'chest', 'green-key'), 1);
  assert.equal(inventory.count('green-key'), 1);
  assert.deepEqual(progress.chestState('level-1', 'chest'), { remaining: {} });
  assert.deepEqual(emittedEvents.map((event) => event.event), ['inventory.changed', 'world.progress.changed']);
});

test('partial and zero-capacity transfers move only the deterministic maximum fit', () => {
  const maxStack = itemRegistry.get('hp-potion').maxStack;
  const partial = setup({ 'hp-potion': 5 }, { maxSlots: 1, slots: [{ itemId: 'hp-potion', count: maxStack - 1 }] });
  assert.equal(partial.transaction.transferChestStack('level-1', 'chest', 'hp-potion'), 1);
  assert.equal(partial.progress.chestState('level-1', 'chest').remaining['hp-potion'], 4);
  const full = setup({ 'hp-potion': 5 }, { maxSlots: 1, slots: [{ itemId: 'hp-potion', count: maxStack }] });
  assert.equal(full.transaction.transferChestStack('level-1', 'chest', 'hp-potion'), 0);
  assert.equal(full.progress.chestState('level-1', 'chest').remaining['hp-potion'], 5);
});

test('invalid item and injected install failure change neither owner', () => {
  const invalid = setup({ 'not-an-item': 2 });
  assert.equal(invalid.transaction.transferChestStack('level-1', 'chest', 'not-an-item'), 0);
  const failed = setup({ 'green-key': 1 });
  const originalInstall = failed.progress.installTransactionSnapshot.bind(failed.progress);
  let first = true;
  failed.progress.installTransactionSnapshot = (snapshot) => { if (first) { first = false; throw new Error('injected'); } originalInstall(snapshot); };
  assert.equal(failed.transaction.transferChestStack('level-1', 'chest', 'green-key'), 0);
  assert.equal(failed.inventory.count('green-key'), 0);
  assert.deepEqual(failed.progress.chestState('level-1', 'chest'), { remaining: { 'green-key': 1 } });
  assert.equal(emittedEvents.length, 0);
});

test('collectible pickup atomically moves the maximum fit and preserves provenance', () => {
  const { inventory, progress, transaction } = setup({}, {
    maxSlots: 1,
    slots: [{ itemId: 'hp-potion', count: itemRegistry.get('hp-potion').maxStack - 2 }],
  });
  progress.setCollectibleState('level-1', 'drop', {
    remaining: 5,
    sourceResourceInstanceId: 'tree-1',
  });
  emittedEvents.length = 0;

  assert.equal(transaction.collectWorldItem({
    mapId: 'level-1',
    instanceId: 'drop',
    itemId: 'hp-potion',
    remaining: 5,
    requested: 4,
  }), 2);
  assert.equal(inventory.count('hp-potion'), itemRegistry.get('hp-potion').maxStack);
  assert.deepEqual(progress.collectibleState('level-1', 'drop'), {
    remaining: 3,
    sourceResourceInstanceId: 'tree-1',
  });
  assert.deepEqual(emittedEvents.map((event) => event.event), ['inventory.changed', 'world.progress.changed']);
});

test('collectible pickup rolls both owners back when world installation fails', () => {
  const { inventory, progress, transaction } = setup({});
  progress.setCollectibleState('level-1', 'berry', { remaining: 1 });
  emittedEvents.length = 0;
  const originalInstall = progress.installTransactionSnapshot.bind(progress);
  let first = true;
  progress.installTransactionSnapshot = (snapshot) => {
    if (first) {
      first = false;
      throw new Error('injected');
    }
    originalInstall(snapshot);
  };

  assert.equal(transaction.collectWorldItem({
    mapId: 'level-1',
    instanceId: 'berry',
    itemId: 'purple-berry',
    remaining: 1,
  }), 0);
  assert.equal(inventory.count('purple-berry'), 0);
  assert.deepEqual(progress.collectibleState('level-1', 'berry'), { remaining: 1 });
  assert.equal(emittedEvents.length, 0);
});

test('consuming, non-consuming, missing, and idempotent gate unlocks are aggregate', () => {
  const consuming = setup({}, { maxSlots: 24, slots: [{ itemId: 'green-key', count: 1 }] });
  const request = { mapId: 'level-1', gateId: 'east-gate', requiredItemId: 'green-key', consumeOnUnlock: true };
  assert.equal(consuming.transaction.unlockGate(request), 'unlocked');
  assert.equal(consuming.inventory.count('green-key'), 0);
  assert.equal(consuming.progress.isGateUnlocked('level-1', 'east-gate'), true);
  assert.equal(consuming.transaction.unlockGate(request), 'already-unlocked');
  assert.equal(consuming.inventory.count('green-key'), 0);

  const nonConsuming = setup({}, { maxSlots: 24, slots: [{ itemId: 'green-key', count: 1 }] });
  assert.equal(nonConsuming.transaction.unlockGate({ ...request, consumeOnUnlock: false }), 'unlocked');
  assert.equal(nonConsuming.inventory.count('green-key'), 1);
  const missing = setup({});
  assert.equal(missing.transaction.unlockGate(request), 'missing-item');
  assert.equal(missing.progress.isGateUnlocked('level-1', 'east-gate'), false);
});
