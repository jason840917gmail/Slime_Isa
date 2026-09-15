import assert from 'node:assert/strict';
import test from 'node:test';

import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const content = await loadAuthoredSceneContent();
const sceneIds = [
  'character.worm-archer',
  'character.worm-swordsman',
  'character.slime-spider',
];

class TestCharacterBody extends t.Node2D {
  velocity = { x: 0, y: 0 };
}

async function instantiatePair(sceneId) {
  const namespace = sceneId.replaceAll('.', '-');
  const scene = content.scenes.find((document) => document.sceneId === sceneId);
  const activations = new t.AttackActivation();
  const router = new t.DamageRouter(activations);
  const loader = new t.SceneDocumentLoader(async (id) => id === scene.sceneId ? scene : undefined);
  const resources = new t.SceneResourceLoader(async (id) => content.resources.find((resource) => resource.resourceId === id));
  const descriptors = t.createGameDescriptorRegistry();
  const packed = await new t.SceneResolver({ documents: loader, resources, registry: descriptors }).prepare_scene(scene.sceneId);
  const scripts = t.createGameScriptRegistry({
    [t.DAMAGE_ROUTER_SERVICE]: router,
    [t.ATTACK_ACTIVATION_SERVICE]: activations,
    [t.ENEMY_TARGET_SERVICE]: { getPrimaryTarget: () => undefined },
  });
  const nodeTypes = t.createCoreNodeTypeRegistry().replace('CharacterBody2D', (context) => new TestCharacterBody({
    runtimeId: context.runtimeId,
    name: context.name,
    position: Array.isArray(context.properties.position)
      ? { x: Number(context.properties.position[0]), y: Number(context.properties.position[1]) }
      : undefined,
  }));
  const instantiator = new t.SceneInstantiator({ nodeTypes, scripts, descriptors });
  const first = instantiator.instantiate_scene(packed, { runtimeNamespace: `${namespace}-first` });
  const second = instantiator.instantiate_scene(packed, { runtimeNamespace: `${namespace}-second` });
  const firstTree = new t.SceneTree();
  const secondTree = new t.SceneTree();
  firstTree.setRoot(first);
  secondTree.setRoot(second);
  return { activations, router, first, second, firstTree, secondTree, packed, loader, resources };
}

for (const sceneId of sceneIds) {
  test(`${sceneId} instances have independent runtime state and stable authored references`, async () => {
    const fixture = await instantiatePair(sceneId);
    const firstScript = fixture.first.get_node('EnemyScript');
    const secondScript = fixture.second.get_node('EnemyScript');
    const firstArea = fixture.first.get_node('DamageArea');
    assert.ok(firstScript instanceof t.EnemyScript);
    assert.ok(secondScript instanceof t.EnemyScript);
    assert.notEqual(firstScript.runtimeId, secondScript.runtimeId);
    assert.equal(firstScript.getReference('body').configuredTarget, fixture.first);
    assert.equal(secondScript.getReference('body').configuredTarget, fixture.second);

    const activationId = fixture.activations.begin('player-weapon', ['player-swing']);
    fixture.router.routeStep([{
      activationId,
      sourceNodeId: 'player-weapon',
      attackAreaNodeId: 'player-swing',
      targetAreaNodeId: firstArea.runtimeId,
      weaponId: 'wooden-spear',
      weaponTags: ['melee', 'spear'],
      damageTypes: ['physical'],
      baseDamage: 7,
      effects: [],
      impact: { x: 0, y: 0, knockX: 1, knockY: 0 },
    }], 100);
    assert.equal(firstScript.hp, firstScript.maxHealth - 7);
    assert.equal(secondScript.hp, secondScript.maxHealth);

    fixture.firstTree.shutdown();
    fixture.secondTree.shutdown();
    fixture.packed.dispose();
    assert.equal(fixture.loader.activeLeaseCount(), 0);
    assert.equal(fixture.resources.activeLeaseCount(), 0);
  });
}
