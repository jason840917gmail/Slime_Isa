import assert from 'node:assert/strict';
import test from 'node:test';
import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const camps = await loadTypescriptModule('src/game/editor/scene-studio/BossCampStudio.ts');
const areas = await loadTypescriptModule('src/game/editor/scene-studio/WorldAreaStudio.ts');
const viewport = await loadTypescriptModule('src/game/editor/scene-studio/SceneViewport.ts');
const content = await loadAuthoredSceneContent();
const byId = new Map(content.scenes.map((scene) => [scene.sceneId, scene]));
const TRANSFORM_TYPES = new Set(['Node2D', 'Sprite2D', 'Area2D', 'CollisionShape2D', 'CharacterBody2D', 'StaticBody2D', 'TileMapLayer2D', 'Camera2D', 'AudioStreamPlayer2D', 'AnimatedSprite2D']);

function compose(sceneId) {
  const document = byId.get(sceneId);
  const nodes = viewport.composeSceneNodes(document, (id) => byId.get(id), (type) => TRANSFORM_TYPES.has(type));
  return { document, nodes, byKey: new Map(nodes.map((node) => [node.key, node])) };
}

function shapeValue(nodes) {
  return (node) => {
    const scene = byId.get(node.sourceSceneId);
    const resource = scene.subresources.find((candidate) => candidate.resourceId === node.properties.shape?.resourceId);
    return resource ? { value: resource.value, editable: false } : undefined;
  };
}

const isEnemyScript = (scriptId) => scriptId === 'game.enemy' || scriptId === 'game.fatty';

test('selecting the Fatty camp in level-1 links to the boss scene and shows where it spawns', () => {
  const { nodes, byKey } = compose('world.level-1');
  const campRoot = nodes.find((node) => node.instancePath[0] === 'level-1-fatty-one-eye-camp' && node.parentKey === ':world');
  const camp = camps.owningBossCamp(campRoot, nodes);
  assert.ok(camp, 'any node of the placed encounter resolves to its camp script');
  assert.equal(camps.bossSceneIdOf(camp), 'character.fatty-one-eye');
  // The encounter root is placed at 2528,1472 and spawns the boss at its origin.
  assert.deepEqual(camps.bossSpawnPoint(camp, byKey), [2528, 1472]);

  const boss = camps.bossSceneInfo('character.fatty-one-eye', byId.get('character.fatty-one-eye'), isEnemyScript, 'fatty-one-eye');
  assert.deepEqual(boss, { sceneId: 'character.fatty-one-eye', name: 'Fatty One Eye', spawnable: true });
  const summary = camps.bossCampSummary(camp, nodes, shapeValue(nodes), boss);
  assert.deepEqual(summary.issues, []);
  assert.equal(summary.shapesEditableHere, false, 'circles belong to the encounter scene, not the world');
  assert.match(summary.lines.join('\n'), /Arena: circle r933 at 2528, 1472/);
});

test('camp shapes are coloured as activation and arena', () => {
  const { nodes } = compose('encounter.level-1-fatty-camp');
  const roles = camps.bossCampShapeRoles(nodes);
  assert.equal(roles.get(':activation-shape'), 'activation');
  assert.equal(roles.get(':arena-shape'), 'arena');
});

test('a camp pointing at a non-enemy scene or an arena that misses the spawn is flagged', () => {
  const { nodes } = compose('encounter.level-1-fatty-camp');
  const camp = nodes.find(camps.isBossCampScript);
  const notEnemy = camps.bossSceneInfo('character.lili', byId.get('character.lili'), isEnemyScript, 'lili');
  assert.match(camps.bossCampSummary(camp, nodes, shapeValue(nodes), notEnemy).issues.join('\n'), /no enemy script/);
  const moved = nodes.map((node) => node.key === camp.key ? { ...node, properties: { ...node.properties, spawn: [2000, 0] } } : node);
  const boss = camps.bossSceneInfo('character.fatty-one-eye', byId.get('character.fatty-one-eye'), isEnemyScript, 'x');
  assert.match(camps.bossCampSummary(moved.find(camps.isBossCampScript), moved, shapeValue(moved), boss).issues.join('\n'), /spawns outside its arena/);
});

test('the enemy picker edits spawn settings without losing other keys', () => {
  let data = { enemies: [{ type: 'worm-brawler', weight: 1, maxAlive: 3 }], intervalMs: 2500, maxPopulation: 3, note: 'kept' };
  data = areas.editAreaSettings(data, { kind: 'enemy-add', type: 'worm-archer' });
  data = areas.editAreaSettings(data, { kind: 'enemy-field', index: 1, field: 'weight', value: '4' });
  data = areas.editAreaSettings(data, { kind: 'enemy-field', index: 0, field: 'maxAlive', value: '' });
  data = areas.editAreaSettings(data, { kind: 'setting', key: 'maxPopulation', value: '5' });
  assert.deepEqual(data, {
    enemies: [{ type: 'worm-brawler', weight: 1 }, { type: 'worm-archer', weight: 4, maxAlive: 1 }],
    intervalMs: 2500, maxPopulation: 5, note: 'kept',
  });
  assert.throws(() => areas.editAreaSettings(data, { kind: 'setting', key: 'intervalMs', value: '0' }), /whole number above 0/);
  data = areas.editAreaSettings(data, { kind: 'enemy-remove', index: 0 });
  assert.deepEqual(data.enemies, [{ type: 'worm-archer', weight: 4, maxAlive: 1 }]);
});

test('unknown enemy types are reported in the area summary', () => {
  const document = { version: 1, sceneId: 'world.fixture', rootNodeId: 'root', instances: [], subresources: [], nodes: [{ id: 'root', name: 'Root', type: 'Node2D', parentId: null, order: 0, properties: {} }] };
  const { command, areaNodeId } = areas.worldAreaTemplateCommand(document, 'enemy-spawn', 'root', [0, 0]);
  const next = command.apply(document).document;
  const script = next.nodes.find((node) => node.scriptId === 'game.world-area');
  script.properties.data.enemies[0].type = 'worm-typo';
  const nodes = viewport.composeSceneNodes(next);
  const summary = areas.worldAreaSummary(areas.owningWorldArea(nodes.find((node) => node.key === `:${areaNodeId}`), nodes), nodes,
    (node) => next.subresources.find((resource) => resource.resourceId === node.properties.shape.resourceId)?.value, new Set(['worm-brawler']));
  assert.match(summary.issues.join('\n'), /Unknown enemy type 'worm-typo'/);
});
