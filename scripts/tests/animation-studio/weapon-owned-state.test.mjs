import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let moduleUnderTest;

async function loadTypeScriptModule(entryPoint) {
  const result = await build({ absWorkingDir: repositoryRoot, entryPoints: [entryPoint], bundle: true, format: 'esm', platform: 'node', write: false });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

before(async () => { moduleUnderTest = await loadTypeScriptModule('src/game/editor/WeaponOwnedAnimationDocumentState.ts'); });

function weapon() {
  const animation = { version: 2, durationSeconds: 0.5, framesPerSecond: 8, loop: false, loopMode: 'wrap', layers: [{ layerId: 'base', displayName: 'Base', assetId: 'sheet.weapon', depthOffset: 0, blocks: [{ from: 0, through: 1, sourceFrame: 0 }] }] };
  const attack = { animation: structuredClone(animation), characterActionId: 'attack', hitboxes: {}, attackTrack: { hitboxSpans: [{ hitboxId: 'blade', from: 0, through: 1 }] } };
  return { version: 2, weaponId: 'tool.test', displayName: 'Test Tool', category: 'melee', baseDamage: 1, cooldownMs: 100, hitboxWidth: 1, hitboxHeight: 1, hitboxOffset: 0, hitboxDurationMs: 1, knockStrength: 1, vfxColor: 0xffffff, unlockLevel: 1, iconKey: 'tool.test', iconFrame: 0, description: 'test', characterActionId: 'attack', animations: { idle: structuredClone(animation) }, directionalAttacks: { right: attack, down: structuredClone(attack) } };
}

test('owned state edits only the selected embedded animation and reconciles its attack track', () => {
  const source = weapon();
  const state = new moduleUnderTest.WeaponOwnedAnimationDocumentState(source, 'r1', { slot: 'attack', direction: 'right' });
  assert.equal(state.setDurationSeconds(1), true);
  assert.equal(state.value.weapon.directionalAttacks.right.animation.durationSeconds, 1);
  assert.equal(state.value.weapon.directionalAttacks.down.animation.durationSeconds, 0.5);
  assert.deepEqual(state.value.weapon.directionalAttacks.right.attackTrack.hitboxSpans, [{ hitboxId: 'blade', from: 0, through: 1 }]);
  assert.equal(state.undo(), true);
  assert.equal(state.value.weapon.directionalAttacks.right.animation.durationSeconds, 0.5);
  assert.equal(state.value.weapon.directionalAttacks.down.animation.durationSeconds, 0.5);
});

test('shared or inherited slots cannot be constructed as owned documents', () => {
  const shared = weapon();
  shared.animations.idleAnimationId = 'shared.idle';
  assert.throws(() => new moduleUnderTest.WeaponOwnedAnimationDocumentState(shared, 'r1', { slot: 'idle' }), /shared reference/);
  assert.throws(() => new moduleUnderTest.WeaponOwnedAnimationDocumentState(weapon(), 'r1', { slot: 'attack', direction: 'left' }), /inherited/);
});
