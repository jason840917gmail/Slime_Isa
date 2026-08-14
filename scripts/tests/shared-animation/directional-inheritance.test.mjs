import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let animation;

async function loadTypeScriptModule(entryPoint) {
  const result = await build({ absWorkingDir: repositoryRoot, entryPoints: [entryPoint], bundle: true, format: 'esm', platform: 'node', write: false });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

before(async () => {
  animation = await loadTypeScriptModule('src/game/shared/animation/index.ts');
});

const pairs = [
  { child: 'left', master: 'right', axis: 'x', enabled: true },
  { child: 'up', master: 'down', axis: 'y', enabled: true },
];

test('exact child wins over mirror inheritance and reports no host axes', () => {
  const result = animation.resolveDirectionalVariant(
    { down: 'down', up: 'custom-up' },
    'up',
    { pairs },
  );
  assert.deepEqual(result, { value: 'custom-up', requestedDirection: 'up', sourceDirection: 'up', authored: true, mirrorX: false, mirrorY: false });
});

test('missing UP resolves from DOWN with only vertical mirroring', () => {
  const result = animation.resolveDirectionalVariant(
    { right: 'right', down: 'down' },
    'up',
    { pairs },
  );
  assert.deepEqual(result, { value: 'down', requestedDirection: 'up', sourceDirection: 'down', authored: false, mirrorX: false, mirrorY: true });
});

test('missing master falls through to an unmirrored default', () => {
  const result = animation.resolveDirectionalVariant(
    { right: 'right' },
    'up',
    { pairs, defaultValue: 'default' },
  );
  assert.deepEqual(result, { value: 'default', requestedDirection: 'up', sourceDirection: 'default', authored: false, mirrorX: false, mirrorY: false });
});

test('materialization preserves the inherited visual when host mirroring is removed', () => {
  const source = {
    version: 2,
    durationSeconds: 1 / 12,
    framesPerSecond: 12,
    loop: false,
    layers: [{
      layerId: 'trail',
      displayName: 'Trail',
      assetId: 'effect.trail',
      depthOffset: 0,
      transform: { offset: [4, 8], rotationDeg: 12, flipY: true, origin: [0.25, 0.75] },
      blocks: [{ from: 0, through: 0, sourceFrame: 1, transform: { offset: [2, 3], rotationDeg: 5, flipX: true } }],
    }],
  };
  const materialized = animation.materializeDirectionalAnimation(source, { mirrorX: false, mirrorY: true });
  assert.deepEqual(materialized.layers[0].transform.offset, [4, -8]);
  assert.equal(materialized.layers[0].transform.rotationDeg, -12);
  assert.equal(materialized.layers[0].transform.flipY, false);
  assert.deepEqual(materialized.layers[0].blocks[0].transform.offset, [2, -3]);
  assert.equal(materialized.layers[0].blocks[0].transform.rotationDeg, -5);
  assert.equal(materialized.layers[0].blocks[0].transform.flipX, true);
  assert.deepEqual(source.layers[0].transform.offset, [4, 8]);
});
