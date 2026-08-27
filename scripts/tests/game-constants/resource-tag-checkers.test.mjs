import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const checkedInConstantsPath = path.join(repositoryRoot, 'src', 'game', 'content', 'game-constants.json');

function runChecker(scriptName, environment) {
  return spawnSync(process.execPath, [path.join(repositoryRoot, 'scripts', scriptName)], {
    cwd: repositoryRoot,
    encoding: 'utf8',
    env: { ...process.env, ...environment },
  });
}

test('weapon and object repository checkers reject unknown resource tags with configured alternatives', async () => {
  const fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'slime-resource-checkers-'));
  const constantsPath = path.join(fixtureRoot, 'game-constants.json');
  const weaponRoot = path.join(fixtureRoot, 'weapons');
  const objectRoot = path.join(fixtureRoot, 'objects');

  try {
    await fs.copyFile(checkedInConstantsPath, constantsPath);
    await fs.cp(path.join(repositoryRoot, 'src', 'game', 'content', 'weapons'), weaponRoot, { recursive: true });
    await fs.cp(path.join(repositoryRoot, 'src', 'game', 'content', 'objects'), objectRoot, { recursive: true });

    const weaponPath = path.join(weaponRoot, 'stone-axe', 'weapon.json');
    const weapon = JSON.parse(await fs.readFile(weaponPath, 'utf8'));
    weapon.harvestCapabilities = { crystal: 1 };
    await fs.writeFile(weaponPath, `${JSON.stringify(weapon, null, 2)}\n`);

    const weaponResult = runChecker('check-weapons.mjs', {
      SLIME_CHECK_GAME_CONSTANTS_PATH: constantsPath,
      SLIME_CHECK_WEAPON_ROOT: weaponRoot,
    });
    assert.equal(weaponResult.status, 1, weaponResult.stdout || weaponResult.stderr);
    const weaponOutput = `${weaponResult.stdout}${weaponResult.stderr}`;
    assert.match(weaponOutput, /\[stone-axe\].*crystal/);
    assert.match(weaponOutput, /configured tags: wood, stone, iron, charcoal, grain/);

    const objectPath = path.join(objectRoot, 'trees', 'tree-world-solid.json');
    const object = JSON.parse(await fs.readFile(objectPath, 'utf8'));
    object.resourceNode.harvestRequirement.targetTag = 'crystal';
    await fs.writeFile(objectPath, `${JSON.stringify(object, null, 2)}\n`);

    const objectResult = runChecker('check-objects.mjs', {
      SLIME_CHECK_GAME_CONSTANTS_PATH: constantsPath,
      SLIME_CHECK_OBJECT_ROOT: objectRoot,
    });
    assert.equal(objectResult.status, 1, objectResult.stdout || objectResult.stderr);
    const objectOutput = `${objectResult.stdout}${objectResult.stderr}`;
    assert.match(objectOutput, /\[.*:tree\.world\.solid\].*crystal/);
    assert.match(objectOutput, /configured tags: wood, stone, iron, charcoal, grain/);
  } finally {
    await fs.rm(fixtureRoot, { recursive: true, force: true });
  }
});

test('repository checkers reject malformed game constants before validating content', async () => {
  const fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'slime-resource-constants-'));
  const constantsPath = path.join(fixtureRoot, 'game-constants.json');

  try {
    const constants = JSON.parse(await fs.readFile(checkedInConstantsPath, 'utf8'));
    constants.resources.tags = ['wood', 'wood'];
    await fs.writeFile(constantsPath, `${JSON.stringify(constants, null, 2)}\n`);
    const result = runChecker('check-weapons.mjs', { SLIME_CHECK_GAME_CONSTANTS_PATH: constantsPath });
    assert.equal(result.status, 1, result.stdout || result.stderr);
    assert.match(`${result.stdout}${result.stderr}`, /duplicate tag 'wood'/);
  } finally {
    await fs.rm(fixtureRoot, { recursive: true, force: true });
  }
});
