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

test('persistent authored objects enter gameplay through the packed world root', () => {
  const worldScene = read('src/game/scenes/WorldScene.ts');
  const universalWorld = read('src/game/features/world/UniversalSceneWorldController.ts');
  assert.doesNotMatch(worldScene, /MapBuilder|LegacyMapPlacementBridge|BossCampController|NpcRuntimeController|ChestController/);
  assert.match(worldScene, /worldSceneId: this\.loadedWorld\.sceneId/);
  assert.match(universalWorld, /this\.runtime\.mountScene\(this\.options\.worldSceneId/);
  assert.match(universalWorld, /descendants\(mount\.root, ResourceNodeScript\)/);
  assert.match(universalWorld, /descendants\(mount\.root, NpcScript\)/);
  assert.match(universalWorld, /descendants\(mount\.root, BossCampScript\)/);
  assert.equal(
    fs.existsSync(path.join(root, 'src/game/infrastructure/scenes/compatibility/LegacyMapPlacementBridge.ts')),
    false,
  );
});

test('production world loading and population no longer invoke legacy map construction', () => {
  const loadScene = read('src/game/scenes/MapLoadScene.ts');
  const combat = read('src/game/features/combat/CombatController.ts');
  assert.doesNotMatch(loadScene, /MapRepository|mapRepository/);
  assert.match(loadScene, /new WorldSceneLoader\(content\)/);
  assert.doesNotMatch(combat, /\bEnemySpawner\b/);
  assert.match(combat, /AuthoredEnemyPopulationController/);
});
