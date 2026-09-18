import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/infrastructure/scenes/hostTooling.ts');

function key(key) {
  return { handled: false, type: 'key-down', timestamp: 1, key, pressed: true, released: false };
}

test('focused modal controls navigate first, Escape closes second, and hidden modal trees release input', () => {
  let tree;
  const router = new t.InputRouter({
    sink: { enqueueInput(event) { tree?.dispatchInput(event); } },
    eventTarget: new EventTarget(),
    isPaused: () => tree?.paused ?? false,
  });
  const modal = new t.ModalRootControlNode({ runtimeId: 'ui/modal', name: 'Modal', inputRouter: router, open: true });
  const list = new t.ItemListControlNode({
    runtimeId: 'ui/modal/list', name: 'Choices', inputRouter: router, focused: true, processWhenPaused: true,
    items: [{ id: 'one', label: 'One' }, { id: 'two', label: 'Two' }, { id: 'three', label: 'Three', disabled: true }],
    selectedIndex: 0,
  });
  const selections = [];
  const closes = [];
  const receiver = new t.Node({ runtimeId: 'ui/modal/receiver', name: 'Receiver' });
  receiver.registerSignalHandler('on_select', (selection) => selections.push(selection.item.id));
  receiver.registerSignalHandler('on_close', () => closes.push('close'));
  list.createSignal('item_selected').connect(receiver, 'on_select');
  modal.createSignal('close_requested').connect(receiver, 'on_close');
  modal.add_child(list);
  modal.add_child(receiver);
  tree = new t.SceneTree();
  tree.setRoot(modal);
  tree.paused = true;

  const navigate = router.route(key('ArrowRight'));
  assert.equal(navigate.handled, true);
  assert.equal(list.selectedIndex, 1);
  assert.deepEqual(selections, ['two']);
  assert.deepEqual(closes, []);

  list.focused = false;
  const escape = router.route(key('Escape'));
  assert.equal(escape.handled, true);
  assert.deepEqual(closes, ['close']);

  modal.setOpen(false);
  const released = router.route(key('Escape'));
  assert.equal(released.handled, false);

  tree.shutdown();
  router.destroy();
});

test('button keyboard activation uses the same typed signal as pointer activation', () => {
  const button = new t.ButtonControlNode({ runtimeId: 'ui/button', name: 'Confirm', focused: true });
  let pressed = 0;
  const receiver = new t.Node({ runtimeId: 'ui/button/receiver', name: 'Receiver' });
  receiver.registerSignalHandler('on_pressed', () => { pressed += 1; });
  button.createSignal('pressed').connect(receiver, 'on_pressed');
  button.add_child(receiver);
  const tree = new t.SceneTree();
  tree.setRoot(button);
  const event = key('Enter');
  button.handleRoutedInput(event);
  assert.equal(event.handled, true);
  assert.equal(pressed, 1);
  tree.shutdown();
});
