import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const read = (path) => readFile(new URL(`../../../${path}`, import.meta.url), 'utf8');

test('production mounts authored HUD and weapon hotbar through the universal Control runtime', async () => {
  const [config, world, controller] = await Promise.all([
    read('src/game/config.ts'),
    read('src/game/scenes/WorldScene.ts'),
    read('src/game/features/world/UniversalSceneWorldController.ts'),
  ]);

  assert.match(config, /sceneId\('ui\.hud'\)/);
  assert.match(config, /sceneId\('ui\.weapon-hotbar'\)/);
  assert.match(config, /data-scene-ui-root/);
  assert.match(controller, /new HtmlControlPresentationAdapter/);
  assert.match(controller, /mountScene\(sceneId\('ui\.hud'\)/);
  assert.match(controller, /mountScene\(sceneId\('ui\.weapon-hotbar'\)/);
  assert.match(controller, /\[UI_SURFACE_SERVICE\]: uiSurfaces/);
  assert.doesNotMatch(world, /new HUD\(/);
  assert.doesNotMatch(world, /new WeaponHotbar\(/);
  assert.doesNotMatch(world, /from ['"]\.\.\/HUD['"]/);
});

test('the HUD surface adapter is read-only and owns event cleanup', async () => {
  const source = await read('src/game/features/ui/HudSurfacePort.ts');
  assert.match(source, /snapshot\(surfaceId: string\)/);
  assert.match(source, /invoke\(\): void/);
  assert.match(source, /gameEvents\.on\('hp\.changed'/);
  assert.match(source, /gameEvents\.off\('hp\.changed'/);
  assert.match(source, /this\.listeners\.clear\(\)/);
});
