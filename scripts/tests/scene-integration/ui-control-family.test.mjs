import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/infrastructure/scenes/hostTooling.ts');
const descriptors = await loadTypescriptModule('src/game/infrastructure/scenes/tooling.ts');

function sceneFixture() {
  return {
    physics: {
      systems: {},
      disableUpdate() {},
      enableUpdate() {},
      world: { step() {} },
      add: { collider() { return { destroy() {} }; } },
    },
  };
}

function construction(type, properties = {}, resources = new Map()) {
  return {
    runtimeId: `ui/${type.toLowerCase()}`,
    name: type,
    type,
    properties,
    resources,
  };
}

test('minimum UI control family is described by the common registry', () => {
  const registry = descriptors.createCoreDescriptorRegistry();
  const expected = ['Control', 'Container', 'TextureRect', 'Label', 'ProgressBar', 'Button', 'ItemList', 'GridContainer', 'ScrollContainer', 'ModalRoot'];
  for (const type of expected) assert.equal(registry.nodeTypes.has(type), true, `${type} descriptor`);
  assert.deepEqual(registry.nodeTypes.get('Button').signals, [{ id: 'pressed' }]);
  assert.deepEqual(registry.nodeTypes.get('ItemList').signals, [{ id: 'item_selected', payload: 'UiListSelection' }, { id: 'item_secondary', payload: 'UiListSelection' }]);
});

test('Phaser registry constructs authored containers, labels, status, buttons, lists, scrolling, and modals', () => {
  const context = new t.PhaserNodeContext(sceneFixture());
  const registry = t.createPhaserNodeRegistry(context);

  const container = registry.construct(construction('Container', {
    anchorMin: [0, 0], anchorMax: [1, 1], direction: 'vertical', gap: 12,
    padding: [8, 12, 8, 12], align: 'center', justify: 'space-between', styleClass: 'field-panel',
  }));
  assert.equal(container instanceof t.ContainerControlNode, true);
  assert.deepEqual({ direction: container.direction, gap: container.gap, padding: container.padding, styleClass: container.styleClass }, {
    direction: 'vertical', gap: 12, padding: [8, 12, 8, 12], styleClass: 'field-panel',
  });

  const label = registry.construct(construction('Label', { text: 'Coins 12', tone: 'warning', fontSize: 12, fontWeight: 700 }));
  assert.equal(label instanceof t.LabelControlNode, true);
  assert.equal(label.text, 'Coins 12');

  const progress = registry.construct(construction('ProgressBar', { value: 25, max: 100, label: 'HP', tone: 'danger', showValue: true }));
  assert.equal(progress instanceof t.ProgressBarControlNode, true);
  assert.equal(progress.ratio, 0.25);

  const button = registry.construct(construction('Button', { text: 'Take', disabled: true }));
  assert.equal(button instanceof t.ButtonControlNode, true);
  assert.equal(button.activate(), false);

  const list = registry.construct(construction('ItemList', {
    items: [{ id: 'wood', label: 'Wood' }, { id: 'ore', label: 'Ore', disabled: true }],
    selectedIndex: 0, columns: 5, gap: 8,
  }));
  assert.equal(list instanceof t.ItemListControlNode, true);
  assert.equal(list.select(1), false);
  assert.equal(list.select(0), true);

  assert.equal(registry.construct(construction('GridContainer', { columns: 4 })) instanceof t.GridContainerControlNode, true);
  assert.equal(registry.construct(construction('ScrollContainer', { scrollAxis: 'horizontal' })) instanceof t.ScrollContainerControlNode, true);
  const modal = registry.construct(construction('ModalRoot', { open: true }));
  assert.equal(modal instanceof t.ModalRootControlNode, true);
  assert.deepEqual({ open: modal.open, visible: modal.visible, modal: modal.modal, consumeInput: modal.consumeInput }, {
    open: true, visible: true, modal: true, consumeInput: true,
  });
});

test('TextureRect resolves an authored texture resource through the shared asset boundary', () => {
  const resource = { version: 1, resourceId: 'ui.icon', kind: 'texture', assetId: 'ui.icon.asset' };
  const resources = new Map([[resource.resourceId, resource]]);
  const context = new t.PhaserNodeContext(sceneFixture(), resources, (assetId) => `runtime:${assetId}`);
  const registry = t.createPhaserNodeRegistry(context);
  const image = registry.construct(construction('TextureRect', { texture: { resourceId: resource.resourceId }, alt: 'Potion', fit: 'contain' }, resources));
  assert.equal(image instanceof t.TextureRectControlNode, true);
  assert.equal(image.assetKey, 'runtime:ui.icon.asset');
  assert.equal(image.alt, 'Potion');
});
