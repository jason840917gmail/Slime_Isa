import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { createServer } from 'vite';

const vite = await createServer({
  configFile: false,
  root: process.cwd(),
  appType: 'custom',
  server: { middlewareMode: true },
});

const { ModalStack } = await vite.ssrLoadModule('/src/game/ui/ModalStack.ts');
const { createTransientModalSession } = await vite.ssrLoadModule('/src/game/ui/TransientModalSession.ts');
const {
  canReopenPendingLevelUp,
  reopenPendingLevelUpWhenIdle,
} = await vite.ssrLoadModule('/src/game/ui/LevelUpReopenPolicy.ts');

test.after(async () => {
  await vite.close();
});

class FakeEventTarget {
  listeners = [];

  addEventListener(type, listener, options) {
    assert.equal(type, 'keydown');
    assert.deepEqual(options, { capture: true });
    this.listeners.push({ type, listener, options });
  }

  removeEventListener(type, listener, options) {
    assert.equal(type, 'keydown');
    assert.deepEqual(options, { capture: true });
    this.listeners = this.listeners.filter((entry) => entry.listener !== listener);
  }

  dispatch(event) {
    for (const entry of [...this.listeners]) entry.listener(event);
  }

  listenerCount() {
    return this.listeners.length;
  }
}

function keyboardEvent(key) {
  return {
    key,
    defaultPrevented: false,
    propagationStopped: false,
    preventDefault() {
      this.defaultPrevented = true;
    },
    stopPropagation() {
      this.propagationStopped = true;
    },
  };
}

test('Escape closes active surfaces in LIFO order and leaves unused events alone', () => {
  const target = new FakeEventTarget();
  const stack = new ModalStack(target);
  const parentState = { open: false, closes: 0 };
  const childState = { open: false, closes: 0 };

  const parent = stack.register('parent', {
    isOpen: () => parentState.open,
    close: () => {
      parentState.open = false;
      parentState.closes += 1;
    },
  });
  const child = stack.register('child', {
    isOpen: () => childState.open,
    close: () => {
      childState.open = false;
      childState.closes += 1;
    },
  });

  parentState.open = true;
  parent.open();
  childState.open = true;
  child.open();
  assert.equal(stack.hasActiveSurface(), true);

  const firstEscape = keyboardEvent('Escape');
  target.dispatch(firstEscape);
  assert.equal(childState.closes, 1);
  assert.equal(parentState.closes, 0);
  assert.equal(firstEscape.defaultPrevented, true);
  assert.equal(firstEscape.propagationStopped, true);

  const secondEscape = keyboardEvent('Escape');
  target.dispatch(secondEscape);
  assert.equal(parentState.closes, 1);
  assert.equal(stack.hasActiveSurface(), false);

  const unusedEscape = keyboardEvent('Escape');
  target.dispatch(unusedEscape);
  assert.equal(unusedEscape.defaultPrevented, false);
  assert.equal(unusedEscape.propagationStopped, false);

  stack.destroy();
  assert.equal(target.listenerCount(), 0);
});

test('a guarded top surface consumes Escape without closing or losing its position', () => {
  const target = new FakeEventTarget();
  const stack = new ModalStack(target);
  let busy = true;
  let closes = 0;
  const handle = stack.register('guarded', {
    isOpen: () => true,
    canClose: () => !busy,
    close: () => { closes += 1; },
  });
  handle.open();

  const blockedEscape = keyboardEvent('Escape');
  target.dispatch(blockedEscape);
  assert.equal(closes, 0);
  assert.equal(stack.hasActiveSurface(), true);
  assert.equal(blockedEscape.defaultPrevented, true);
  assert.equal(blockedEscape.propagationStopped, true);

  busy = false;
  target.dispatch(keyboardEvent('Escape'));
  assert.equal(closes, 1);
  assert.equal(stack.hasActiveSurface(), false);
  stack.destroy();
});

test('transient persistence sessions unregister, reopen, and remain active while busy', () => {
  const target = new FakeEventTarget();
  const stack = new ModalStack(target);
  let busy = false;
  let closedCount = 0;

  const openSession = () => createTransientModalSession({
    modalStack: stack,
    id: 'persistence',
    canClose: () => !busy,
    onClosed: () => { closedCount += 1; },
  });

  const first = openSession();
  assert.equal(first.isOpen(), true);
  assert.equal(first.requestClose(), true);
  assert.equal(first.isOpen(), false);
  assert.equal(first.requestClose(), false);
  assert.equal(closedCount, 1);

  const second = openSession();
  assert.throws(() => openSession(), /already registered/);
  busy = true;
  const blockedEscape = keyboardEvent('Escape');
  target.dispatch(blockedEscape);
  assert.equal(second.isOpen(), true);
  assert.equal(stack.hasActiveSurface(), true);
  assert.equal(blockedEscape.defaultPrevented, true);
  assert.equal(second.requestClose(), false);
  assert.equal(closedCount, 1);

  busy = false;
  target.dispatch(keyboardEvent('Escape'));
  assert.equal(second.isOpen(), false);
  assert.equal(stack.hasActiveSurface(), false);
  assert.equal(closedCount, 2);

  const cleanupError = new Error('cleanup failed');
  const throwing = createTransientModalSession({
    modalStack: stack,
    id: 'persistence',
    canClose: () => true,
    onClosed: () => { throw cleanupError; },
  });
  assert.throws(() => throwing.requestClose(), cleanupError);
  assert.equal(throwing.isOpen(), false);
  assert.equal(throwing.requestClose(), false);
  assert.doesNotThrow(() => openSession().requestClose());
  stack.destroy();
});

