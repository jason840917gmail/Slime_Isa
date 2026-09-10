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

test('lethal resource hits deplete immediately even when an on-hit animation exists', async () => {
  const { resolveResourceHitPresentation } = await load('src/game/combat/ResourceHitPresentation.ts');

  assert.equal(resolveResourceHitPresentation({
    acceptedDamage: 12,
    depleted: true,
    onHitAnimationId: 'object.tree.hit',
  }), 'deplete');
  assert.equal(resolveResourceHitPresentation({
    acceptedDamage: 12,
    depleted: true,
  }), 'deplete');
});

test('only positive non-lethal resource hits play the on-hit animation', async () => {
  const { resolveResourceHitPresentation } = await load('src/game/combat/ResourceHitPresentation.ts');

  assert.equal(resolveResourceHitPresentation({
    acceptedDamage: 12,
    depleted: false,
    onHitAnimationId: 'object.tree.hit',
  }), 'animate-hit');
  assert.equal(resolveResourceHitPresentation({
    acceptedDamage: 0,
    depleted: false,
    onHitAnimationId: 'object.tree.hit',
  }), 'none');
  assert.equal(resolveResourceHitPresentation({
    acceptedDamage: 12,
    depleted: false,
  }), 'none');
});
