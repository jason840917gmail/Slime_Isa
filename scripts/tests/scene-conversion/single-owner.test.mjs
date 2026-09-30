import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { auditSceneOwnership, REPOSITORY_ROOT } from '../../check-scene-ownership.mjs';

test('Scene Studio is the only mounted editor and scene-owned UI has an authored composition', () => {
  assert.deepEqual(auditSceneOwnership(), []);
  const config = readFileSync(path.join(REPOSITORY_ROOT, 'src/game/config.ts'), 'utf8');
  assert.match(config, /mountSceneStudio\(container\)/);
  assert.doesNotMatch(config, /mount(?:Character|Animation|Weapon|Projectile)Studio|MapEditor(?:Load)?Scene/);
  const ledger = JSON.parse(readFileSync(path.join(REPOSITORY_ROOT, 'scripts/migrations/universal-scene-conversion-ledger.json'), 'utf8'));
  assert.equal(ledger.rows.filter((row) => row.family === 'ui' && row.writerState === 'scene').length, 14);
});
