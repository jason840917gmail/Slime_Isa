import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { createGameDescriptorRegistry } = await loadTypescriptModule('src/game/features/scripts/registrations.ts');
const { sceneInspectorModel } = await loadTypescriptModule('src/game/editor/scene-studio/SceneInspector.ts');

const registry = createGameDescriptorRegistry();

function scriptNode(scriptId) {
  return { id: 'script', name: 'Behavior', type: 'ScriptNode', scriptId, parentId: 'body', order: 0, properties: {} };
}

function propertyKeys(scriptId) {
  return [...sceneInspectorModel(scriptNode(scriptId), registry).groups.values()]
    .flat()
    .map((entry) => entry.descriptor.key);
}

test('Fatty uses the ordinary enemy ScriptNode authoring path plus descriptor-defined exports', () => {
  const enemy = sceneInspectorModel(scriptNode('game.enemy'), registry);
  const fatty = sceneInspectorModel(scriptNode('game.fatty'), registry);
  const enemyKeys = propertyKeys('game.enemy');
  const fattyKeys = propertyKeys('game.fatty');

  assert.equal(registry.scripts.get('game.fatty').extends, 'game.enemy');
  assert.deepEqual(enemyKeys.filter((key) => !fattyKeys.includes(key)), []);
  assert.deepEqual(fatty.capabilities.filter((capability) => enemy.capabilities.includes(capability)), enemy.capabilities);
  assert.ok(fattyKeys.includes('contactHopCooldownMs'));
  assert.ok(fattyKeys.includes('landingDamage'));
  assert.equal(registry.nodeTypes.has('BossBody2D'), false);
  assert.equal(registry.nodeTypes.has('FattyBody2D'), false);
});

test('rank is common enemy metadata rather than a boss document or editor branch', () => {
  const enemyRank = [...sceneInspectorModel(scriptNode('game.enemy'), registry).groups.values()]
    .flat()
    .find((entry) => entry.descriptor.key === 'rank')?.descriptor;
  const fattyRank = [...sceneInspectorModel(scriptNode('game.fatty'), registry).groups.values()]
    .flat()
    .find((entry) => entry.descriptor.key === 'rank')?.descriptor;

  assert.deepEqual(fattyRank, enemyRank);
  assert.deepEqual(enemyRank.value.values, ['ordinary', 'elite', 'boss']);
});
