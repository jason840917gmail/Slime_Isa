import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');

async function load(entry) {
  const result = await build({
    absWorkingDir: root,
    entryPoints: [entry],
    bundle: true,
    format: 'esm',
    platform: 'node',
    write: false,
  });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

class FakeTarget {
  constructor(x, y) {
    this.x = x;
    this.y = y;
    this.active = true;
    this.listeners = new Map();
  }

  once(event, listener) {
    this.listeners.set(event, listener);
    return this;
  }

  off(event, listener) {
    if (this.listeners.get(event) === listener) this.listeners.delete(event);
    return this;
  }

  emit(event) {
    const listener = this.listeners.get(event);
    this.listeners.delete(event);
    listener?.();
  }

  listenerCount() {
    return this.listeners.size;
  }
}

test('attachment starts at and follows the target center, including inactive targets', async () => {
  const { WorldEffectAdapter } = await load('src/game/features/effects/WorldEffectAdapter.ts');
  const { WorldEffectPositionAttachment } = await load('src/game/features/effects/WorldEffectPositionAttachment.ts');
  const target = new FakeTarget(10, 20);
  const adapter = new WorldEffectAdapter(0, 0, 5, true, false);
  const attachment = new WorldEffectPositionAttachment(adapter, target, 'destroy', 0, 0);

  assert.deepEqual(adapter.getAnimationHostTransform(), {
    x: 10,
    y: 20,
    baseDepth: 5,
    rotationRad: 0,
    mirrorX: true,
    mirrorY: false,
  });

  target.x = 80;
  target.y = 90;
  target.active = false;
  attachment.update();
  assert.deepEqual([adapter.getAnimationHostTransform().x, adapter.getAnimationHostTransform().y], [80, 90]);
});

test('attachment preserves the last valid coordinate for non-finite target axes', async () => {
  const { WorldEffectAdapter } = await load('src/game/features/effects/WorldEffectAdapter.ts');
  const { WorldEffectPositionAttachment } = await load('src/game/features/effects/WorldEffectPositionAttachment.ts');
  const target = new FakeTarget(10, 20);
  const adapter = new WorldEffectAdapter(3, 4, 5, false, true);
  const attachment = new WorldEffectPositionAttachment(adapter, target, 'destroy', 3, 4);

  target.x = Number.NaN;
  target.y = 50;
  attachment.update();

  assert.deepEqual([adapter.getAnimationHostTransform().x, adapter.getAnimationHostTransform().y], [10, 50]);
});

test('target destruction freezes the final position and removes the listener', async () => {
  const { WorldEffectAdapter } = await load('src/game/features/effects/WorldEffectAdapter.ts');
  const { WorldEffectPositionAttachment } = await load('src/game/features/effects/WorldEffectPositionAttachment.ts');
  const target = new FakeTarget(10, 20);
  const adapter = new WorldEffectAdapter(0, 0, 5, false, false);
  new WorldEffectPositionAttachment(adapter, target, 'destroy', 0, 0);

  target.x = 45;
  target.y = 55;
  target.emit('destroy');
  target.x = 100;
  target.y = 110;

  assert.deepEqual([adapter.getAnimationHostTransform().x, adapter.getAnimationHostTransform().y], [45, 55]);
  assert.equal(target.listenerCount(), 0);
});

test('disposing an attachment prevents stale target events from moving a reused adapter', async () => {
  const { WorldEffectAdapter } = await load('src/game/features/effects/WorldEffectAdapter.ts');
  const { WorldEffectPositionAttachment } = await load('src/game/features/effects/WorldEffectPositionAttachment.ts');
  const adapter = new WorldEffectAdapter(0, 0, 5, false, false);
  const oldTarget = new FakeTarget(10, 20);
  const oldAttachment = new WorldEffectPositionAttachment(adapter, oldTarget, 'destroy', 0, 0);

  oldAttachment.dispose();
  const newTarget = new FakeTarget(70, 80);
  new WorldEffectPositionAttachment(adapter, newTarget, 'destroy', 70, 80);
  oldTarget.x = 1000;
  oldTarget.y = 1000;
  oldTarget.emit('destroy');

  assert.deepEqual([adapter.getAnimationHostTransform().x, adapter.getAnimationHostTransform().y], [70, 80]);
  assert.equal(oldTarget.listenerCount(), 0);
});

test('two attachments follow independent targets', async () => {
  const { WorldEffectAdapter } = await load('src/game/features/effects/WorldEffectAdapter.ts');
  const { WorldEffectPositionAttachment } = await load('src/game/features/effects/WorldEffectPositionAttachment.ts');
  const firstTarget = new FakeTarget(10, 20);
  const secondTarget = new FakeTarget(30, 40);
  const firstAdapter = new WorldEffectAdapter(0, 0, 1, false, false);
  const secondAdapter = new WorldEffectAdapter(0, 0, 2, false, false);
  const first = new WorldEffectPositionAttachment(firstAdapter, firstTarget, 'destroy', 0, 0);
  const second = new WorldEffectPositionAttachment(secondAdapter, secondTarget, 'destroy', 0, 0);

  firstTarget.x = 100;
  secondTarget.y = 200;
  first.update();
  second.update();

  assert.deepEqual([firstAdapter.getAnimationHostTransform().x, firstAdapter.getAnimationHostTransform().y], [100, 20]);
  assert.deepEqual([secondAdapter.getAnimationHostTransform().x, secondAdapter.getAnimationHostTransform().y], [30, 200]);
});
