import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let previewModule;

before(async () => {
  const result = await build({
    absWorkingDir: repositoryRoot,
    entryPoints: ['src/game/editor/LayeredAnimationPreviewPanel.ts'],
    bundle: true,
    format: 'esm',
    platform: 'node',
    write: false,
  });
  previewModule = await import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
});

test('weapon-owned and shared animations use one preview panel contract', async () => {
  const html = previewModule.renderLayeredAnimationPreviewPanel({
    kicker: 'SHARED PREVIEW',
    summaryHtml: '0.00s / 0.50s',
    previewZoom: 1.2,
    playing: false,
    sceneHtml: '<span>scene</span>',
    footerHtml: '<span>footer</span>',
  });
  assert.match(html, /studio-preview-card weapon-preview-card layered-preview-card/);
  assert.match(html, /data-action="preview-zoom-out"/);
  assert.match(html, /data-action="preview-zoom-in"/);
  assert.match(html, /data-action="preview-zoom-reset"/);
  assert.match(html, /data-action="play-preview"/);
  assert.match(html, /aria-pressed="false"/);
  assert.match(html, /--preview-zoom:1\.2/);

  const [weaponSource, sharedSource] = await Promise.all([
    readFile(path.join(repositoryRoot, 'src/game/editor/LayeredWeaponStudio.ts'), 'utf8'),
    readFile(path.join(repositoryRoot, 'src/game/editor/AnimationStudio.ts'), 'utf8'),
  ]);
  assert.match(weaponSource, /renderLayeredAnimationPreviewPanel\(/);
  assert.match(sharedSource, /renderLayeredAnimationPreviewPanel\(/);
});

test('shared package workbench consumes the same timeline commands and interactions', async () => {
  const [panelSource, sharedSource, weaponSource] = await Promise.all([
    readFile(path.join(repositoryRoot, 'src/game/editor/LayeredAnimationTimelinePanel.ts'), 'utf8'),
    readFile(path.join(repositoryRoot, 'src/game/editor/AnimationStudio.ts'), 'utf8'),
    readFile(path.join(repositoryRoot, 'src/game/editor/LayeredWeaponStudio.ts'), 'utf8'),
  ]);
  assert.match(panelSource, /data-action="add-layer"/);
  assert.match(panelSource, /data-action="add-layer-tiles"/);
  assert.match(sharedSource, /target\.dataset\.animationAction \?\? target\.dataset\.action/);
  assert.match(sharedSource, /action === 'confirm-picker'/);
  assert.match(sharedSource, /document\.placeTiles/);
  assert.match(weaponSource, /document\.placeTiles/);
  assert.match(sharedSource, /handleStudioHistoryShortcut/);
  assert.match(weaponSource, /handleStudioHistoryShortcut/);
  assert.match(sharedSource, /document\.resizeBlock/);
  assert.match(sharedSource, /document\.moveBlock/);
  assert.match(sharedSource, /handleWheel/);
  assert.match(sharedSource, /data-workbench-splitter/);
  assert.match(sharedSource, /previewSplit/);
  assert.match(sharedSource, /applyWorkbenchSplit/);
  assert.match(sharedSource, /playbackGeneration/);
  assert.match(sharedSource, /updateLayeredAnimationPreviewPlayback/);
  assert.match(weaponSource, /data-workbench-splitter/);
  assert.match(weaponSource, /applyWorkbenchSplit/);
  assert.match(weaponSource, /playbackGeneration/);
  assert.match(weaponSource, /updateLayeredAnimationPreviewPlayback/);
});
