import assert from 'node:assert/strict';
import test from 'node:test';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const preview = await loadTypescriptModule('src/game/editor/scene-studio/ScenePreview.ts');

test('preview removes scripts and gameplay connections and never grants domain or persistence capabilities', () => {
  const document = { version: 1, sceneId: 'preview.fixture', rootNodeId: 'root', nodes: [{ id: 'root', name: 'Root', type: 'Node', parentId: null, order: 0, properties: {} }, { id: 'malicious', name: 'Malicious', type: 'ScriptNode', scriptId: 'fixture.malicious', parentId: 'root', order: 0, properties: {} }], instances: [], connections: [{ source: { nodeId: 'root' }, signal: 'ready', target: { nodeId: 'malicious' }, handler: 'writeSave' }] };
  const isolated = preview.isolatedPreviewDocument(document);
  assert.deepEqual(isolated.nodes.map((node) => node.id), ['root']);
  assert.deepEqual(isolated.connections, []);
  for (const capability of preview.FORBIDDEN_PREVIEW_CAPABILITIES) assert.equal(preview.PREVIEW_CAPABILITIES.has(capability), false);
  let disposed = false;
  const session = new preview.ScenePreview({ create(received, capabilities) { assert.equal(received.nodes.some((node) => node.type === 'ScriptNode'), false); assert.equal(capabilities.has('persistence'), false); return { dispose() { disposed = true; }, resourceCount: () => 2 }; } });
  session.open(document);
  assert.equal(session.resourceCount, 2);
  session.close();
  assert.equal(disposed, true);
  assert.equal(session.resourceCount, 0);
});
