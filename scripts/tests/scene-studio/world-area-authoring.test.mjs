import assert from 'node:assert/strict';
import test from 'node:test';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const areas = await loadTypescriptModule('src/game/editor/scene-studio/WorldAreaStudio.ts');
const viewport = await loadTypescriptModule('src/game/editor/scene-studio/SceneViewport.ts');
const tooling = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const validation = await loadTypescriptModule('src/game/content/scenes/validation.ts');

const world = () => ({
  version: 1, sceneId: 'world.fixture', rootNodeId: 'root', instances: [], subresources: [],
  nodes: [
    { id: 'root', name: 'Root', type: 'Node2D', parentId: null, order: 0, properties: {} },
    { id: 'world', name: 'world', type: 'Node2D', parentId: 'root', order: 0, properties: { position: [100, 0] } },
  ],
});

function add(document, kind, position = [400, 300]) {
  const { command, areaNodeId, areaId } = areas.worldAreaTemplateCommand(document, kind, 'world', position);
  return { document: command.apply(document).document, areaNodeId, areaId };
}

function summaryFor(document, areaNodeId) {
  const nodes = viewport.composeSceneNodes(document);
  const script = areas.owningWorldArea(nodes.find((node) => node.key === `:${areaNodeId}`), nodes);
  const shapeValue = (node) => document.subresources.find((resource) => resource.resourceId === node.properties.shape.resourceId)?.value;
  return areas.worldAreaSummary(script, nodes, shapeValue);
}

test('each world area template adds a valid, loadable area', () => {
  const registry = tooling.createGameDescriptorRegistry();
  let document = world();
  for (const kind of ['enemy-spawn', 'enemy-safe-zone', 'npc-wander']) ({ document } = add(document, kind));
  assert.deepEqual(validation.validateSceneDocument(document, { registry }), []);
  assert.equal(document.nodes.filter((node) => node.scriptId === 'game.world-area').length, 3);
  const spawn = document.nodes.find((node) => node.properties.areaKind === 'enemy-spawn');
  assert.deepEqual(Object.keys(spawn.properties.data).sort(), ['enemies', 'intervalMs', 'maxPopulation']);
  assert.ok(spawn.properties.stayShape, 'spawn areas get a stay shape');
});

test('template ids never collide with existing areas or resources', () => {
  let document = world();
  const first = add(document, 'enemy-spawn');
  const second = add(first.document, 'enemy-spawn');
  assert.equal(first.areaId, 'enemy-area-01');
  assert.equal(second.areaId, 'enemy-area-02');
  const ids = second.document.subresources.map((resource) => resource.resourceId);
  assert.equal(new Set(ids).size, ids.length);
  document = second.document;
  assert.equal(document.nodes.find((node) => node.id === 'area-enemy-area-02').properties.position[0], 400);
});

test('the area summary reports what the game loads and flags invalid edits', () => {
  const { document, areaNodeId } = add(world(), 'enemy-spawn');
  const ok = summaryFor(document, areaNodeId);
  assert.deepEqual(ok.issues, []);
  // Area at world (100,0) + (400,300): pursue 512×384 centred there.
  assert.match(ok.lines[0], /Pursue: 512×384 at 244, 108/);

  const moved = structuredClone(document);
  moved.nodes.find((node) => node.id === `${areaNodeId}-stay-shape`).properties.position = [300, 0];
  assert.match(summaryFor(moved, areaNodeId).issues.join('\n'), /stay rectangle must fit inside the pursue rectangle/i);

  const npc = add(world(), 'npc-wander');
  assert.match(summaryFor(npc.document, npc.areaNodeId).issues.join('\n'), /Choose the NPC/);
});

test('shape roles colour pursue, stay, safe and wander shapes', () => {
  let document = world();
  let spawn;
  ({ document, areaNodeId: spawn } = add(document, 'enemy-spawn'));
  const roles = areas.worldAreaShapeRoles(viewport.composeSceneNodes(document));
  assert.equal(roles.get(`:${spawn}-shape`), 'perimeter');
  assert.equal(roles.get(`:${spawn}-stay-shape`), 'stay');
});

test('switching a shape kind keeps its footprint', () => {
  assert.deepEqual(areas.convertShapeKind({ shape: 'rectangle', width: 200, height: 100 }, 'circle'), { shape: 'circle', radius: 100 });
  assert.deepEqual(areas.convertShapeKind({ shape: 'circle', radius: 40 }, 'rectangle'), { shape: 'rectangle', width: 80, height: 80 });
  assert.deepEqual(areas.convertShapeKind({ shape: 'rectangle', width: 60, height: 20 }, 'ellipse'), { shape: 'ellipse', radiusX: 30, radiusY: 10 });
});