test('level-up reopening policy rejects invalid states and P is blocked by active surfaces', () => {
  assert.equal(canReopenPendingLevelUp({ isOpen: true, isClosing: false, choiceCount: 3 }), false);
  assert.equal(canReopenPendingLevelUp({ isOpen: false, isClosing: true, choiceCount: 3 }), false);
  assert.equal(canReopenPendingLevelUp({ isOpen: false, isClosing: false, choiceCount: 0 }), false);
  assert.equal(canReopenPendingLevelUp({ isOpen: false, isClosing: false, choiceCount: 3 }), true);

  let reopenCalls = 0;
  const levelUpModal = {
    reopenPending: () => {
      reopenCalls += 1;
      return true;
    },
  };
  assert.equal(reopenPendingLevelUpWhenIdle({ hasActiveSurface: () => true }, levelUpModal), false);
  assert.equal(reopenCalls, 0);
  assert.equal(reopenPendingLevelUpWhenIdle({ hasActiveSurface: () => false }, levelUpModal), true);
  assert.equal(reopenCalls, 1);
});

test('handles are token-scoped across unregister and ID reuse', () => {
  const stack = new ModalStack(new FakeEventTarget());
  assert.throws(() => {
    stack.register('duplicate', { isOpen: () => false, close: () => {} });
    stack.register('duplicate', { isOpen: () => false, close: () => {} });
  }, /already registered/);

  let oldOpen = false;
  const oldHandle = stack.register('reused', {
    isOpen: () => oldOpen,
    close: () => { oldOpen = false; },
  });
  oldHandle.open();
  oldHandle.unregister();

  let newOpen = false;
  const newHandle = stack.register('reused', {
    isOpen: () => newOpen,
    close: () => { newOpen = false; },
  });
  oldHandle.open();
  oldHandle.close();
  newOpen = true;
  newHandle.open();
  assert.equal(stack.hasActiveSurface(), true);
  newHandle.unregister();
  newHandle.unregister();
  assert.equal(stack.hasActiveSurface(), false);
  stack.destroy();
});

test('re-entrant and throwing close callbacks preserve one retryable top entry', () => {
  const stack = new ModalStack(new FakeEventTarget());
  let open = true;
  let nestedCloseResult;
  let handle;
  handle = stack.register('throwing', {
    isOpen: () => open,
    close: () => {
      handle.open();
      nestedCloseResult = stack.closeTopmost();
      throw new Error('close failed');
    },
  });
  handle.open();

  assert.throws(() => stack.closeTopmost(), /close failed/);
  assert.equal(nestedCloseResult, false);
  assert.equal(stack.hasActiveSurface(), true);
  open = false;
  assert.equal(stack.closeTopmost(), false);
  stack.destroy();
});

test('destroy is idempotent and boolean queries are false afterward', () => {
  const target = new FakeEventTarget();
  const stack = new ModalStack(target);
  const handle = stack.register('surface', { isOpen: () => true, close: () => {} });
  handle.open();
  stack.destroy();
  stack.destroy();
  assert.equal(stack.hasActiveSurface(), false);
  assert.equal(stack.closeTopmost(), false);
  assert.throws(() => stack.register('later', { isOpen: () => false, close: () => {} }), /destroy/);
  handle.open();
  handle.close();
  handle.unregister();
  assert.equal(target.listenerCount(), 0);
});

test('WorldScene integration keeps one shared Escape contract', () => {
  const root = process.cwd();
  const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8');
  const worldScene = read('src/game/scenes/WorldScene.ts');
  const config = read('src/game/config.ts');
  const surfaceFiles = [
    'src/game/ui/InventoryUI.ts',
    'src/game/ui/CraftingUI.ts',
    'src/game/ui/WorldMapUI.ts',
    'src/game/ui/QuestJournal.ts',
    'src/game/ui/LevelUpModal.ts',
    'src/game/ChatUI.ts',
    'src/game/ShopUI.ts',
  ];

  for (const file of surfaceFiles) {
    const source = read(file);
    assert.doesNotMatch(source, /KeyCodes\.ESC/);
  }
  assert.doesNotMatch(read('src/game/ChatUI.ts'), /document\.addEventListener\(['"]keydown/);
  assert.doesNotMatch(read('src/game/devTools.ts'), /event\.key === 'Escape'/);
  assert.match(config, /new ModalStack\(\)/);
  assert.match(config, /registry\.set\('modalStack'/);
  assert.match(worldScene, /registry\.get\('modalStack'/);
  assert.match(worldScene, /keydown-P/);
  const registrations = {
    inventory: 'src/game/ui/InventoryUI.ts',
    crafting: 'src/game/ui/CraftingUI.ts',
    'world-map': 'src/game/ui/WorldMapUI.ts',
    'quest-journal': 'src/game/ui/QuestJournal.ts',
    'level-up': 'src/game/ui/LevelUpModal.ts',
    chat: 'src/game/ChatUI.ts',
    shop: 'src/game/ShopUI.ts',
  };
  for (const [id, file] of Object.entries(registrations)) {
    assert.match(read(file), new RegExp(`register\\('${id}'`));
  }
  const devTools = read('src/game/devTools.ts');
  assert.match(devTools, /createTransientModalSession/);
  assert.match(devTools, /id: 'persistence'/);
  assert.match(devTools, /const canClose = \(\): boolean => !state\.busy/);
  assert.doesNotMatch(devTools, /modalHandle\.close\(\)/);
});
