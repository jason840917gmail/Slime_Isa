import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';
import test from 'node:test';

const domainFiles = [
  'src/game/features/player/PlayerAbilityPresentation.ts',
  'src/game/features/player/PlayerAbilityService.ts',
  'src/game/features/player/PlayerHealthService.ts',
  'src/game/features/player/PlayerNodePorts.ts',
  'src/game/features/player/PlayerServicePorts.ts',
  'src/game/features/scripts/PlayerScript.ts',
];

test('player domain services and PlayerScript stay engine and legacy-combat neutral', async () => {
  for (const path of domainFiles) {
    const source = await readFile(path, 'utf8');
    for (const forbidden of [
      /from ['"]phaser['"]/,
      /\bHitbox\b/,
      /\bTargetDummy\b/,
      /\bscene\.time\b/,
      /\bscene\.add\b/,
      /\bscene\.tweens\b/,
      /\bnew Phaser\b/,
    ]) {
      assert.doesNotMatch(source, forbidden, `${path} crosses the player domain boundary`);
    }
  }
});

test('production player construction has no PlayerFactory or compatibility proxy', async () => {
  const [worldScene, universalWorld] = await Promise.all([
    readFile('src/game/scenes/WorldScene.ts', 'utf8'),
    readFile('src/game/features/world/UniversalSceneWorldController.ts', 'utf8'),
  ]);
  assert.doesNotMatch(worldScene, /PlayerFactory|createPlayerEntity/);
  assert.doesNotMatch(universalWorld, /synchronizeLegacyPlayerProxy|synchronizeManagedPlayer/);
  assert.doesNotMatch(universalWorld, /\.visible\s*=\s*false/);
  assert.match(universalWorld, /playerPhysicsSprite/);
  assert.match(universalWorld, /playerPresentation/);
});

test('legacy player wrappers do not remain domain systems', async () => {
  await assert.rejects(access('src/game/systems/AbilitySystem.ts'));
  await assert.rejects(access('src/game/systems/HealthSystem.ts'));
  const [abilityController, healthAdapter] = await Promise.all([
    readFile('src/game/features/player/PlayerAbilityController.ts', 'utf8'),
    readFile('src/game/infrastructure/scenes/compatibility/LegacyPlayerHealthAdapter.ts', 'utf8'),
  ]);
  assert.match(abilityController, /class PlayerAbilityController/);
  assert.match(healthAdapter, /class LegacyPlayerHealthAdapter/);
});
