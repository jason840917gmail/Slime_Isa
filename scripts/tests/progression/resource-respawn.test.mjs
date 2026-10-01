import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { createServer } from 'vite';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { resolveResourceRespawn } = await loadTypescriptModule('src/game/features/resources/ResourceRespawn.ts');

// WorldProgress reaches Phaser through the event bus; load it through Vite with a stub bus.
const contentRoot = path.resolve(process.cwd(), 'src/game/content');
const eventBusStubId = '\0resource-respawn-event-bus-stub';
const vite = await createServer({
  configFile: false, root: process.cwd(), appType: 'custom',
  plugins: [{
    name: 'resource-respawn-event-bus-stub', enforce: 'pre',
    resolveId(source) { return source.endsWith('/EventBus') || source.endsWith('core/EventBus') ? eventBusStubId : undefined; },
    load(id) { return id === eventBusStubId ? 'export const gameEvents = { emit() { return this; }, on() { return this; }, once() { return this; }, off() { return this; } };' : undefined; },
  }],
  resolve: { alias: {
    'virtual-character-content': path.join(contentRoot, 'characters/virtual-character-content.ts'),
    'virtual-projectile-content': path.join(contentRoot, 'projectiles/virtual-projectile-content.ts'),
    'virtual-weapon-content': path.join(contentRoot, 'weapons/virtual-weapon-content.ts'),
    'virtual-effect-content': path.join(contentRoot, 'effects/virtual-effect-content.ts'),
  } },
  optimizeDeps: { noDiscovery: true }, server: { middlewareMode: true, hmr: false },
});
const { WorldProgress } = await vite.ssrLoadModule('/src/game/features/progression/WorldProgress.ts');
test.after(async () => vite.close());

const RESPAWN_MS = 600_000;

test('an untouched or standing node never changes', () => {
  assert.deepEqual(resolveResourceRespawn(undefined, 0, RESPAWN_MS), { state: undefined, changed: false });
  const standing = { stage: 'node', value: 40 };
  assert.deepEqual(resolveResourceRespawn(standing, 0, RESPAWN_MS), { state: standing, changed: false });
});

test('a harvested node regrows only after its time, and only once its piles are collected', () => {
  const depleted = { stage: 'depleted', value: 0, respawnReadyAtEpochMs: 1_000_000 };
  assert.equal(resolveResourceRespawn(depleted, 999_999, RESPAWN_MS).changed, false, 'never early');
  assert.deepEqual(resolveResourceRespawn(depleted, 1_000_000, RESPAWN_MS), { state: undefined, changed: true });
  const piles = { stage: 'destroyed', value: 3, respawnReadyAtEpochMs: 1_000_000, piles: [{ id: 'tree-drop-1', cellX: 1, cellY: 1, amount: 3 }] };
  assert.equal(resolveResourceRespawn(piles, 5_000_000, RESPAWN_MS).changed, false, 'uncollected piles keep the node down');
});

test('nodes harvested before regrowth existed start their timer instead of returning at once', () => {
  const legacy = { stage: 'depleted', value: 0 };
  assert.deepEqual(resolveResourceRespawn(legacy, 50, RESPAWN_MS), { state: { stage: 'depleted', value: 0, respawnReadyAtEpochMs: 50 + RESPAWN_MS }, changed: true });
});

test('world progress keeps a node\'s regrowth time while its piles change, and forgets it when it regrows', () => {
  const progress = new WorldProgress();
  progress.load({ discoveredAreas: [], defeatedBossIds: [], completedDungeonIds: [], maps: {} });
  progress.setResourceState('level-1', 'tree-1', { stage: 'depleted', value: 0, respawnReadyAtEpochMs: 777 });
  progress.setResourceState('level-1', 'tree-1', { stage: 'destroyed', value: 3, piles: [{ id: 'tree-1-drop-1', cellX: 0, cellY: 0, amount: 3 }] });
  assert.equal(progress.resourceState('level-1', 'tree-1').respawnReadyAtEpochMs, 777);
  progress.setResourceState('level-1', 'tree-1', { stage: 'depleted', value: 0 });
  assert.equal(progress.resourceState('level-1', 'tree-1').respawnReadyAtEpochMs, 777);
  const saved = progress.serialize();
  assert.equal(saved.maps['level-1'].resources['tree-1'].respawnReadyAtEpochMs, 777, 'the time is saved with the run');
  progress.clearResourceState('level-1', 'tree-1');
  assert.equal(progress.resourceState('level-1', 'tree-1'), undefined);
});

test('a regrown node forgets its collected piles, so the next harvest gives its wood again', () => {
  const progress = new WorldProgress();
  progress.load({ discoveredAreas: [], defeatedBossIds: [], completedDungeonIds: [], maps: {} });
  progress.setResourceState('level-1', 'tree-1', { stage: 'depleted', value: 0, respawnReadyAtEpochMs: 1 });
  progress.setCollectibleState('level-1', 'tree-1-drop-1', { remaining: 0, sourceResourceInstanceId: 'tree-1' });
  progress.setCollectibleState('level-1', 'tree-1-drop-2', { remaining: 0 });
  progress.setCollectibleState('level-1', 'tree-10-drop-1', { remaining: 0, sourceResourceInstanceId: 'tree-10' });
  progress.clearResourceState('level-1', 'tree-1');
  assert.equal(progress.collectibleState('level-1', 'tree-1-drop-1'), undefined);
  assert.equal(progress.collectibleState('level-1', 'tree-1-drop-2'), undefined);
  assert.deepEqual(progress.collectibleState('level-1', 'tree-10-drop-1'), { remaining: 0, sourceResourceInstanceId: 'tree-10' }, 'other nodes keep theirs');
});
