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
  assert.match(renderer, /camp\.activation\)/);
  assert.match(renderer, /camp\.arena\)/);
  // Authored worlds carry boss camps as encounter scenes, not map.bossCamps.
  assert.match(worldScene, /getBossBattleAreas: \(\) => this\.universalWorld\?\.bossBattleAreas \?\? \[\]/);
});
