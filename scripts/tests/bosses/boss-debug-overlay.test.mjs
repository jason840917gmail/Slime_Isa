import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

test('developer tools expose a separate boss battle area overlay', async () => {
  const devTools = await readFile(new URL('../../../src/game/devTools.ts', import.meta.url), 'utf8');
  const renderer = await readFile(new URL('../../../src/game/dev/WorldDebugRenderer.ts', import.meta.url), 'utf8');
  const worldScene = await readFile(new URL('../../../src/game/scenes/WorldScene.ts', import.meta.url), 'utf8');
  assert.match(devTools, /bossBattleAreas: boolean/);
  assert.match(devTools, /label: 'Boss battle areas'/);
  assert.match(renderer, /devToolsState\.bossBattleAreas/);
  assert.match(renderer, /camp\.activationPerimeter/);
  assert.match(renderer, /camp\.arenaPerimeter/);
  assert.match(worldScene, /getBossCamps: \(\) => this\.builtMap\?\.bossCamps \?\? \[\]/);
});
