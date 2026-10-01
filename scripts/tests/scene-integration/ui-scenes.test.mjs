import assert from 'node:assert/strict';
import test from 'node:test';

import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const content = await loadAuthoredSceneContent();
const uiScenes = content.scenes.filter((scene) => scene.sceneId.startsWith('ui.')).sort((left, right) => left.sceneId.localeCompare(right.sceneId));

function fakeScene() {
  return {
    physics: {
      systems: {}, disableUpdate() {}, enableUpdate() {}, world: { step() {} },
      add: { collider() { return { destroy() {} }; } },
    },
  };
}

function descendants(root) {
  const nodes = [];
  const visit = (node) => { nodes.push(node); for (const child of node.get_children()) visit(child); };
  visit(root);
  return nodes;
}

async function prepare(sceneId) {
  const registry = t.createGameDescriptorRegistry();
  const documents = new t.SceneDocumentLoader(async (id) => content.scenes.find((scene) => scene.sceneId === id));
  const resources = new t.SceneResourceLoader(async (id) => content.resources.find((resource) => resource.resourceId === id));
  const resolver = new t.SceneResolver({ documents, resources, registry });
  return { packed: await resolver.prepare_scene(sceneId), registry, documents, resources };
}

test('every authored UI scene resolves through the common scene document pipeline', async () => {
  assert.equal(uiScenes.length, 26);
  for (const scene of uiScenes) {
    const { packed, documents, resources } = await prepare(scene.sceneId);
    assert.equal(packed.definition.sourceSceneId, scene.sceneId);
    assert.ok(packed.definition.nodes.some((node) => node.scriptId === 'game.ui-surface'));
    assert.ok(['Container', 'ModalRoot'].includes(packed.definition.nodes[0].type));
    packed.dispose();
    assert.equal(documents.activeLeaseCount(), 0);
    assert.equal(resources.activeLeaseCount(), 0);
  }
});

test('UI scripts bind injected presentation models and queue typed actions without domain imports', async () => {
  const models = {
    hud: { coinsLabel: 'Coins 27', hp: 42, maxHp: 60, energy: 31, maxEnergy: 40 },
    'chest-inventory-panel': { open: true, selectedIndex: 0, items: [{ id: 'wood', label: 'Wood ×3' }], details: 'Wood\nCrafting material' },
  };
  const actions = [];
  const port = {
    snapshot: (surfaceId) => models[surfaceId] ?? {},
    invoke: (surfaceId, actionId, payload) => actions.push({ surfaceId, actionId, payload }),
  };
  const registry = t.createGameDescriptorRegistry();
  const scripts = t.createGameScriptRegistry({ [t.UI_SURFACE_SERVICE]: port });
  const context = new t.PhaserNodeContext(fakeScene(), new Map(content.resources.map((resource) => [resource.resourceId, resource])));
  const nodeTypes = t.createPhaserNodeRegistry(context);
  const instantiator = new t.SceneInstantiator({ nodeTypes, scripts, descriptors: registry });

  const hudPrepared = await prepare('ui.hud');
  const hud = instantiator.instantiate_scene(hudPrepared.packed, { runtimeNamespace: 'ui-hud-test' });
  const hudTree = new t.SceneTree();
  hudTree.setRoot(hud);
  const hudNodes = descendants(hud);
  assert.equal(hudNodes.find((node) => node.name === 'Coins').text, 'Coins 27');
  assert.equal(hudNodes.some((node) => node.name === 'Level' || node.name === 'Experience'), false);
  assert.equal(hudNodes.find((node) => node.name === 'Health').ratio, 0.7);
  hudTree.shutdown();
  hudPrepared.packed.dispose();

  const chestPrepared = await prepare('ui.chest-inventory-panel');
  const chest = instantiator.instantiate_scene(chestPrepared.packed, { runtimeNamespace: 'ui-chest-test' });
  const chestTree = new t.SceneTree();
  chestTree.setRoot(chest);
  const chestNodes = descendants(chest);
  assert.equal(chestNodes[0].open, true);
  assert.equal(chestNodes.find((node) => node.name === 'Items').items[0].id, 'wood');
  chestNodes.find((node) => node.name === 'Close').activate();
  chestTree.process(0);
  assert.deepEqual(actions, [{ surfaceId: 'chest-inventory-panel', actionId: 'close', payload: undefined }]);
  chestTree.shutdown();
  chestPrepared.packed.dispose();
  context.shutdown();
});
