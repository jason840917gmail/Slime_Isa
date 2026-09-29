import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { ConversionRunner } from '../../lib/scene-conversion/ConversionRunner.mjs';
import { uiSceneAdapter } from '../../lib/scene-conversion/ui.mjs';
import { validateSceneWriteSet } from '../../lib/scene-conversion/validate-scene-write-set.mjs';
import { withoutSceneAudio } from '../helpers/scene-audio.mjs';

const repositoryRoot = fileURLToPath(new URL('../../..', import.meta.url));
const authoredRoot = path.join(repositoryRoot, 'src/game/content/scenes/authored');

async function discoverDocumentPaths(directory, suffix) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = (await Promise.all(entries.map(async (entry) => {
    const candidate = path.join(directory, entry.name);
    return entry.isDirectory() ? discoverDocumentPaths(candidate, suffix) : entry.isFile() && entry.name.endsWith(suffix) ? [candidate] : [];
  }))).flat().sort();
  return files;
}

async function discoverDocuments(directory, suffix) {
  const files = await discoverDocumentPaths(directory, suffix);
  return Promise.all(files.map(async (file) => JSON.parse(await readFile(file, 'utf8'))));
}

async function createRunner() {
  const productionLedger = JSON.parse(await readFile(path.join(repositoryRoot, 'scripts/migrations/universal-scene-conversion-ledger.json'), 'utf8'));
  const uiRows = productionLedger.rows.filter((row) => row.family === 'ui');
  const uiKeys = new Set(uiRows.map((row) => row.key));
  const ledger = { ...productionLedger, rows: productionLedger.rows.map((row) => uiKeys.has(row.key) ? { ...row, writerState: 'legacy' } : row) };
  const manifest = JSON.parse(await readFile(path.join(repositoryRoot, 'asset/assets.json'), 'utf8'));
  const [existingScenes, existingResources] = await Promise.all([
    discoverDocuments(authoredRoot, '.scene.json'),
    discoverDocuments(authoredRoot, '.resource.json'),
  ]);
  return {
    unitKeys: [...uiKeys].sort(),
    runner: new ConversionRunner({
      repositoryRoot,
      ledger,
      adapters: { ui: uiSceneAdapter },
      outputRoot: await mkdtemp(path.join(os.tmpdir(), 'ui-scene-conversion-')),
      validateWriteSet: (outputs) => validateSceneWriteSet(outputs, {
        hasAsset: (assetId) => Object.hasOwn(manifest.assets, assetId), existingScenes, existingResources,
      }),
    }),
  };
}

test('UI conversion covers every ledger row and is deterministic in either input order', async () => {
  const { runner, unitKeys } = await createRunner();
  const first = await runner.run({ unitKeys, mode: 'dry-run' });
  const replay = await runner.run({ unitKeys: [...unitKeys].reverse(), mode: 'dry-run' });
  assert.deepEqual(replay.outputs, first.outputs);
  assert.equal(first.outputs.length, 15);
  assert.deepEqual(first.outputs.map((output) => output.unitKey), unitKeys);
  assert.ok(first.outputs.every((output) => output.path.startsWith('ui/') && output.path.endsWith('.scene.json')));
});

test('UI scenes preserve layout, theme, typed bindings, actions, and common controls', async () => {
  const { runner, unitKeys } = await createRunner();
  await runner.run({ unitKeys, mode: 'apply' });
  await runner.run({ unitKeys, mode: 'check' });
  const load = async (name) => JSON.parse(await readFile(path.join(runner.outputRoot, `ui/${name}.scene.json`), 'utf8'));
  const hud = await load('hud');
  const inventory = await load('inventory-ui');
  const chest = await load('chest-inventory-panel');

  assert.equal(hud.sceneId, 'ui.hud');
  assert.deepEqual(hud.nodes.find((node) => node.id === 'surface').properties.theme, { resourceId: 'ui.field-kit.theme' });
  assert.deepEqual(hud.nodes.filter((node) => node.type === 'ProgressBar').map((node) => node.name), ['Health', 'Experience', 'Energy']);
  assert.equal(hud.nodes.find((node) => node.scriptId === 'game.ui-surface').properties.bindings.length, 8);

  assert.equal(inventory.nodes[0].type, 'ModalRoot');
  assert.ok(inventory.nodes.some((node) => node.type === 'ItemList'));
  assert.ok(inventory.nodes.some((node) => node.type === 'Button'));
  const inventoryActions = inventory.nodes.find((node) => node.scriptId === 'game.ui-surface').properties.actions;
  assert.equal(inventoryActions.on_item_selected, 'select-item');
  assert.equal(inventoryActions.on_primary_action, 'use-or-equip');
  assert.equal(inventoryActions.on_assign_slot, 'assign-slot');
  assert.equal(inventoryActions.on_drop_all, 'drop-all');
  assert.equal(inventoryActions.on_remove_all, 'remove-all');
  assert.equal(inventoryActions.on_close_action, 'close');
  assert.equal(inventory.nodes.find((node) => node.name === 'Items').parentId, 'content');
  assert.equal(inventory.nodes.find((node) => node.id === 'content').parentId, 'scroll');
  assert.ok(inventory.connections.some((connection) => connection.handler === 'on_item_selected'));
  assert.ok(chest.connections.some((connection) => connection.signal === 'item_secondary' && connection.handler === 'on_item_secondary'));
  assert.equal(chest.nodes.find((node) => node.name === 'Items').parentId, 'content');

  for (const key of unitKeys) {
    const name = key.slice('ui:'.length);
    assert.deepEqual(
      withoutSceneAudio(JSON.parse(await readFile(path.join(authoredRoot, `ui/${name}.scene.json`), 'utf8'))),
      await load(name),
    );
  }
});

test('UI extraction descriptors pin every source hash and destination identity', async () => {
  const ledger = JSON.parse(await readFile(path.join(repositoryRoot, 'scripts/migrations/universal-scene-conversion-ledger.json'), 'utf8'));
  const extraction = JSON.parse(await readFile(path.join(repositoryRoot, 'scripts/migrations/ui-extraction-descriptors.json'), 'utf8'));
  const descriptors = new Map(extraction.surfaces.map((surface) => [surface.id, surface]));
  const rows = ledger.rows.filter((row) => row.family === 'ui');
  assert.equal(descriptors.size, rows.length);
  for (const row of rows) {
    const descriptor = descriptors.get(row.stableId);
    assert.ok(descriptor, row.key);
    assert.equal(descriptor.sourcePath, row.oldSourcePath);
    assert.equal(descriptor.sourceHash, row.sourceHash);
    assert.equal(`scene://ui/${descriptor.id}`, row.destinationId);
    assert.ok(Object.keys(descriptor.layoutValues).length > 0);
    assert.ok(Object.keys(descriptor.themeValues).length > 0);
    assert.ok(Array.isArray(descriptor.bindings));
  }
});
