import assert from 'node:assert/strict';
import test from 'node:test';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const resources = await loadTypescriptModule('src/game/editor/scene-studio/ResourceBrowser.ts');
const inspector = await loadTypescriptModule('src/game/editor/scene-studio/ResourceInspector.ts');

const document = { version: 1, sceneId: 'resource.fixture', rootNodeId: 'root', nodes: [{ id: 'root', name: 'Root', type: 'Node', parentId: null, order: 0, properties: { theme: { resourceId: 'theme.shared' } } }], instances: [], subresources: [] };

test('resource consumers are explicit and make-unique changes only the chosen local owner', () => {
  assert.deepEqual(resources.resourceConsumers(document, 'theme.shared').map((entry) => entry.ownerId), ['root']);
  const shared = { version: 1, resourceId: 'theme.shared', kind: 'theme', values: { color: 'green' } };
  const result = resources.makeResourceUniqueForNode('root', 'theme', shared, 'theme.local').apply(document).document;
  assert.equal(result.subresources[0].resourceId, 'theme.local');
  assert.deepEqual(result.nodes[0].properties.theme, { resourceId: 'theme.local' });
  assert.deepEqual(shared.values, { color: 'green' });
});

test('resource inspector edits data without permitting identity mutation', () => {
  const shared = { version: 1, resourceId: 'theme.shared', kind: 'theme', values: { color: 'green' } };
  assert.deepEqual(inspector.editResourceField(shared, 'values', { color: 'amber' }).values, { color: 'amber' });
  assert.throws(() => inspector.editResourceField(shared, 'resourceId', 'other'), /identity field/);
});
