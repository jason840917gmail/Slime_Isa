import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let zoomModule;

before(async () => {
  const result = await build({
    absWorkingDir: repositoryRoot,
    entryPoints: ['src/game/editor/PreviewZoom.ts'],
    bundle: true,
    format: 'esm',
    platform: 'node',
    write: false,
  });
  zoomModule = await import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
});

test('preview zoom responds to wheel direction and stays view-only', () => {
  assert.equal(zoomModule.adjustPreviewZoom(1, -100), 1.1);
  assert.equal(zoomModule.adjustPreviewZoom(1, 100), 0.9);
  assert.equal(zoomModule.adjustPreviewZoom(1, 0), 1);
});

test('preview zoom clamps to readable limits and normalizes invalid values', () => {
  assert.equal(zoomModule.clampPreviewZoom(0.1), 0.5);
  assert.equal(zoomModule.clampPreviewZoom(9), 3);
  assert.equal(zoomModule.clampPreviewZoom(Number.NaN), 1);
  assert.equal(zoomModule.adjustPreviewZoom(3, -1), 3);
  assert.equal(zoomModule.adjustPreviewZoom(0.5, 1), 0.5);
});
