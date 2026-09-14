import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const { PreparedSceneContent } = await loadTypescriptModule('src/game/infrastructure/scenes/PreparedSceneContent.ts');

const scene = (sceneId, resourceId) => ({
  version: 1,
  sceneId,
  rootNodeId: 'root',
  nodes: [{ id: 'root', name: 'Root', type: 'Sprite2D', parentId: null, order: 0, properties: { texture: { resourceId } } }],
  instances: [],
});

test('prepared content validates once, caches selected packed scenes, and releases every lease', async () => {
  const resource = { version: 1, resourceId: 'fixture.sprite', kind: 'texture', assetId: 'fixture.asset' };
  const content = await PreparedSceneContent.prepare({
    scenes: [scene('fixture.one', resource.resourceId), scene('fixture.two', resource.resourceId)],
    resources: [resource],
    registry: t.createGameDescriptorRegistry(),
    sceneIds: ['fixture.two', 'fixture.one', 'fixture.one'],
    hasAsset: (assetId) => assetId === 'fixture.asset',
  });
  assert.equal(content.get('fixture.one').definition.sourceSceneId, 'fixture.one');
  assert.equal(content.get('fixture.two').definition.sourceSceneId, 'fixture.two');
  assert.equal(content.documents.activeLeaseCount(), 2);
  assert.equal(content.resourceLoader.activeLeaseCount(), 2);
  assert.throws(() => content.get('fixture.missing'), /not prepared/);
  content.dispose();
  assert.equal(content.documents.activeLeaseCount(), 0);
  assert.equal(content.resourceLoader.activeLeaseCount(), 0);
  assert.throws(() => content.get('fixture.one'), /disposed/);
});
