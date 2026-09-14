import assert from 'node:assert/strict';
import test from 'node:test';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const viewport = await loadTypescriptModule('src/game/editor/scene-studio/ViewportSelection.ts');
const shapes = await loadTypescriptModule('src/game/editor/scene-studio/ShapeEditor.ts');
const { SceneViewportState } = await loadTypescriptModule('src/game/editor/scene-studio/SceneViewport.ts');

test('viewport rejects backend-unsupported body rotation and nonuniform circle scale', () => {
  assert.match(viewport.validateViewportTransform('CharacterBody2D', { position: [0, 0], rotation: 15, scale: [1, 1] }).join('\n'), /rotation is unsupported/);
  assert.match(viewport.validateViewportTransform('CollisionShape2D', { position: [0, 0], rotation: 0, scale: [2, 1] }, 'circle').join('\n'), /uniform scale/);
  assert.deepEqual(viewport.validateViewportTransform('Node2D', { position: [4, 8], rotation: 20, scale: [2, 1] }), []);
});

test('shape editor validates geometry and exposes authored/effective differences', () => {
  const resource = { version: 1, resourceId: 'shape.body', kind: 'collision-shape', value: { shape: 'circle', radius: 4 } };
  assert.equal(shapes.editCollisionShape(resource, { shape: 'ellipse', radiusX: 5, radiusY: 3 }).value.shape, 'ellipse');
  assert.throws(() => shapes.editCollisionShape(resource, { shape: 'circle', radius: 0 }), /positive/);
  assert.equal(shapes.collisionShapeGuide(resource.value, { shape: 'rectangle', width: 8, height: 8 }).differs, true);
  const state = new SceneViewportState();
  state.wheel(-1);
  assert.equal(state.zoom, 1.1);
});
