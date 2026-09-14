import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/infrastructure/scenes/hostTooling.ts');

test('Control presentation owns one DOM lease and resolves anchors plus offsets', () => {
  const children = [];
  const rootElement = { clientWidth: 400, clientHeight: 200, append(element) { children.push(element); } };
  const createElement = () => ({ dataset: {}, style: {}, remove() { const index = children.indexOf(this); if (index >= 0) children.splice(index, 1); } });
  const presentation = new t.ControlPresentationAdapter({ root: rootElement, createElement });
  const control = new t.ControlNode({
    runtimeId: 'control/panel', name: 'Panel', presentation,
    layout: { anchorMin: { x: 0.25, y: 0.5 }, anchorMax: { x: 0.75, y: 1 }, offsetMin: { x: -10, y: 4 }, offsetMax: { x: 10, y: -6 } },
  });
  const tree = new t.SceneTree();
  tree.setRoot(control);
  tree.process(0);
  const element = presentation.elementFor(control);
  assert.deepEqual({ left: element.style.left, top: element.style.top, width: element.style.width, height: element.style.height }, { left: '90px', top: '104px', width: '220px', height: '90px' });
  assert.equal(presentation.size, 1);
  control.visible = false;
  tree.process(0);
  assert.equal(element.style.display, 'none');
  tree.shutdown();
  assert.equal(presentation.size, 0);
  assert.equal(children.length, 0);
});

test('Phaser registry constructs Control with authored layout and UI services', () => {
  const scene = {
    physics: { systems: {}, disableUpdate() {}, enableUpdate() {}, world: { step() {} }, add: { collider() { return { destroy() {} }; } } },
  };
  const context = new t.PhaserNodeContext(scene);
  const registry = t.createPhaserNodeRegistry(context);
  const control = registry.construct({
    runtimeId: 'registry/control', name: 'Control', type: 'Control', resources: new Map(),
    properties: { anchorMin: [0, 0], anchorMax: [1, 1], offsetMin: [2, 3], offsetMax: [-4, -5], modal: true },
  });
  assert.equal(control instanceof t.ControlNode, true);
  assert.deepEqual(control.layout.offsetMax, { x: -4, y: -5 });
  assert.equal(control.modal, true);
});
