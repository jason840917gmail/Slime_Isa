import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'vite';

const vite = await createServer({ configFile: false, root: process.cwd(), appType: 'custom', optimizeDeps: { noDiscovery: true }, server: { middlewareMode: true, hmr: false } });
const { parseMapFile, MapValidationError } = await vite.ssrLoadModule('/src/game/content/maps/mapFormat.ts');
const { validateMapReferences } = await vite.ssrLoadModule('/src/game/content/maps/validateMapReferences.ts');
const { validateCharacterPackage } = await vite.ssrLoadModule('/src/game/content/characters/validation.ts');
const fixture = (await vite.ssrLoadModule('/src/game/content/maps/test-rectangle.map.json')).default;
const levelOne = (await vite.ssrLoadModule('/src/game/content/maps/level-1.map.json')).default;
const fattyCharacter = (await vite.ssrLoadModule('/src/game/content/characters/fatty-one-eye/character.json')).default;
const fattyVisualSet = (await vite.ssrLoadModule('/src/game/content/characters/fatty-one-eye/visual-set.json')).default;
test.after(async () => vite.close());

function camp(overrides = {}) {
  return {
    id: 'boss-camp-01', bossId: 'fatty-one-eye', spawn: { x: 256, y: 160 },
    activationPerimeter: { shape: 'circle', x: 256, y: 160, radius: 120 },
    arenaPerimeter: { shape: 'circle', x: 256, y: 160, radius: 100 },
    respawnMs: 180000,
    ...overrides,
  };
}

function mapWith(camps, objects = []) {
  const map = structuredClone(fixture);
  map.mapId = 'boss-contract';
  map.bossCamps = camps;
  map.objects.push(...objects);
  return map;
}

test('chestless circular boss camps are valid and Level 1 preserves editable concentric circles', () => {
  assert.equal(parseMapFile(mapWith([camp()]), 'fixture').bossCamps[0].guardedChestInstanceId, undefined);
  const parsed = parseMapFile(levelOne, 'level-1');
  const authored = parsed.bossCamps[0];
  assert.deepEqual(authored.spawn, { x: 2528, y: 1472 });
  assert.equal(authored.activationPerimeter.shape, 'circle');
  assert.equal(authored.arenaPerimeter.shape, 'circle');
  assert.deepEqual(
    { x: authored.activationPerimeter.x, y: authored.activationPerimeter.y },
    authored.spawn,
  );
  assert.deepEqual(
    { x: authored.arenaPerimeter.x, y: authored.arenaPerimeter.y },
    authored.spawn,
  );
  assert.ok(authored.activationPerimeter.radius >= authored.arenaPerimeter.radius);
});

for (const [name, invalid] of [
  ['rectangular perimeter', camp({ activationPerimeter: { shape: 'rectangle', x: 10, y: 10, w: 300, h: 300 } })],
  ['off-center perimeter', camp({ arenaPerimeter: { shape: 'circle', x: 257, y: 160, radius: 100 } })],
  ['arena larger than activation', camp({ arenaPerimeter: { shape: 'circle', x: 256, y: 160, radius: 121 } })],
  ['circle outside map', camp({ spawn: { x: 50, y: 50 }, activationPerimeter: { shape: 'circle', x: 50, y: 50, radius: 200 }, arenaPerimeter: { shape: 'circle', x: 50, y: 50, radius: 100 } })],
]) test(`rejects ${name}`, () => assert.throws(() => parseMapFile(mapWith([invalid]), name), MapValidationError));

test('duplicate optional chest ownership is rejected', () => {
  const first = camp({ guardedChestInstanceId: 'chest-1' });
  const second = camp({ id: 'boss-camp-02', guardedChestInstanceId: 'chest-1' });
  assert.throws(() => parseMapFile(mapWith([first, second]), 'duplicate'), MapValidationError);
});

test('reference validation reports unknown bosses and only validates a chest when assigned', () => {
  const resolver = {
    isWorldTileId: () => true, getObjectReference: () => ({ kind: 'object' }), getNpcReference: () => undefined,
    getNpcBody: () => undefined, isEnemyId: () => true, isBossId: () => false, isItemId: () => true, hasMap: () => true,
  };
  const issues = validateMapReferences(parseMapFile(mapWith([camp()]), 'refs'), resolver);
  assert.deepEqual(issues, ["bossCamps[0].bossId: unknown boss 'fatty-one-eye'"]);
});

test('Fatty boss character package passes the shared Character Studio contract', () => {
  assert.deepEqual(validateCharacterPackage({ character: fattyCharacter, visualSet: fattyVisualSet }), []);
});
