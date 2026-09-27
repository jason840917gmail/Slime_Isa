import assert from 'node:assert/strict';
import test from 'node:test';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const viewport = await loadTypescriptModule('src/game/editor/scene-studio/SceneViewport.ts');
const { sceneTreeRows } = await loadTypescriptModule('src/game/editor/scene-studio/SceneTreePanel.ts');
const preview = await loadTypescriptModule('src/game/editor/scene-studio/ScenePreview.ts');

const prop = {
  version: 1, sceneId: 'object.prop', rootNodeId: 'root',
  nodes: [
    { id: 'root', name: 'Prop', type: 'Node2D', parentId: null, order: 0, properties: { position: [0, 0] } },
    { id: 'visual', name: 'Visual', type: 'Sprite2D', parentId: 'root', order: 0, properties: { position: [0, -10] } },
  ],
  instances: [],
};
const camp = {
  version: 1, sceneId: 'encounter.camp', rootNodeId: 'root',
  nodes: [{ id: 'root', name: 'Camp', type: 'Node2D', parentId: null, order: 0, properties: { position: [0, 0], scale: [2, 2] } }],
  instances: [{ instanceId: 'crate', name: 'Crate', sceneId: 'object.prop', parentNodeId: 'root', order: 0, overrides: [{ sourceInstancePath: [], sourceNodeId: 'root', property: 'position', value: [5, 5] }] }],
};
const world = {
  version: 1, sceneId: 'world.test', rootNodeId: 'world',
  nodes: [
    { id: 'world', name: 'World', type: 'Node2D', parentId: null, order: 0, properties: { position: [0, 0] } },
    { id: 'group', name: 'Group', type: 'Node2D', parentId: 'world', order: 0, properties: { position: [100, 50] } },
    { id: 'logic', name: 'Logic', type: 'Node', parentId: 'group', order: 1, properties: {} },
    { id: 'marker', name: 'Marker', type: 'Node2D', parentId: 'logic', order: 0, properties: { position: [1, 2] } },
  ],
  instances: [
    { instanceId: 'camp-1', name: 'Camp One', sceneId: 'encounter.camp', parentNodeId: 'group', order: 2, overrides: [
      { sourceInstancePath: [], sourceNodeId: 'root', property: 'position', value: [10, 20] },
      { sourceInstancePath: ['crate'], sourceNodeId: 'root', property: 'position', value: [7, 0] },
    ] },
  ],
};
const library = new Map([[prop.sceneId, prop], [camp.sceneId, camp], [world.sceneId, world]]);
const resolve = (sceneId) => library.get(sceneId);

test('composition walks parent chains through non-2D nodes and into instances with outer overrides winning', () => {
  const nodes = viewport.composeSceneNodes(world, resolve);
  const byKey = new Map(nodes.map((node) => [node.key, node]));
  assert.deepEqual(byKey.get(':group').global.position, [100, 50]);
  // Plain Node breaks nothing: Marker composes through Logic to Group.
  assert.deepEqual(byKey.get(':marker').global.position, [101, 52]);
  assert.equal(byKey.get(':logic').global, undefined);
  // Instance root uses the instance override, composed onto Group.
  const campRoot = byKey.get('camp-1:root');
  assert.deepEqual(campRoot.global.position, [110, 70]);
  assert.equal(campRoot.readOnly, true);
  // Nested instance: the outer override ([7,0]) beats the camp's own ([5,5]); camp scale 2 applies.
  const crate = byKey.get('camp-1/crate:root');
  assert.deepEqual(crate.global.position, [124, 70]);
  assert.deepEqual(byKey.get('camp-1/crate:visual').global.position, [124, 50]);
  assert.deepEqual(crate.global.scale, [2, 2]);
  // Global edits convert back to authored local values.
  assert.deepEqual(viewport.localPositionFor(crate.parentGlobal, [130, 80]).map((value) => Math.round(value * 100) / 100), [10, 5]);
});

test('camera helpers zoom around the cursor, pan in screen space and frame bounds', () => {
  const size = { width: 800, height: 600 };
  const camera = { centerX: 0, centerY: 0, zoom: 1 };
  const anchor = viewport.screenToWorld(camera, size, [600, 100]);
  const zoomed = viewport.zoomCameraAt(camera, size, [600, 100], 2);
  assert.deepEqual(viewport.screenToWorld(zoomed, size, [600, 100]), anchor);
  assert.equal(zoomed.zoom, 2);
  assert.deepEqual(viewport.panCamera(zoomed, 20, -10), { ...zoomed, centerX: zoomed.centerX - 10, centerY: zoomed.centerY + 5 });
  const framed = viewport.frameCamera({ x: 1400, y: 200, width: 2100, height: 1000 }, size, 50);
  assert.equal(framed.centerX, 2450);
  assert.ok(framed.zoom > 0.3 && framed.zoom < 0.34);
  assert.equal(viewport.clampViewZoom(1000), viewport.VIEW_ZOOM_MAX);
});

test('instances are expandable in the tree only when a resolver is supplied, and collapse on demand', () => {
  const collapsed = sceneTreeRows(world, resolve, () => false);
  const instance = collapsed.find((row) => row.kind === 'instance');
  assert.equal(instance.expandable, true);
  assert.equal(instance.expanded, false);
  assert.equal(collapsed.some((row) => row.readOnly), false);
  const expanded = sceneTreeRows(world, resolve, (key) => key === instance.key);
  assert.ok(expanded.some((row) => row.kind === 'node' && row.readOnly && row.key === 'camp-1:root'));
  // Nested instance rows carry their containing path so selection can map to composed keys.
  assert.deepEqual(expanded.find((row) => row.kind === 'instance' && row.instanceId === 'crate').instancePath, ['camp-1']);
  const unresolved = sceneTreeRows(world);
  assert.equal(unresolved.find((row) => row.kind === 'instance').expandable, false);
});

test('preview isolation keeps sibling order dense after stripping script subtrees', () => {
  const document = {
    version: 1, sceneId: 'preview.order', rootNodeId: 'root', instances: [{ instanceId: 'i', name: 'I', sceneId: 'object.prop', parentNodeId: 'root', order: 3, overrides: [] }],
    nodes: [
      { id: 'root', name: 'Root', type: 'Node2D', parentId: null, order: 0, properties: {} },
      { id: 'a', name: 'A', type: 'Node2D', parentId: 'root', order: 0, properties: {} },
      { id: 'script', name: 'Script', type: 'ScriptNode', scriptId: 'x', parentId: 'root', order: 1, properties: {} },
      { id: 'b', name: 'B', type: 'Node2D', parentId: 'root', order: 2, properties: {} },
    ],
  };
  const isolated = preview.isolatedPreviewDocument(document);
  assert.deepEqual(isolated.nodes.filter((node) => node.parentId === 'root').map((node) => [node.id, node.order]), [['a', 0], ['b', 1]]);
  assert.equal(isolated.instances[0].order, 2);
});
