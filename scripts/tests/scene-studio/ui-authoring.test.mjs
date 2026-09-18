import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { SceneViewportState } = await loadTypescriptModule('src/game/editor/scene-studio/SceneViewport.ts');
const creation = await loadTypescriptModule('src/game/editor/scene-studio/SceneCreationDialog.ts');
const descriptors = await loadTypescriptModule('src/game/infrastructure/scenes/tooling.ts');
const studioSource = await readFile(new URL('../../../src/game/editor/scene-studio/SceneStudio.ts', import.meta.url), 'utf8');

test('the common creation registry exposes the complete Control family', () => {
  const registry = descriptors.createCoreDescriptorRegistry();
  const entries = creation.sceneCreationEntries(registry);
  assert.ok(entries.some((entry) => entry.id === 'Control'));
  assert.ok(entries.some((entry) => entry.id === 'ScrollContainer'));
  const template = creation.COMMON_SCENE_TEMPLATES.find((candidate) => candidate.id === 'interface');
  assert.deepEqual(template.nodeTypes, ['Control', 'Container', 'TextureRect', 'Label', 'ProgressBar', 'Button', 'ItemList', 'GridContainer', 'ScrollContainer', 'ModalRoot']);
});

test('UI layout handles resolve nested anchors in the universal viewport', () => {
  const viewport = new SceneViewportState();
  viewport.select('button');
  const nodes = viewport.nodes([
    {
      id: 'surface', name: 'Inventory', type: 'ModalRoot', parentId: null, order: 0,
      properties: { anchorMin: [0.5, 0.5], anchorMax: [0.5, 0.5], offsetMin: [-500, -320], offsetMax: [500, 320] },
    },
    {
      id: 'button', name: 'Close', type: 'Button', parentId: 'surface', order: 0,
      properties: { anchorMin: [1, 1], anchorMax: [1, 1], offsetMin: [-80, -44], offsetMax: [0, 0] },
    },
  ]);
  assert.deepEqual(nodes[0], { id: 'surface', name: 'Inventory', type: 'ModalRoot', kind: 'ui', position: [140, 40], size: [1000, 640], selected: false });
  assert.deepEqual(nodes[1], { id: 'button', name: 'Close', type: 'Button', kind: 'ui', position: [1060, 636], size: [80, 44], selected: true });
});

test('Scene Studio renders UI layout handles as a context in the shared viewport', () => {
  assert.match(studioSource, /renderUiLayoutViewport/);
  assert.match(studioSource, /aria-label="UI layout viewport"/);
  assert.doesNotMatch(studioSource, /mountUiStudio|UiStudioController/);
});
