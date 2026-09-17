import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';

import { loadAuthoredSceneContent } from '../helpers/load-authored-scene-content.mjs';
import { loadTypescriptModule, REPOSITORY_ROOT } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');
const content = await loadAuthoredSceneContent();
const mapRoot = path.join(REPOSITORY_ROOT, 'src/game/content/maps');
const reportRoot = path.join(REPOSITORY_ROOT, 'src/game/content/scenes/authored/reports/worlds');

async function json(file) {
  return JSON.parse(await readFile(file, 'utf8'));
}

test('every authored map placement has exactly one reported scene owner', async () => {
  const mapFiles = (await readdir(mapRoot)).filter((name) => name.endsWith('.map.json')).sort();
  assert.equal(mapFiles.length, 15);
  for (const name of mapFiles) {
    const map = await json(path.join(mapRoot, name));
    const report = await json(path.join(reportRoot, `${map.mapId}.mapping.json`));
    const world = content.scenes.find((scene) => scene.sceneId === `world.${map.mapId}`);
    assert.ok(world, `missing world.${map.mapId}`);
    assert.deepEqual(report.sourceCounts, {
      objects: map.objects.length,
      bossCamps: map.bossCamps?.length ?? 0,
    });
    assert.equal(report.placements.length, map.objects.length + (map.bossCamps?.length ?? 0));
    assert.equal(world.instances.length, report.worldInstanceCount);
    assert.equal(new Set(world.instances.map((instance) => instance.instanceId)).size, world.instances.length);
    assert.equal(new Set(world.instances.map((instance) => instance.persistenceKey)).size, world.instances.length);

    const sourceKeys = report.placements.map((placement) => `${placement.sourceKind}:${placement.sourceId}`);
    assert.equal(new Set(sourceKeys).size, sourceKeys.length, `${map.mapId} has duplicate mapping rows`);
    for (const object of map.objects) assert.ok(sourceKeys.includes(`object:${object.instanceId}`), `${map.mapId} lost ${object.instanceId}`);
    for (const camp of map.bossCamps ?? []) assert.ok(sourceKeys.includes(`boss-camp:${camp.id}`), `${map.mapId} lost ${camp.id}`);
  }
});

test('world preparation preserves placement transforms, identities, persistence, and nested encounter ownership', async () => {
  const descriptors = t.createGameDescriptorRegistry();
  const documents = new t.SceneDocumentLoader(async (id) => content.scenes.find((scene) => scene.sceneId === id));
  const resources = new t.SceneResourceLoader(async (id) => content.resources.find((resource) => resource.resourceId === id));
  const resolver = new t.SceneResolver({ documents, resources, registry: descriptors });

  const rectangle = await resolver.prepare_scene('world.test-rectangle');
  const amberRoot = rectangle.definition.nodes.find((node) => node.key === 'amber-rock-001/body');
  const amberScript = rectangle.definition.nodes.find((node) => node.key === 'amber-rock-001/script');
  assert.equal(amberRoot.persistenceKey, 'test-rectangle.amber-rock-001');
  assert.deepEqual(amberRoot.properties.position, [288, 192]);
  assert.deepEqual(
    { mapId: amberScript.properties.mapId, instanceId: amberScript.properties.instanceId, initialHealth: amberScript.properties.initialHealth },
    { mapId: 'test-rectangle', instanceId: 'amber-rock-001', initialHealth: 30 },
  );
  rectangle.dispose();

  const levelOne = await resolver.prepare_scene('world.level-1');
  const campRoot = levelOne.definition.nodes.find((node) => node.key === 'level-1-fatty-one-eye-camp/root');
  const guardedChest = levelOne.definition.nodes.find((node) => node.key === 'level-1-fatty-one-eye-camp/guarded-chest/body');
  assert.equal(campRoot.persistenceKey, 'level-1-fatty-one-eye-camp');
  assert.deepEqual(campRoot.properties.position, [2528, 1472]);
  assert.equal(guardedChest.provenance.authoredInstanceId, 'guarded-chest');
  assert.equal(levelOne.definition.nodes.some((node) => node.key.startsWith('level-1-fatty-guarded-chest/')), false);
  levelOne.dispose();

  assert.equal(documents.activeLeaseCount(), 0);
  assert.equal(resources.activeLeaseCount(), 0);
});
