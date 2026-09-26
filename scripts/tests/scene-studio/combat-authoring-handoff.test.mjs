import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { characterContentModulesPlugin } = await loadTypescriptModule('src/game/content/characters/characterContentModulesPlugin.ts');

test('converted combat entities declare Scene Studio as their writer', async () => {
  const ledger = JSON.parse(await readFile('scripts/migrations/universal-scene-conversion-ledger.json', 'utf8'));
  const entities = ledger.rows.filter((row) => ['weapon', 'projectile', 'effect'].includes(row.family) && row.classification === 'convert');
  assert.equal(entities.length, 16);
  assert.deepEqual([...new Set(entities.map((row) => row.writerState))], ['scene']);
});

test('the combat content loader does not register legacy write routes', () => {
  assert.equal(characterContentModulesPlugin().configureServer, undefined);
});
