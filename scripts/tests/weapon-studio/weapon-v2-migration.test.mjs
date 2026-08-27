import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let migration;
let animation;
let validation;
let normalize;

async function loadTypeScriptModule(entryPoint) {
  const result = await build({ absWorkingDir: repositoryRoot, entryPoints: [entryPoint], bundle: true, format: 'esm', platform: 'node', write: false });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

before(async () => {
  [migration, animation, validation, normalize] = await Promise.all([
    loadTypeScriptModule('src/game/content/weapons/migrateLegacyWeapon.ts'),
    loadTypeScriptModule('src/game/shared/animation/index.ts'),
    loadTypeScriptModule('src/game/content/weapons/validation.ts'),
    loadTypeScriptModule('src/game/content/weapons/normalize.ts'),
  ]);
});

function weaponFixture(overrides = {}) {
  const idle = { frames: [0, 1], keyframeTimes: [0, 2], durationSeconds: 0.4, framesPerSecond: 10, loop: true, loopMode: 'ping-pong' };
  const attack = {
    frames: [2, 3], keyframeTimes: [0, 3], durationSeconds: 0.5, framesPerSecond: 10, loop: true, loopMode: 'wrap',
    frameTransforms: { '1': { offset: [2, 3], scale: [1.5, 1], rotationDeg: 30 } },
  };
  return {
    version: 1, weaponId: 'fixture-sword', displayName: 'Fixture Sword', category: 'melee',
    characterActionId: 'attack-1', assetId: 'weapon.fixture',
    animations: { idle, attack, impact: { frames: [4], framesPerSecond: 10, loop: false } },
    visual: {
      sourceOffset: [5, 6], origin: [0.25, 0.75], scale: [0.5, 0.75],
      animationOffsets: { 'attack-right': [10, 20] }, frameOffsets: { '3': [30, 40] },
    },
    hitboxes: { primary: { shape: 'rectangle', width: 10, height: 8, offsetX: 12, offsetY: 1 } },
    attackTrack: {
      hitboxSpans: [{ hitboxId: 'primary', from: 1, through: 2 }],
      events: [{ at: 2, eventId: 'weapon.impact' }, { at: 3, eventId: 'sound.swing' }],
    },
    baseDamage: 10, cooldownMs: 100, hitboxWidth: 10, hitboxHeight: 8, hitboxOffset: 12,
    hitboxDurationMs: 100, knockStrength: 5, vfxColor: 0xffffff, unlockLevel: 1,
    iconKey: 'fixture', description: 'Fixture', ...overrides,
  };
}

test('legacy migration preserves expanded frames and occurrence transforms without mutating input', () => {
  const weapon = weaponFixture();
  const source = structuredClone(weapon);
  const migrated = migration.migrateLegacyWeaponDefinition(weapon);
  assert.deepEqual(weapon, source);
  assert.equal(migrated.iconFrame, 0);

  const legacyExpanded = animation.expandAnimationClip(animation.normalizeAnimationClip(weapon.animations.attack));
  const layered = animation.normalizeLayeredAnimation(migrated.directionalAttacks.right.animation);
  const layeredFrames = Array.from({ length: animation.layeredTimelineFrameCount(layered) }, (_, frame) => (
    animation.resolveLayeredAnimationFrame(layered, frame)[0].sourceFrame
  ));
  assert.deepEqual(layeredFrames, legacyExpanded.sourceFrames);
  assert.equal(layered.loop, false);
  assert.equal(migrated.animations.idle.loop, true);
  assert.equal(migrated.animations.idle.loopMode, 'ping-pong');

  const secondBlock = migrated.directionalAttacks.right.animation.layers[0].blocks[1];
  assert.deepEqual(secondBlock.transform.offset, [22, 23]);
  assert.deepEqual(secondBlock.transform.scale, [1.5, 1]);
  assert.equal(secondBlock.transform.rotationDeg, 30);
  assert.deepEqual(migrated.directionalAttacks.right.animation.layers[0].transform.offset, [10, 20]);
  assert.deepEqual(migrated.directionalAttacks.right.animation.layers[0].transform.origin, [0.25, 0.75]);
});

test('legacy migration preserves an explicit icon frame', () => {
  const migrated = migration.migrateLegacyWeaponDefinition(weaponFixture({ iconFrame: 7 }));
  assert.equal(migrated.iconKey, 'fixture');
  assert.equal(migrated.iconFrame, 7);
});

test('legacy migration preserves targeting data', () => {
  const damageModifiers = [{ targetTag: 'wood', modifier: 0.5 }];
  const harvestCapabilities = { wood: 1, stone: 2 };
  const migrated = migration.migrateLegacyWeaponDefinition(weaponFixture({ damageModifiers, harvestCapabilities }));
  assert.deepEqual(migrated.damageModifiers, damageModifiers);
  assert.deepEqual(migrated.harvestCapabilities, harvestCapabilities);
});

test('targeting validation requires canonical tags and integer capability tiers', () => {
  const valid = migration.migrateLegacyWeaponDefinition(weaponFixture({
    damageModifiers: [{ targetTag: 'stone', modifier: 0.25 }],
    harvestCapabilities: { wood: 1, stone: 2 },
  }));
  assert.deepEqual(validation.validateWeaponDefinition(valid), []);

  const invalid = {
    ...valid,
    damageModifiers: [{ targetTag: 'stone', modifier: 1 }, { targetTag: ' stone ', modifier: 0.5 }],
    harvestCapabilities: { ' ': 1, ' wood ': 2, stone: 0, metal: 1.5 },
  };
  const issues = validation.validateWeaponDefinition(invalid);
  assert.ok(issues.some((issue) => issue.includes('surrounding whitespace')));
  assert.ok(issues.some((issue) => issue.includes("duplicate 'stone'")));
  assert.ok(issues.some((issue) => issue.includes('target tag must be non-empty')));
  assert.ok(issues.some((issue) => issue.includes('tier must be an integer >= 1')));
  assert.ok(validation.validateWeaponDefinition({ ...valid, harvestCapabilities: [] }).some((issue) => issue.includes('must be an object')));
});

test('migration removes legacy Impact events and omits root legacy storage fields', () => {
  const migrated = migration.migrateLegacyWeaponDefinition(weaponFixture(), { onHitEffectId: 'fixture-impact' });
  assert.equal(migrated.version, 2);
  assert.equal(migrated.onHitEffectId, 'fixture-impact');
  assert.deepEqual(migrated.directionalAttacks.right.attackTrack.events.map((event) => event.eventId), ['sound.swing']);
  for (const field of ['assetId', 'visual', 'attackTrack', 'hitboxes', 'animKey']) assert.equal(field in migrated, false);
  assert.equal('impact' in migrated.animations, false);
  assert.equal('attack' in migrated.animations, false);
});

test('normalization accepts both package versions and coerces attacks to one shot', () => {
  const legacy = normalize.normalizeWeaponDefinition(weaponFixture());
  const layered = migration.migrateLegacyWeaponDefinition(weaponFixture());
  layered.directionalAttacks.right.animation.loop = true;
  const current = normalize.normalizeWeaponDefinition(layered);
  assert.equal(legacy.sourceVersion, 1);
  assert.equal(current.sourceVersion, 2);
  assert.equal(current.directionalAttacks.right.animation.loop, false);
  assert.equal(current.directionalAttacks.left.presentation, 'mirror-right');
});

test('v2 weapons inherit missing UP from DOWN without duplicating gameplay data', () => {
  const weapon = migration.migrateLegacyWeaponDefinition(weaponFixture());
  delete weapon.directionalAttacks.up;
  assert.deepEqual(validation.validateWeaponDefinition(weapon), []);
  const normalized = normalize.normalizeWeaponDefinition(weapon);
  const up = normalized.directionalAttacks.up;
  const down = normalized.directionalAttacks.down;
  assert.equal(up.presentation, 'mirror-down');
  assert.equal(up.sourceDirection, 'down');
  assert.equal(up.mirrorX, false);
  assert.equal(up.mirrorY, true);
  assert.equal(up.presentationOffsetY, 20);
  assert.deepEqual(up.hitboxes, down.hitboxes);
  assert.deepEqual(up.attackTrack, down.attackTrack);
  assert.equal(up.characterActionId, down.characterActionId);
});

test('v2 validation rejects missing directions and root legacy fields', () => {
  const valid = migration.migrateLegacyWeaponDefinition(weaponFixture());
  assert.deepEqual(validation.validateWeaponDefinition(valid), []);
  const invalid = { ...valid, assetId: 'weapon.fixture', directionalAttacks: { right: valid.directionalAttacks.right } };
  const issues = validation.validateWeaponDefinition(invalid);
  assert.ok(issues.some((issue) => issue.includes('weapon.assetId: is forbidden')));
  assert.ok(issues.some((issue) => issue.includes('directionalAttacks.down: is required')));
});
