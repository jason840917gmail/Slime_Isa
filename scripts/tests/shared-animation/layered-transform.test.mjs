import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let transformModule;

async function loadTypeScriptModule(entryPoint) {
  const result = await build({ absWorkingDir: repositoryRoot, entryPoints: [entryPoint], bundle: true, format: 'esm', platform: 'node', write: false });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

before(async () => {
  transformModule = await loadTypeScriptModule('src/game/shared/animation/layeredTransform.ts');
});

function layerFixture(overrides = {}) {
  return {
    layerId: 'trail', displayName: 'Trail', assetId: 'effect.trail', sourceFrame: 2,
    layerIndex: 1, blockIndex: 0, relativeDepth: 0.25,
    layerTransform: { offset: [10, 4], scale: [2, 3], rotationDeg: 15, flipX: false, flipY: true, origin: [0.2, 0.8] },
    blockTransform: { offset: [2, -1], scale: [0.5, 2], rotationDeg: 5, flipX: true, flipY: true },
    ...overrides,
  };
}

test('layer and block transforms compose before host rotation', () => {
  const output = transformModule.composeAnimationVisualTransform(layerFixture(), {
    x: 100, y: 200, baseDepth: 4, rotationRad: Math.PI / 2, mirrorX: false, mirrorY: false,
  });
  assert.ok(Math.abs(output.x - 97) < 1e-9);
  assert.ok(Math.abs(output.y - 212) < 1e-9);
  assert.equal(output.depth, 4.25);
  assert.deepEqual([output.originX, output.originY], [0.2, 0.8]);
  assert.deepEqual([output.scaleX, output.scaleY], [1, 6]);
  assert.equal(output.flipX, true);
  assert.equal(output.flipY, false);
  assert.ok(Math.abs(output.rotationRad - (Math.PI / 2 + 20 * Math.PI / 180)) < 1e-9);
});

test('host mirroring reflects X, negates local rotation, and participates in XOR flipping', () => {
  const output = transformModule.composeAnimationVisualTransform(layerFixture(), {
    x: 100, y: 200, baseDepth: 4, rotationRad: 0, mirrorX: true, mirrorY: false,
  });
  assert.deepEqual([output.x, output.y], [88, 203]);
  assert.equal(output.flipX, false);
  assert.equal(output.flipY, false);
  assert.ok(Math.abs(output.rotationRad - (-20 * Math.PI / 180)) < 1e-9);
});

test('double authored X flips cancel without changing positive scale', () => {
  const layer = layerFixture({
    layerTransform: { ...layerFixture().layerTransform, flipX: true },
    blockTransform: { ...layerFixture().blockTransform, flipX: true },
  });
  const output = transformModule.composeAnimationVisualTransform(layer, {
    x: 0, y: 0, baseDepth: 0, rotationRad: 0, mirrorX: false, mirrorY: false,
  });
  assert.equal(output.flipX, false);
  assert.deepEqual([output.scaleX, output.scaleY], [1, 6]);
});

test('vertical mirroring reflects Y, negates local rotation, and participates in flipY XOR', () => {
  const output = transformModule.composeAnimationVisualTransform(layerFixture(), {
    x: 100, y: 200, baseDepth: 4, rotationRad: 0, mirrorX: false, mirrorY: true,
  });
  assert.deepEqual([output.x, output.y], [112, 197]);
  assert.equal(output.flipX, true);
  assert.equal(output.flipY, true);
  assert.ok(Math.abs(output.rotationRad - (-20 * Math.PI / 180)) < 1e-9);
});
