import assert from 'node:assert/strict';
import test from 'node:test';

import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const content = await loadAuthoredSceneContent();

async function instantiate(sceneId, runtimeNamespace, mapId, instanceId) {
  const activations = new t.AttackActivation();
  const router = new t.DamageRouter(activations);
  const descriptors = t.createGameDescriptorRegistry();
  const loader = new t.SceneDocumentLoader(async (id) => content.scenes.find((candidate) => candidate.sceneId === id));
  const resources = new t.SceneResourceLoader(async (id) => content.resources.find((candidate) => candidate.resourceId === id));
  const packed = await new t.SceneResolver({ documents: loader, resources, registry: descriptors }).prepare_scene(sceneId);
  const root = new t.SceneInstantiator({
    nodeTypes: t.createCoreNodeTypeRegistry(),
    scripts: t.createGameScriptRegistry({
      [t.DAMAGE_ROUTER_SERVICE]: router,
      [t.WORLD_OBJECT_STATE_SERVICE]: { load: () => undefined, saveHealth() {}, markDestroyed() {} },
      [t.RESOURCE_NODE_SERVICE]: { publishHit() {}, publishHarvestBlocked() {}, spawnDrops() {} },
    }),
    descriptors,
  }).instantiate_scene(packed, {
    runtimeNamespace,
    persistenceKey: `${mapId}.${instanceId}`,
    propertyOverrides: [
      { nodeId: 'script', property: 'mapId', value: mapId },
      { nodeId: 'script', property: 'instanceId', value: instanceId },
    ],
  });
  const tree = new t.SceneTree();
  tree.setRoot(root);
  return { root, tree, packed, loader, resources, router };
}

function dispose(fixture) {
  fixture.tree.shutdown();
  fixture.packed.dispose();
  assert.equal(fixture.loader.activeLeaseCount(), 0);
  assert.equal(fixture.resources.activeLeaseCount(), 0);
}

for (const sceneId of [
  'object.resource-stone-node',
  'object.resource-stone-node.big-stone-mine',
  'object.tree-world-solid',
  'object.tree-world-solid.tree-autumn-01',
]) {
  test(`${sceneId} mounts independent persistent resource state through placement overrides`, async () => {
    const first = await instantiate(sceneId, `${sceneId}-first`, 'level-1', 'stone-1');
    const second = await instantiate(sceneId, `${sceneId}-second`, 'level-2', 'stone-2');
    const firstScript = first.root.get_node('ResourceNodeScript');
    const secondScript = second.root.get_node('ResourceNodeScript');
    assert.ok(firstScript instanceof t.ResourceNodeScript);
    assert.ok(secondScript instanceof t.ResourceNodeScript);
    assert.equal(firstScript.mapId, 'level-1');
    assert.equal(firstScript.instanceId, 'stone-1');
    assert.equal(secondScript.mapId, 'level-2');
    assert.equal(secondScript.instanceId, 'stone-2');
    assert.equal(first.root.explicitPersistenceKey, 'level-1.stone-1');
    assert.equal(first.router.hasArea(first.root.get_node('DamageArea').runtimeId), true);
    dispose(first);
    dispose(second);
  });
}
