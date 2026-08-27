import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../..', import.meta.url));

async function load(entryPoint) {
  const result = await build({ absWorkingDir: root, entryPoints: [entryPoint], bundle: true, format: 'esm', platform: 'node', write: false });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

const { GAME_CONSTANTS } = await load('src/game/Constant.ts');
const { applyExperience, levelEntry, resolveLevelStats } = await load('src/game/systems/PlayerProgression.ts');
const { legacyCumulativeXpForLevel, migratePlayerProgression } = await load('src/game/infrastructure/persistence/PlayerProgressionMigration.ts');
const progression = GAME_CONSTANTS.character.player.progression;

test('every normative level requirement and gain resolves exactly', () => {
  const requirements = [80, 226, 416, 640, 894, 1176, 1482, 1810, 2160, null];
  requirements.forEach((requirement, index) => {
    const entry = levelEntry(progression, index + 1);
    assert.equal(entry.xpToNextLevel, requirement);
    assert.deepEqual(entry.gains, index === 0
      ? { maxHp: 0, maxEnergy: 0, attack: 0, defense: 0 }
      : { maxHp: 12, maxEnergy: 4, attack: 2, defense: 1 });
  });
  assert.deepEqual(resolveLevelStats(progression, 10), {
    maxHp: 208, maxEnergy: 136, attack: 28, defense: 11,
  });
});

test('one XP grant crosses multiple levels and carries its remainder', () => {
  const result = applyExperience(progression, 1, 20, 80 + 226 + 10);
  assert.equal(result.level, 3);
  assert.equal(result.currentXp, 30);
  assert.deepEqual(result.levelsGained.map((entry) => entry.level), [2, 3]);
});

test('maximum level discards XP and cannot reward another level', () => {
  const reached = applyExperience(progression, 9, 2159, 1);
  assert.equal(reached.level, 10);
  assert.equal(reached.currentXp, 0);
  assert.deepEqual(reached.levelsGained.map((entry) => entry.level), [10]);
  assert.deepEqual(applyExperience(progression, 10, 0, 1_000_000), {
    level: 10, currentXp: 0, levelsGained: [],
  });
});

test('invalid levels and XP are rejected', () => {
  assert.throws(() => levelEntry(progression, 0), RangeError);
  assert.throws(() => applyExperience(progression, 1, -1, 0), RangeError);
  assert.throws(() => applyExperience(progression, 1, 0, Number.NaN), RangeError);
});

test('legacy migration keeps saved level and clamps inconsistent cumulative XP', () => {
  assert.equal(legacyCumulativeXpForLevel(3), 306);
  assert.deepEqual(migratePlayerProgression(progression, 3, 323), { level: 3, currentXp: 17 });
  assert.deepEqual(migratePlayerProgression(progression, 3, 1), { level: 3, currentXp: 0 });
  assert.deepEqual(migratePlayerProgression(progression, 3, 999_999), { level: 3, currentXp: 415 });
  assert.deepEqual(migratePlayerProgression(progression, 10, 999_999), { level: 10, currentXp: 0 });
  assert.throws(() => migratePlayerProgression(progression, 11, 0), RangeError);
});

test('changing a supplied gain table recalculates derived stats without changing progression state', () => {
  const changed = structuredClone(progression);
  changed.levels[2].gains.maxHp = 100;
  assert.deepEqual(resolveLevelStats(changed, 3), {
    maxHp: 212, maxEnergy: 108, attack: 14, defense: 4,
  });
  assert.deepEqual(applyExperience(changed, 3, 17, 0), {
    level: 3, currentXp: 17, levelsGained: [],
  });
});