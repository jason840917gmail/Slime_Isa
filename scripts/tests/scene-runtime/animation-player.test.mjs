import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { AnimationBinding, AnimationPlayerNode, Node, Node2D, SceneTree } = await loadTypescriptModule('src/game/runtime/scene/tooling.ts');

const numeric = (key, domains = ['physics', 'render']) => ({ key, label: key, value: { kind: 'number' }, serialized: true, inspector: 'number', animation: { interpolation: 'numeric', domains }, overridable: true });
const step = (key, kind = 'boolean', domains = ['physics', 'render']) => ({ key, label: key, value: { kind }, serialized: true, inspector: 'checkbox', animation: { interpolation: 'step', domains }, overridable: true });
const track = (property, keys) => ({ binding: 'target', property, keys });

function fixture(animations, domain = 'physics', source) {
  const target = new Node2D({ runtimeId: `animation/target-${Math.random()}`, name: 'Target', rotation: 2, visible: true });
  const descriptors = { rotation: numeric('rotation'), visible: step('visible') };
  const player = new AnimationPlayerNode({
    runtimeId: `animation/player-${Math.random()}`, name: 'Player', domain, animations, advanceSource: source,
    resolveBinding: (_player, binding, property) => {
      assert.equal(binding, 'target');
      return new AnimationBinding(target, property, descriptors[property]);
    },
  });
  const root = new Node({ runtimeId: `animation/root-${Math.random()}`, name: 'Root' });
  root.add_child(target);
  root.add_child(player);
  const tree = new SceneTree();
  tree.setRoot(root);
  return { target, player, tree };
}

test('one shared clock drives numeric and step tracks plus deterministic events and completion', () => {
  const animation = {
    durationSeconds: 3, framesPerSecond: 1, loop: false,
    tracks: [track('rotation', [{ at: 0, value: 0 }, { at: 2, value: 10 }]), track('visible', [{ at: 0, value: true }, { at: 1, value: false }])],
    events: [{ at: 0, eventId: 'start' }, { at: 1, eventId: 'first' }, { at: 1, eventId: 'second' }, { at: 2, eventId: 'end' }],
  };
  const { target, player, tree } = fixture({ run: animation });
  const events = [];
  const finished = [];
  const listener = new Node({ runtimeId: 'animation/listener', name: 'Listener' });
  listener.registerSignalHandler('event', (payload) => events.push(payload.event.eventId));
  listener.registerSignalHandler('finished', (name) => finished.push(name));
  tree.root.add_child(listener);
  tree.flushMutations();
  player.animationEvent.connect(listener, 'event');
  player.animationFinished.connect(listener, 'finished');
  player.play('run');
  assert.deepEqual(events, ['start']);
  assert.equal(target.rotation, 0);
  player.advance(1);
  assert.equal(target.rotation, 5);
  assert.equal(target.visible, false);
  assert.deepEqual(events, ['start', 'first', 'second']);
  player.advance(2);
  assert.equal(target.rotation, 10);
  assert.deepEqual(events, ['start', 'first', 'second', 'end']);
  assert.deepEqual(finished, ['run']);
  assert.equal(player.currentAnimation, undefined);
  tree.shutdown();
});

test('loop boundaries fire exact events, while seek previews silently and stop restores baselines', () => {
  const animation = {
    durationSeconds: 2, framesPerSecond: 1, loop: true,
    tracks: [track('rotation', [{ at: 0, value: 4 }, { at: 1, value: 8 }])],
    events: [{ at: 0, eventId: 'zero' }, { at: 1, eventId: 'one' }],
  };
  const { target, player, tree } = fixture({ loop: animation });
  const events = [];
  const listener = new Node({ runtimeId: 'loop/listener', name: 'Listener' });
  listener.registerSignalHandler('event', (payload) => events.push(`${payload.event.eventId}:${payload.context.cycle}`));
  tree.root.add_child(listener); tree.flushMutations(); player.animationEvent.connect(listener, 'event');
  player.play('loop');
  player.seek(1);
  assert.equal(target.rotation, 8);
  assert.deepEqual(events, ['zero:0']);
  player.stop();
  assert.equal(target.rotation, 2);
  player.play('loop');
  player.advance(2);
  assert.deepEqual(events, ['zero:0', 'zero:0', 'one:0', 'zero:1']);
  player.stop();
  assert.equal(target.rotation, 2);
  tree.shutdown();
});

test('replacement restores the original baseline and active writer conflicts are transactional', () => {
  const first = { durationSeconds: 2, framesPerSecond: 1, loop: true, tracks: [track('rotation', [{ at: 0, value: 10 }])] };
  const second = { durationSeconds: 2, framesPerSecond: 1, loop: true, tracks: [track('rotation', [{ at: 0, value: 20 }])] };
  const { target, player, tree } = fixture({ first, second });
  player.play('first');
  assert.equal(target.rotation, 10);
  player.play('second');
  assert.equal(target.rotation, 20);

  const other = new AnimationPlayerNode({
    runtimeId: 'animation/other', name: 'Other', domain: 'physics', animations: { first },
    resolveBinding: (_player, _binding, property) => new AnimationBinding(target, property, numeric(property)),
  });
  tree.root.add_child(other); tree.flushMutations();
  assert.throws(() => other.play('first'), /active animation writer/);
  assert.equal(other.currentAnimation, undefined);
  player.stop();
  assert.equal(target.rotation, 2);
  tree.shutdown();
});

test('domain restrictions reject render gameplay, and host callbacks advance exactly one clock domain', () => {
  const callbacks = new Map();
  const source = { registerCallback(phase, callback) { callbacks.set(phase, callback); return () => callbacks.delete(phase); } };
  const animation = { durationSeconds: 2, framesPerSecond: 1, loop: true, tracks: [track('rotation', [{ at: 0, value: 0 }, { at: 1, value: 6 }])] };
  const { target, player, tree } = fixture({ run: animation }, 'physics', source);
  player.play('run');
  callbacks.get('physics-animation')(1);
  assert.equal(target.rotation, 6);
  assert.equal(callbacks.has('render-animation'), false);
  tree.shutdown();
  assert.equal(callbacks.size, 0);

  assert.throws(() => fixture({ bad: { ...animation, events: [{ at: 0, eventId: 'hit', gameplay: true }] } }, 'render').player.play('bad'), /must use the physics domain/);
  const physicsOnly = numeric('rotation', ['physics']);
  const target2 = new Node2D({ runtimeId: 'animation/restricted-target', name: 'RestrictedTarget' });
  const renderPlayer = new AnimationPlayerNode({ runtimeId: 'animation/restricted', name: 'Restricted', domain: 'render', animations: { run: animation }, resolveBinding: () => new AnimationBinding(target2, 'rotation', physicsOnly) });
  assert.throws(() => renderPlayer.play('run'), /cannot animate in the render domain/);
});
