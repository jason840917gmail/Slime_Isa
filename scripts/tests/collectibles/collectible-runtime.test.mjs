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
const { completeDropPlacements } = await vite.ssrLoadModule('/src/game/features/resources/ResourceDropPlacement.ts');

test.after(async () => vite.close());

function harness(capacities, savedState) {
  const children = [];
  const persisted = new Map();
  const messages = [];
  const collected = [];
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
  const controller = new CollectibleController({
    scene: { time: { now: 10_000 } },
    mapId: 'level-1',
    group,
    inventory: { add: (_itemId, requested) => Math.min(requested, capacities.shift() ?? 0) },
    progress,
    showMessage: (...message) => messages.push(message),
    onCollected: (payload) => collected.push(payload),
  });
  controller.register({ image, objectId: 'collectible.wood-pile', instanceId: 'wood-01' });
  return { controller, image, persisted, messages, collected };
}

test('walk-over transfer handles full pickup and exact-once depletion', () => {
  const state = harness([10, 10]);
  state.controller.collect(state.image);
  state.controller.collect(state.image);
  assert.equal(state.image.active, false);
  assert.equal(state.persisted.get('wood-01').remaining, 0);
  assert.equal(state.collected.length, 1);
  assert.deepEqual(state.collected[0], {
    mapId: 'level-1', instanceId: 'wood-01', objectId: 'collectible.wood-pile', itemId: 'wood', quantity: 10,
  });
});

test('walk-over transfer preserves partial and zero-capacity quantities', () => {
  const state = harness([0, 4, 6]);
  state.controller.collect(state.image);
  assert.equal(state.persisted.size, 0);
  assert.equal(state.messages.at(-1)[2], 'Inventory full');
  state.controller.collect(state.image);
  assert.equal(state.persisted.get('wood-01').remaining, 6);
  assert.equal(state.image.active, true);
  state.controller.collect(state.image);
  assert.equal(state.persisted.get('wood-01').remaining, 0);
  assert.equal(state.image.active, false);
});

test('fallback resource drops use stable distinct offsets', () => {
  const placements = completeDropPlacements([], { cellX: 4, cellY: 7 }, 6, 64);
  assert.equal(placements.length, 6);
  assert.equal(new Set(placements.map((entry) => `${entry.cellX}:${entry.cellY}:${entry.offsetX}:${entry.offsetY}`)).size, 6);
  assert.deepEqual(placements, completeDropPlacements([], { cellX: 4, cellY: 7 }, 6, 64));
});
