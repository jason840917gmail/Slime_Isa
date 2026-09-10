import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const root = process.cwd();
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8');

test('legacy runtime map populations stay removed', () => {
  const deletedModules = [
    'src/game/Friend.ts',
    'src/game/ChatUI.ts',
    'src/game/ShopUI.ts',
    'src/game/House.ts',
    'src/game/systems/HouseSystem.ts',
    'src/game/features/houses/HousePlacement.ts',
    'src/game/features/dungeon/CrystalTrialController.ts',
  ];
  for (const modulePath of deletedModules) {
    assert.equal(fs.existsSync(path.join(root, modulePath)), false, `${modulePath} must stay removed`);
  }

  const worldScene = read('src/game/scenes/WorldScene.ts');
  assert.doesNotMatch(worldScene, /createFriends|spawnFriend|friendCountForArea|CrystalTrial|dungeonSwitch|dungeonChest/);
  assert.doesNotMatch(worldScene, /currentArea\.biome\s*===/);

  const proceduralAssets = read('src/game/infrastructure/assets/ProceduralAssetScene.ts');
  assert.doesNotMatch(proceduralAssets, /friend-face|friend-ear|crystal-switch|crystal-chest|big-blue-house/);
});

test('persistent authored objects enter gameplay through MapBuilder', () => {
  const worldScene = read('src/game/scenes/WorldScene.ts');
  const mapBuilder = read('src/game/features/world/MapBuilder.ts');
  assert.match(worldScene, /new MapBuilder\(/);
  assert.match(mapBuilder, /for \(const object of this\.ctx\.map\.objects\)/);
  assert.match(mapBuilder, /this\.objectFactory\.create\(/);
});
