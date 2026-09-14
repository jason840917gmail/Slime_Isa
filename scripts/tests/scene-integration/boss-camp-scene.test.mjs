import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { loadTypescriptModule, REPOSITORY_ROOT } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const paths = [
  'src/game/content/scenes/authored/encounters/level-1-fatty-camp.scene.json',
  'src/game/content/scenes/authored/objects/chest-wooden.scene.json',
];
const documents = await Promise.all(paths.map(async (path) => JSON.parse(await readFile(`${REPOSITORY_ROOT}/${path}`, 'utf8'))));

async function instantiate() {
  const descriptors = t.createGameDescriptorRegistry();
  const loader = new t.SceneDocumentLoader(async (id) => documents.find((document) => document.sceneId === id));
  const packed = await new t.SceneResolver({ documents: loader, registry: descriptors })
    .prepare_scene('encounter.level-1-fatty-camp');
  const remaining = new Map();
  const spawnRequests = [];
  const removed = [];
  const status = [];
  const respawns = new Map();
  const defeated = [];
  const opened = [];
  const closed = [];
  let campScript;
  const services = {
    [t.CHEST_WORLD_SERVICE]: {
      ensureInitialized: (mapId, instanceId, contents) => {
        const key = `${mapId}:${instanceId}`;
        if (!remaining.has(key)) remaining.set(key, { ...contents });
      },
      getRemaining: (mapId, instanceId) => ({ ...(remaining.get(`${mapId}:${instanceId}`) ?? {}) }),
      transferStack: (mapId, instanceId, itemId) => {
        const key = `${mapId}:${instanceId}`;
        const contents = remaining.get(key) ?? {};
        const moved = contents[itemId] ?? 0;
        delete contents[itemId];
        remaining.set(key, contents);
        return moved;
      },
    },
    [t.CHEST_GUARD_SERVICE]: { isLocked: (instanceId) => campScript?.isChestGuarded(instanceId) ?? false },
    [t.CHEST_VIEW_SERVICE]: {
      open: (model) => opened.push(model),
      close: (instanceId) => closed.push(instanceId),
    },
    [t.BOSS_CAMP_PROGRESS_SERVICE]: {
      getRespawnReadyAt: (mapId, campId) => respawns.get(`${mapId}:${campId}`),
      setRespawnReadyAt: (mapId, campId, epoch) => {
        const key = `${mapId}:${campId}`;
        if (epoch === undefined) respawns.delete(key); else respawns.set(key, epoch);
      },
      markBossDefeated: (bossId) => defeated.push(bossId),
    },
    [t.BOSS_SCENE_SPAWNER_SERVICE]: {
      spawnBoss: (request) => spawnRequests.push(request),
      removeBoss: (campId) => removed.push(campId),
    },
    [t.BOSS_UI_SERVICE]: {
      showBoss: (campId, bossId) => status.push(['show', campId, bossId]),
      hideBoss: (campId, wasDefeated) => status.push(['hide', campId, wasDefeated]),
    },
  };
  const root = new t.SceneInstantiator({
    nodeTypes: t.createCoreNodeTypeRegistry(),
    scripts: t.createGameScriptRegistry(services),
    descriptors,
  }).instantiate_scene(packed, {
    runtimeNamespace: 'camp-fixture',
    persistenceKey: 'level-1-fatty-one-eye-camp',
  });
  campScript = root.get_node('BossCampScript');
  const chestScript = root.get_node('GuardedChest/ChestScript');
  const tree = new t.SceneTree(); tree.setRoot(root);
  return { root, tree, packed, loader, campScript, chestScript, remaining, spawnRequests, removed, status, respawns, defeated, opened, closed };
}

test('authored camp eagerly owns one preserved chest instance and dynamically requests Fatty', async () => {
  const fixture = await instantiate();
  assert.ok(fixture.campScript instanceof t.BossCampScript);
  assert.ok(fixture.chestScript instanceof t.ChestScript);
  assert.equal(fixture.root.explicitPersistenceKey, 'level-1-fatty-one-eye-camp');
  assert.equal(fixture.chestScript.instanceId, 'level-1-fatty-guarded-chest');
  assert.deepEqual(fixture.chestScript.remaining, { 'green-key': 1 });
  assert.equal(fixture.root.get_children().filter((node) => node.name === 'GuardedChest').length, 1);

  assert.equal(fixture.campScript.evaluateActivation(true, 1000), true);
  assert.equal(fixture.spawnRequests.length, 1);
  assert.deepEqual(fixture.spawnRequests[0], {
    sceneId: 'character.fatty-one-eye',
    campId: 'level-1-fatty-one-eye-camp',
    bossId: 'fatty-one-eye',
    parentRuntimeId: fixture.root.get_node('ActiveBosses').runtimeId,
    spawn: { x: 0, y: 0 },
  });
  assert.equal(fixture.chestScript.requestOpen(), 'guarded');
  assert.equal(fixture.opened.length, 0);

  fixture.campScript.onBossDefeated(2000);
  assert.deepEqual(fixture.defeated, ['fatty-one-eye']);
  assert.equal(fixture.respawns.get('level-1:level-1-fatty-one-eye-camp'), 182000);
  assert.equal(fixture.chestScript.requestOpen(), 'opened');
  assert.equal(fixture.opened.length, 1);
  assert.equal(fixture.opened[0].transferStack('green-key'), 1);
  assert.deepEqual(fixture.chestScript.remaining, {});

  fixture.tree.shutdown(); fixture.packed.dispose();
  assert.equal(fixture.loader.activeLeaseCount(), 0);
  assert.ok(fixture.closed.includes('level-1-fatty-guarded-chest'));
});

test('camp respawn requires deadline plus an outside observation and transient reset suppresses immediate spawn', async () => {
  const fixture = await instantiate();
  fixture.campScript.evaluateActivation(true, 0);
  fixture.campScript.onBossDefeated(100);
  assert.equal(fixture.campScript.evaluateActivation(true, 180100), false);
  assert.equal(fixture.campScript.evaluateActivation(false, 180100), false);
  assert.equal(fixture.campScript.evaluateActivation(true, 180101), true);
  assert.equal(fixture.spawnRequests.length, 2);
  fixture.campScript.resetActiveFight();
  assert.equal(fixture.campScript.evaluateActivation(true, 180102), false);
  assert.equal(fixture.campScript.evaluateActivation(false, 180103), false);
  assert.equal(fixture.campScript.evaluateActivation(true, 180104), true);
  assert.equal(fixture.spawnRequests.length, 3);
  fixture.tree.shutdown(); fixture.packed.dispose();
});

