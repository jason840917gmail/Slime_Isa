import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const tooling = await loadTypescriptModule('src/game/content/scenes/sceneContentModulesPlugin.ts');

test('virtual scene discovery is recursive, deterministic, and read-only', async (context) => {
  const contentRoot = await mkdtemp(path.join(os.tmpdir(), 'scene-content-discovery-'));
  context.after(() => rm(contentRoot, { recursive: true, force: true }));
  await mkdir(path.join(contentRoot, 'nested'));
  await writeFile(path.join(contentRoot, 'z.scene.json'), '{}\n');
  await writeFile(path.join(contentRoot, 'nested', 'a.scene.json'), '{}\n');
  await writeFile(path.join(contentRoot, 'nested', 'theme.resource.json'), '{}\n');
  const plugin = tooling.sceneContentModulesPlugin(contentRoot);
  assert.equal(plugin.configureServer, undefined);
  assert.equal(plugin.resolveId('virtual-scene-content'), '\0virtual-scene-content');
  const source = await plugin.load('\0virtual-scene-content');
  assert.ok(source.indexOf('a.scene.json') < source.indexOf('z.scene.json'));
  assert.match(source, /theme\.resource\.json/);
  assert.match(source, /export const sceneDocuments/);
  assert.match(source, /export const sceneResourceDocuments/);
});
