import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/infrastructure/scenes/tooling.ts');
const registry = t.createCoreDescriptorRegistry();
const simple = { version: 1, sceneId: 'simple', rootNodeId: 'root', nodes: [{ id: 'root', name: 'Root', type: 'Node', parentId: null, order: 0, properties: {} }], instances: [] };

test('cancellation ignores late document success without acquiring a lease', async () => {
  let finish;
  const loader = new t.SceneDocumentLoader(() => new Promise((resolve) => { finish = resolve; }));
  const controller = new AbortController();
  const pending = new t.SceneResolver({ documents: loader, registry }).prepare_scene('simple', controller.signal);
  controller.abort();
  await assert.rejects(pending, { name: 'AbortError' });
  finish(simple);
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(loader.activeLeaseCount(), 0);
  assert.equal(loader.hasCached('simple'), true);
});

test('resource failure releases every document and resource lease owned by the request', async () => {
  const scene = { ...simple, sceneId: 'resource-scene', nodes: [{ id: 'root', name: 'Root', type: 'Sprite2D', parentId: null, order: 0, properties: { texture: { resourceId: 'missing.texture' } } }] };
  const documents = new t.SceneDocumentLoader(async () => scene);
  const resources = new t.SceneResourceLoader(async () => { throw new Error('resource unavailable'); });
  await assert.rejects(new t.SceneResolver({ documents, resources, registry }).prepare_scene('resource-scene'), /resource unavailable/);
  assert.equal(documents.activeLeaseCount(), 0);
  assert.equal(resources.activeLeaseCount(), 0);
});

test('an initiating node aborts its in-flight scene preparation when it exits', async () => {
  let finish;
  const loader = new t.SceneDocumentLoader(() => new Promise((resolve) => { finish = resolve; }));
  let pending;
  class LoaderNode extends t.Node {
    _ready() {
      const controller = this.create_entry_abort_controller();
      pending = new t.SceneResolver({ documents: loader, registry }).prepare_scene('simple', controller.signal);
    }
  }
  const host = new t.Node({ runtimeId: 'host/root', name: 'Host' });
  const initiator = new LoaderNode({ runtimeId: 'host/loader', name: 'Loader' });
  host.add_child(initiator);
  const tree = new t.SceneTree(); tree.setRoot(host);
  host.remove_child(initiator); tree.flushMutations();
  await assert.rejects(pending, { name: 'AbortError' });
  finish(simple);
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(loader.activeLeaseCount(), 0);
});
