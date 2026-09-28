import test from 'node:test';
import assert from 'node:assert/strict';
import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const content = await loadAuthoredSceneContent();

class TestCharacterBody extends t.Node2D {
  velocity = { x: 0, y: 0 };
  collisionEnabled = true;
}

const ARENA = { shape: 'circle', x: 0, y: 0, radius: 200 };

/** Mounts a character scene whose enemy script is leashed to ARENA and targets `target.position`. */
async function instantiate(sceneId, target) {
  const scene = content.scenes.find((document) => document.sceneId === sceneId);
  const activations = new t.AttackActivation();
  const descriptors = t.createGameDescriptorRegistry();
  const loader = new t.SceneDocumentLoader(async (id) => id === scene.sceneId ? scene : undefined);
  const resources = new t.SceneResourceLoader(async (id) => content.resources.find((resource) => resource.resourceId === id));
  const packed = await new t.SceneResolver({ documents: loader, resources, registry: descriptors }).prepare_scene(scene.sceneId);
  const scripts = t.createGameScriptRegistry({
    [t.DAMAGE_ROUTER_SERVICE]: new t.DamageRouter(activations),
    [t.ATTACK_ACTIVATION_SERVICE]: activations,
    [t.ENEMY_TARGET_SERVICE]: {
      getPrimaryTarget: () => ({ position: { ...target.position }, damageAreaNodeId: 'player-damage', active: true, hostile: true }),
      getNavigation: () => ({ arena: ARENA }),
    },
  });
  const nodeTypes = t.createCoreNodeTypeRegistry().replace('CharacterBody2D', (context) => new TestCharacterBody({ runtimeId: context.runtimeId, name: context.name }));
  const root = new t.SceneInstantiator({ nodeTypes, scripts, descriptors }).instantiate_scene(packed, { runtimeNamespace: `${sceneId}-leash` });
  const tree = new t.SceneTree(); tree.setRoot(root);
  const find = (node) => node instanceof t.EnemyScript ? node : node.get_children().map(find).find(Boolean);
  const script = find(root);
  const body = script.getReference('body').configuredTarget;
  const dispose = () => { tree.shutdown(); packed.dispose(); };
  return { script, body, dispose };
}

function place(body, x, y) {
  body.set_global_transform({ ...body.get_global_transform(), position: { x, y } });
}

test('any enemy spawned into an arena walks home when its target leaves, and resumes when it returns', async () => {
  const target = { position: { x: 900, y: 0 } };
  const { script, body, dispose } = await instantiate('character.worm-brawler', target);
  assert.equal(script.rank, 'ordinary', 'the leash is not boss-specific');
  place(body, 150, 0);
  script._physics_process(1 / 60);
  assert.equal(script.returningToArena, true);
  assert.ok(body.velocity.x < 0 && Math.abs(body.velocity.y) < 1e-9, 'heads back toward the arena centre');

  target.position = { x: 60, y: 0 };
  script._physics_process(1 / 60);
  assert.equal(script.returningToArena, false);
  dispose();
});

test('a returning enemy stops on the arena centre instead of overshooting', async () => {
  const target = { position: { x: 900, y: 0 } };
  const { script, body, dispose } = await instantiate('character.worm-brawler', target);
  place(body, 0.2, 0);
  script._physics_process(1 / 60);
  assert.deepEqual(body.velocity, { x: 0, y: 0 });
  assert.deepEqual(body.get_global_transform().position, { x: 0, y: 0 });
  dispose();
});

test('Fatty mirrors the shared leash as its return-to-center phase and names itself', async () => {
  const target = { position: { x: 900, y: 0 } };
  const { script, body, dispose } = await instantiate('character.fatty-one-eye', target);
  assert.equal(script.displayName, 'Fatty One Eye');
  place(body, 120, 0);
  script._physics_process(1 / 60);
  assert.equal(script.phase, 'return-to-center');
  assert.ok(body.velocity.x < 0, 'keeps walking home during the phase');

  target.position = { x: 50, y: 0 };
  script._physics_process(1 / 60);
  script._physics_process(1 / 60);
  assert.equal(script.phase, 'chase');
  dispose();
});
