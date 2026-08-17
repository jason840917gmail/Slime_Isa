import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');

async function load(entry) {
  const result = await build({
    absWorkingDir: root,
    entryPoints: [entry],
    bundle: true,
    format: 'esm',
    platform: 'node',
    write: false,
  });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

test('position updates preserve the effect transform contract', async () => {
  const { WorldEffectAdapter } = await load('src/game/features/effects/WorldEffectAdapter.ts');
  const adapter = new WorldEffectAdapter(10, 20, 4.5, true, false);

  adapter.setPosition(90, 120);
  assert.deepEqual(adapter.getAnimationHostTransform(), {
    x: 90,
    y: 120,
    baseDepth: 4.5,
    rotationRad: 0,
    mirrorX: true,
    mirrorY: false,
  });
});

test('reset replaces all pooled spawn-time values after a position-only update', async () => {
  const { WorldEffectAdapter } = await load('src/game/features/effects/WorldEffectAdapter.ts');
  const adapter = new WorldEffectAdapter(10, 20, 4.5, true, false);

  adapter.setPosition(90, 120);
  adapter.reset(30, 40, 8.25, false, true);

  assert.deepEqual(adapter.getAnimationHostTransform(), {
    x: 30,
    y: 40,
    baseDepth: 8.25,
    rotationRad: 0,
    mirrorX: false,
    mirrorY: true,
  });
});
