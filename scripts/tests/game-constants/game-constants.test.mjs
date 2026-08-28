import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../..', import.meta.url));

async function load(entryPoint) {
  const result = await build({ absWorkingDir: root, entryPoints: [entryPoint], bundle: true, format: 'esm', platform: 'node', write: false });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

function readAuthoredConstants() {
  return JSON.parse(readFileSync(path.join(root, 'src/game/content/game-constants.json'), 'utf8'));
}

test('checked-in gameplay configuration is valid and deeply frozen', async () => {
  const { GAME_CONSTANTS } = await load('src/game/Constant.ts');
  const authored = readAuthoredConstants();
  assert.deepEqual(GAME_CONSTANTS, authored);
  assert.equal(Number.isInteger(GAME_CONSTANTS.worldNavigation.edgeTransitionGraceMs), true);
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
    worldNavigation: { edgeTransitionGraceMs: 650 },
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

test('JSON Schema owns structural properties without a TypeScript whitelist', async () => {
  const { validateGameConstants } = await load('src/game/content/GameConstantsValidation.ts');
  const authored = readAuthoredConstants();
  assert.deepEqual(validateGameConstants(authored), []);
  authored.unexpectedProperty = true;
  const issues = validateGameConstants(authored);
  assert.ok(issues.some((entry) => entry.path === 'gameConstants.unexpectedProperty' && entry.message === 'unknown property'));
});

test('schema regression matrix rejects representative malformed structures with stable paths', async () => {
  const { validateGameConstants } = await load('src/game/content/GameConstantsValidation.ts');
  const cases = [
    {
      name: 'wrong scalar type',
      mutate(document) { document.worldNavigation.edgeTransitionGraceMs = '650'; },
      path: 'worldNavigation.edgeTransitionGraceMs',
      message: 'integer',
    },
    {
      name: 'empty dynamic map',
      mutate(document) { document.inventory.maxStackByItem = {}; },
      path: 'inventory.maxStackByItem',
      message: 'properties',
    },
    {
      name: 'invalid dynamic-map key',
      mutate(document) { document.inventory.maxStackByItem['Bad Item'] = 1; },
      path: 'inventory.maxStackByItem["Bad Item"]',
      message: 'item ID',
    },
    {
      name: 'nested unknown property',
      mutate(document) { document.character.player.movement.unexpected = 1; },
      path: 'character.player.movement.unexpected',
      message: 'unknown property',
    },
    {
      name: 'missing schema declaration',
      mutate(document) { delete document.$schema; },
      path: 'gameConstants.$schema',
      message: 'required',
    },
  ];

  for (const scenario of cases) {
    const document = readAuthoredConstants();
    scenario.mutate(document);
    const issues = validateGameConstants(document);
    assert.ok(
      issues.some((entry) => entry.path === scenario.path && entry.message.includes(scenario.message)),
      `${scenario.name}: ${JSON.stringify(issues)}`,
    );
  }
});
