import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { characterContentModulesPlugin } = await loadTypescriptModule('src/game/content/characters/characterContentModulesPlugin.ts');

test('all converted characters declare Scene Studio as their writer', async () => {
  const ledger = JSON.parse(await readFile('scripts/migrations/universal-scene-conversion-ledger.json', 'utf8'));
  const characters = ledger.rows.filter((row) => row.family === 'character' && row.classification === 'convert');
  assert.ok(characters.length > 0);
  assert.deepEqual([...new Set(characters.map((row) => row.writerState))], ['scene']);
});

test('the character content loader does not register legacy write routes', () => {
  assert.equal(characterContentModulesPlugin().configureServer, undefined);
});
