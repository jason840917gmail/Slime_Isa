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
  assert.equal(typeof plugin.configureServer, 'function');
  assert.equal(plugin.resolveId('virtual-scene-content'), '\0virtual-scene-content');
  const source = await plugin.load('\0virtual-scene-content');
  assert.ok(source.indexOf('a.scene.json') < source.indexOf('z.scene.json'));
  assert.match(source, /theme\.resource\.json/);
  assert.match(source, /export const sceneDocuments/);
  assert.match(source, /export const sceneResourceDocuments/);
});

test('production builds leave dev-only worlds out; the dev server keeps them', async (context) => {
  const contentRoot = await mkdtemp(path.join(os.tmpdir(), 'scene-content-dev-worlds-'));
  context.after(() => rm(contentRoot, { recursive: true, force: true }));
  await mkdir(path.join(contentRoot, 'worlds'));
  await writeFile(path.join(contentRoot, 'worlds', 'level-1.scene.json'), '{}\n');
  await writeFile(path.join(contentRoot, 'worlds', 'playground.scene.json'), '{}\n');
  const load = async (command) => {
    const plugin = tooling.sceneContentModulesPlugin(contentRoot);
    plugin.configResolved({ command });
    return plugin.load('\0virtual-scene-content');
  };
  const served = await load('serve');
  assert.match(served, /playground\.scene\.json/);
  const built = await load('build');
  assert.doesNotMatch(built, /playground\.scene\.json/);
  assert.match(built, /level-1\.scene\.json/);
});


test('a production build ships exactly the reachable worlds (roadmap 10.2)', async () => {
  const plugin = tooling.sceneContentModulesPlugin(path.resolve('src/game/content/scenes/authored'));
  plugin.configResolved({ command: 'build' });
  const built = await plugin.load('\0virtual-scene-content');
  // Paths are JSON-escaped in the generated module (Windows separators arrive as "\\").
  const worlds = [...built.matchAll(/[\\/]+worlds[\\/]+([^\\/"]+)\.scene\.json/g)].map((match) => match[1]).sort();
  assert.deepEqual(worlds, ['crystal-caverns', 'gloop-cavern', 'gloop-forest', 'gloop-hut', 'level-1', 'mushroom-home', 'slime-home']);
});
