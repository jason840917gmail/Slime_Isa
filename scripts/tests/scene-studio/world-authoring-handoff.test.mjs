import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const config = await readFile(new URL('../../../src/game/config.ts', import.meta.url), 'utf8');
const vite = await readFile(new URL('../../../vite.config.ts', import.meta.url), 'utf8');
const studio = await readFile(new URL('../../../src/game/editor/scene-studio/SceneStudio.ts', import.meta.url), 'utf8');
const ledger = JSON.parse(await readFile(new URL('../../../scripts/migrations/universal-scene-conversion-ledger.json', import.meta.url), 'utf8'));

test('production development routing hands legacy map URLs to authored world scenes', () => {
  assert.match(config, /redirectLegacyStudioRoute\(window\.location\.search\)/);
  assert.match(config, /window\.history\.replaceState\(null, '', legacyStudioRoute\)/);
  assert.match(studio, /loadTileContexts\(record\.document\)/);
});

test('legacy Map Studio write endpoints are retired while Scene Studio owns atomic resources', () => {
  assert.doesNotMatch(vite.slice(vite.indexOf('export default defineConfig')), /mapEditorSavePlugin\(/);
  assert.match(vite, /animationContentModulesPlugin\(\)/);
  assert.match(studio, /this\.repository\.save\(writes\)/);
  assert.match(studio, /kind: 'resource' as const/);
  assert.ok(ledger.rows.filter((row) => row.family === 'map').every((row) => row.writerState === 'scene'));
});
