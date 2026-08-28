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

function expectedStats(level) {
  return progression.levels.slice(1, level).reduce((stats, entry) => ({
    maxHp: stats.maxHp + entry.gains.maxHp,
    maxEnergy: stats.maxEnergy + entry.gains.maxEnergy,
    attack: stats.attack + entry.gains.attack,
    defense: stats.defense + entry.gains.defense,
  }), {
    maxHp: progression.baseMaxHp,
    maxEnergy: progression.baseMaxEnergy,
    attack: progression.baseAttack,
    defense: progression.baseDefense,
  });
}

test('every authored level requirement and gain resolves exactly', () => {
  progression.levels.forEach((authored, index) => {
    const entry = levelEntry(progression, index + 1);
    assert.deepEqual(entry, authored);
  });
  assert.deepEqual(resolveLevelStats(progression, progression.maxLevel), expectedStats(progression.maxLevel));
});

test('one XP grant crosses multiple levels and carries its remainder', () => {
  const levelOneXp = progression.levels[0].xpToNextLevel;
  const levelTwoXp = progression.levels[1].xpToNextLevel;
  assert.notEqual(levelOneXp, null);
  assert.notEqual(levelTwoXp, null);
  const result = applyExperience(progression, 1, 20, levelOneXp + levelTwoXp + 10);
  assert.equal(result.level, 3);
  assert.equal(result.currentXp, 30);
  assert.deepEqual(result.levelsGained.map((entry) => entry.level), [2, 3]);
});

test('maximum level discards XP and cannot reward another level', () => {
  const maximumLevel = progression.maxLevel;
  const previousLevel = maximumLevel - 1;
  const finalRequirement = progression.levels[previousLevel - 1].xpToNextLevel;
  assert.notEqual(finalRequirement, null);
  const reached = applyExperience(progression, previousLevel, finalRequirement - 1, 1);
  assert.equal(reached.level, maximumLevel);
  assert.equal(reached.currentXp, 0);
  assert.deepEqual(reached.levelsGained.map((entry) => entry.level), [maximumLevel]);
  assert.deepEqual(applyExperience(progression, maximumLevel, 0, 1_000_000), {
    level: maximumLevel, currentXp: 0, levelsGained: [],
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
  assert.deepEqual(migratePlayerProgression(progression, 3, 999_999), {
    level: 3,
    currentXp: progression.levels[2].xpToNextLevel - 1,
  });
  assert.deepEqual(migratePlayerProgression(progression, progression.maxLevel, 999_999), {
    level: progression.maxLevel,
    currentXp: 0,
  });
  assert.throws(() => migratePlayerProgression(progression, progression.maxLevel + 1, 0), RangeError);
});

test('changing a supplied gain table recalculates derived stats without changing progression state', () => {
  const changed = structuredClone(progression);
  changed.levels[2].gains.maxHp = 100;
  const changedStats = resolveLevelStats(changed, 3);
  assert.equal(changedStats.maxHp, expectedStats(3).maxHp - progression.levels[2].gains.maxHp + 100);
  assert.equal(changedStats.maxEnergy, expectedStats(3).maxEnergy);
  assert.equal(changedStats.attack, expectedStats(3).attack);
  assert.equal(changedStats.defense, expectedStats(3).defense);
  assert.deepEqual(applyExperience(changed, 3, 17, 0), {
    level: 3, currentXp: 17, levelsGained: [],
  });
});
