import assert from 'node:assert/strict';
import test from 'node:test';

import { embedOwnedResources } from '../../lib/scene-conversion/embed-owned-resources.mjs';

const json = (value) => `${JSON.stringify(value, null, 2)}\n`;
const output = (unitKey, path, document) => ({ unitKey, path, content: json(document), consumedFieldPaths: [`$.${unitKey}`], intentionallyRetainedFields: [] });
const scene = (sceneId, references, subresources = []) => ({
  version: 1, sceneId, rootNodeId: 'root', instances: [],
  nodes: [{ id: 'root', name: 'Root', type: 'Node2D', parentId: null, order: 0, properties: Object.fromEntries(references.map((id, index) => [`ref${index}`, { resourceId: id }])) }],
  subresources,
});
const shape = (resourceId) => ({ version: 1, resourceId, kind: 'collision-shape', value: { shape: 'rectangle', width: 4, height: 4 } });
const parse = (outputs) => Object.fromEntries(outputs.map((entry) => [entry.path, JSON.parse(entry.content)]));

test('single-owner resources are embedded and their units recorded as contributions', () => {
  const outputs = embedOwnedResources([
    output('character:a', 'characters/a.scene.json', scene('a', ['a.shape', 'shared.shape'])),
    output('character:b', 'characters/b.scene.json', scene('b', ['shared.shape'])),
    output('visual:a', 'resources/a.shape.resource.json', shape('a.shape')),
    output('visual:shared', 'resources/shared.shape.resource.json', shape('shared.shape')),
  ]);
  const documents = parse(outputs);
  assert.deepEqual(Object.keys(documents).sort(), ['characters/a.scene.json', 'characters/b.scene.json', 'resources/shared.shape.resource.json']);
  assert.deepEqual(documents['characters/a.scene.json'].subresources.map((resource) => resource.resourceId), ['a.shape']);
  const owner = outputs.find((entry) => entry.path === 'characters/a.scene.json');
  assert.deepEqual(owner.contributions, [{ unitKey: 'visual:a', consumedFieldPaths: ['$.visual:a'], intentionallyRetainedFields: [] }]);
});

test('resources referenced by another resource or of other kinds stay standalone', () => {
  const tileSet = { version: 1, resourceId: 'tiles', kind: 'tile-set', tiles: {} };
  const data = { version: 1, resourceId: 'map.data', kind: 'tile-data', tileSet: 'tiles', columns: 1, rows: 1, cells: [] };
  const outputs = embedOwnedResources([
    output('map:m', 'worlds/m.scene.json', scene('m', ['map.data', 'tiles'])),
    output('terrain:t', 'resources/tiles.tile-set.resource.json', tileSet),
    output('map:m', 'resources/map.data.resource.json', data),
  ]);
  const documents = parse(outputs);
  assert.deepEqual(documents['worlds/m.scene.json'].subresources.map((resource) => resource.resourceId), ['map.data'], 'tile data embeds');
  assert.ok(documents['resources/tiles.tile-set.resource.json'], 'the tile set is referenced by tile data and is not an embeddable kind');
  assert.equal(outputs.find((entry) => entry.path === 'worlds/m.scene.json').contributions, undefined, 'same-unit resources merge into the scene output itself');
});

test('a partial run carries over resources the scene already embeds on disk', () => {
  const existing = scene('a', ['a.shape'], [shape('a.shape')]);
  const outputs = embedOwnedResources([output('character:a', 'characters/a.scene.json', scene('a', ['a.shape']))], { existingScenes: [existing] });
  assert.deepEqual(parse(outputs)['characters/a.scene.json'].subresources, [shape('a.shape')]);
});
