import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { ControlNode, InputRouter, Node, SceneTree } = await loadTypescriptModule('src/game/runtime/scene/tooling.ts');

class KeyboardEventFixture extends Event {
  constructor(type, options) {
    super(type, { cancelable: true });
    this.key = options.key;
    this.code = options.code;
  }
}

test('DOM input is normalized once, routed to focused controls, and withheld from gameplay when handled', () => {
  const previousKeyboardEvent = globalThis.KeyboardEvent;
  globalThis.KeyboardEvent = KeyboardEventFixture;
  try {
    const target = new EventTarget();
    const queued = [];
    const trace = [];
    const tree = new SceneTree();
    const router = new InputRouter({ sink: { enqueueInput: (event) => queued.push(event) }, eventTarget: target, actions: { KeyE: 'interact' }, isPaused: () => tree.paused });
    class GameplayNode extends Node {
      constructor() { super({ runtimeId: 'input/gameplay', name: 'Gameplay' }); this.set_process_unhandled_input(true); }
      _unhandled_input() { trace.push('gameplay'); }
    }
    const root = new Node({ runtimeId: 'input/root', name: 'Root' });
    const control = new ControlNode({
      runtimeId: 'input/control', name: 'Control', inputRouter: router, focused: true,
      onInput: (event) => { trace.push(`${event.type}:${event.action}`); return true; },
    });
    root.add_child(control);
    root.add_child(new GameplayNode());
    tree.setRoot(root);

    const nativeEvent = new KeyboardEventFixture('keydown', { key: 'e', code: 'KeyE' });
    target.dispatchEvent(nativeEvent);
    assert.equal(nativeEvent.defaultPrevented, true);
    assert.equal(queued.length, 1);
    assert.equal(queued[0].handled, true);
    assert.equal(queued[0].controlRouted, true);
    tree.dispatchInput(queued[0]);
    assert.deepEqual(trace, ['key-down:interact']);

    router.destroy();
    tree.shutdown();
  } finally {
    if (previousKeyboardEvent === undefined) delete globalThis.KeyboardEvent;
    else globalThis.KeyboardEvent = previousKeyboardEvent;
  }
});

test('modal controls win over focused controls and pause policy is enforced', () => {
  const target = new EventTarget();
  const router = new InputRouter({ sink: { enqueueInput() {} }, eventTarget: target, isPaused: () => true });
  const trace = [];
  const root = new Node({ runtimeId: 'modal/root', name: 'Root' });
  root.add_child(new ControlNode({ runtimeId: 'modal/focus', name: 'Focus', inputRouter: router, focused: true, inputPriority: 9999, onInput: () => { trace.push('focus'); return true; } }));
  root.add_child(new ControlNode({ runtimeId: 'modal/skipped', name: 'Skipped', inputRouter: router, modal: true, processWhenPaused: false, onInput: () => { trace.push('skipped'); return true; } }));
  root.add_child(new ControlNode({ runtimeId: 'modal/modal', name: 'Modal', inputRouter: router, modal: true, processWhenPaused: true, onInput: () => { trace.push('modal'); return true; } }));
  const tree = new SceneTree();
  tree.setRoot(root);
  router.route({ handled: false, type: 'key-down', timestamp: 1, key: 'Escape', code: 'Escape', pressed: true, released: false });
  assert.deepEqual(trace, ['modal']);
  tree.shutdown();
  router.destroy();
});

test('router teardown unregisters DOM ownership and is idempotent', () => {
  const previousKeyboardEvent = globalThis.KeyboardEvent;
  globalThis.KeyboardEvent = KeyboardEventFixture;
  try {
    const target = new EventTarget();
    const queued = [];
    const router = new InputRouter({ sink: { enqueueInput: (event) => queued.push(event) }, eventTarget: target });
    router.destroy();
    router.destroy();
    target.dispatchEvent(new KeyboardEventFixture('keydown', { key: 'a', code: 'KeyA' }));
    assert.equal(queued.length, 0);
  } finally {
    if (previousKeyboardEvent === undefined) delete globalThis.KeyboardEvent;
    else globalThis.KeyboardEvent = previousKeyboardEvent;
  }
});
