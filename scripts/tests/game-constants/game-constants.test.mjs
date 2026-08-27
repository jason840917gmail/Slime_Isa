import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../..', import.meta.url));

async function load(entryPoint) {
  const result = await build({ absWorkingDir: root, entryPoints: [entryPoint], bundle: true, format: 'esm', platform: 'node', write: false });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

test('checked-in gameplay configuration is valid and deeply frozen', async () => {
  const { GAME_CONSTANTS } = await load('src/game/Constant.ts');
  assert.deepEqual(GAME_CONSTANTS.resources.tags, ['wood', 'stone', 'iron', 'charcoal', 'grain']);
  assert.equal(GAME_CONSTANTS.inventory.initialMaxSlots, 24);
  assert.equal(GAME_CONSTANTS.character.player.progression.maxLevel, 10);
  assert.equal(GAME_CONSTANTS.character.player.progression.levels[8].xpToNextLevel, 2160);
  assert.equal(GAME_CONSTANTS.character.player.progression.levels[9].xpToNextLevel, null);
  assert.equal(Object.isFrozen(GAME_CONSTANTS), true);
  assert.equal(Object.isFrozen(GAME_CONSTANTS.resources.tags), true);
  assert.equal(Object.isFrozen(GAME_CONSTANTS.character.player.progression.levels), true);
  assert.throws(() => { GAME_CONSTANTS.inventory.initialMaxSlots = 1; }, TypeError);
});

test('resource tags expose constants-owned membership checks', async () => {
  const { RESOURCE_TAGS, isResourceTag, resourceTagIssue } = await load('src/game/content/ResourceTags.ts');
  assert.deepEqual(RESOURCE_TAGS, ['wood', 'stone', 'iron', 'charcoal', 'grain']);
  assert.equal(isResourceTag('iron'), true);
  assert.equal(isResourceTag('crystal'), false);
  assert.equal(resourceTagIssue('wood'), undefined);
  assert.match(resourceTagIssue('crystal'), /Unknown resource tag 'crystal'/);
});

test('validator reports movement order and level-table violations', async () => {
  const { validateGameConstants } = await load('src/game/content/GameConstantsValidation.ts');
  const invalid = {
    version: 1,
    resources: { tags: ['wood', 'wood', 'Bad Tag'] },
    inventory: { initialMaxSlots: 24, maxStackByItem: { wood: 99 }, weaponMaxStack: 1 },
    character: { player: {
      initialAttributes: { strength: 10, vitality: 10, agility: 10, intellect: 10 },
      movement: { baseSpeed: 500, boostSpeed: 300, dodgeSpeed: 600, dodgeInvulnerabilityMs: 400, movementSpeedCap: 480 },
      hitInvulnerabilityMs: 500,
      progression: {
        maxLevel: 2, baseMaxHp: 100, baseMaxEnergy: 100, baseAttack: 10, baseDefense: 2,
        levels: [
          { level: 1, xpToNextLevel: 80, gains: { maxHp: 1, maxEnergy: 0, attack: 0, defense: 0 } },
          { level: 3, xpToNextLevel: 100, gains: { maxHp: 12, maxEnergy: 4, attack: 2, defense: 1 } },
        ],
      },
    } },
  };
  const issues = validateGameConstants(invalid);
  assert.ok(issues.some((entry) => entry.message.includes('baseSpeed')));
  assert.ok(issues.some((entry) => entry.message.includes('level 1 gain')));
  assert.ok(issues.some((entry) => entry.message.includes('must be 2')));
  assert.ok(issues.some((entry) => entry.message.includes('final level must use null')));
  assert.ok(issues.some((entry) => entry.message.includes("duplicate tag 'wood'")));
  assert.ok(issues.some((entry) => entry.message.includes('lowercase kebab-case tag')));
});
