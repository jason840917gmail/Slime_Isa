import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import {
  discoverInventory,
  LEDGER_PATH,
  REPOSITORY_ROOT,
} from '../../inventory-scene-conversion.mjs';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const checkedIn = JSON.parse(await readFile(new URL(`../../../${LEDGER_PATH}`, import.meta.url), 'utf8'));
const discovered = discoverInventory(REPOSITORY_ROOT);

test('every discovered legacy content unit appears exactly once in the conversion ledger', () => {
  assert.deepEqual(checkedIn.rows.map((entry) => entry.key), discovered.rows.map((entry) => entry.key));
  assert.equal(new Set(checkedIn.rows.map((entry) => entry.key)).size, checkedIn.rows.length);
});

test('the ledger preserves every authored map and stable persistence key', () => {
  const checkedMaps = checkedIn.rows.filter((entry) => entry.family === 'map');
  const discoveredMaps = discovered.rows.filter((entry) => entry.family === 'map');
  const withoutWriter = (entry) => Object.fromEntries(Object.entries(entry).filter(([key]) => key !== 'writerState'));
  assert.deepEqual(checkedMaps.map(withoutWriter), discoveredMaps.map(withoutWriter));
  assert.ok(checkedMaps.every((entry) => entry.writerState === 'scene'));
  assert.ok(checkedMaps.some((entry) => entry.environment === 'production'));
  assert.ok(checkedMaps.some((entry) => entry.environment === 'development'));
  assert.ok(checkedMaps.reduce((total, entry) => total + entry.persistenceKeys.length, 0) > 0);
});

test('legacy writer endpoints and category routes stay inventoried', () => {
  assert.deepEqual(checkedIn.writerEndpoints, discovered.writerEndpoints);
  assert.deepEqual(checkedIn.editorRoutes, discovered.editorRoutes);
  assert.ok(checkedIn.writerEndpoints.some((entry) => entry.endpoint === '/__map-editor/save'));
  assert.deepEqual(checkedIn.editorRoutes.map((entry) => entry.queryKey), ['editor', 'studio']);
});

test('every row names its ownership and verification path', () => {
  for (const entry of checkedIn.rows) {
    assert.ok(entry.oldSourcePath.length > 0, entry.key);
    assert.ok(entry.oldCatalogValidator.length > 0, entry.key);
    assert.ok(entry.oldFactoryController.length > 0, entry.key);
    assert.ok(entry.destinationId.length > 0, entry.key);
    assert.ok(entry.focusedVerification.length > 0, entry.key);
    if (entry.classification === 'convert') {
      assert.equal(Number.isInteger(entry.migrationWorkPackage), true, entry.key);
      assert.equal(entry.legacyRemovalWorkPackage, 15, entry.key);
    }
  }
});

test('shared TypeScript loader imports one pure graph and rejects guarded engine dependencies', async () => {
  const damage = await loadTypescriptModule('src/game/combat/DamageableTarget.ts');
  assert.deepEqual(damage.acceptedDamage(4, 1), {
    status: 'accepted',
    actualDamage: 3,
    defeated: false,
  });
  await assert.rejects(
    () => loadTypescriptModule('src/game/scenes/BootScene.ts'),
    /guarded dependency 'phaser'/,
  );
});
