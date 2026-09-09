import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const root = new URL('../../../', import.meta.url);
const readJson = (path) => JSON.parse(readFileSync(new URL(path, root), 'utf8'));
const npcPackageIds = ['village-elder-plop', 'mossy-scout', 'lili', 'red-slime-boy', 'yellow-blond-slime-girl'];

test('NPC packages expose the required role and directional clips', () => {
  for (const id of npcPackageIds) {
    const character = readJson(`src/game/content/characters/${id}/character.json`);
    const visual = readJson(`src/game/content/characters/${id}/visual-set.json`);
    assert.equal(character.kind, 'npc');
    assert.deepEqual(Object.keys(character.hitboxes), []);
    assert.deepEqual(Object.keys(visual.clips), ['idle', 'walk-down', 'walk-up', 'walk-left', 'walk-right']);
    assert.ok(character.npc.wanderSpeed > 0);
  }
});

test('level 1 assigns one personal area to each NPC placement', () => {
  const map = readJson('src/game/content/maps/level-1.map.json');
  const npcObjects = map.objects.filter((object) => object.objectId.startsWith('npc.'));
  assert.deepEqual(npcObjects.map((object) => object.visualId).sort(), [...npcPackageIds].sort());
  assert.equal(map.npcWanderAreas.length, npcObjects.length);
  assert.equal(new Set(map.npcWanderAreas.map((area) => area.npcInstanceId)).size, npcObjects.length);
  for (const area of map.npcWanderAreas) assert.ok(npcObjects.some((object) => object.instanceId === area.npcInstanceId));
  assert.deepEqual(map.npcWanderAreas.find((area) => area.npcInstanceId === 'level-1-npc-village-elder-plop')?.perimeter, {
    shape: 'circle', x: 512, y: 704, radius: 96,
  });
  assert.deepEqual(map.npcWanderAreas.find((area) => area.npcInstanceId === 'level-1-npc-mossy-scout')?.perimeter, {
    shape: 'rectangle', x: 672, y: 640, w: 192, h: 128,
  });
});

test('NPC object archetypes use placement visuals instead of legacy variants', () => {
  for (const file of ['npc-world.json', 'npc-world-scout.json', 'npc-lili.json', 'npc-red-slime-boy.json', 'npc-yellow-blond-slime-girl.json']) {
    const object = readJson(`src/game/content/objects/npcs/${file}`);
    assert.equal(object.variants, undefined);
    assert.equal(typeof object.npc.placementVisualId, 'string');
  }
});

test('every placed NPC sheet is loaded by the boot bundle', () => {
  const manifest = readJson('asset/assets.json');
  for (const id of npcPackageIds) {
    const visual = readJson(`src/game/content/characters/${id}/visual-set.json`);
    assert.ok(manifest.bundles.boot.includes(visual.assetId), `${id} would spawn without its texture`);
    assert.ok(manifest.assets[visual.assetId], `${id} must resolve to a registered sheet`);
  }
});
