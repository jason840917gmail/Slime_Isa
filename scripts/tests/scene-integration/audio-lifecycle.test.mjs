import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/infrastructure/scenes/hostTooling.ts');

function fakeAudioScene() {
  const handles = [];
  const scene = {
    sound: {
      add(assetId, config) {
        const events = new Map();
        const handle = {
          assetId, config, plays: 0, stops: 0, destroyed: false, volume: undefined, rate: undefined, pan: undefined,
          play() { this.plays += 1; return true; }, stop() { this.stops += 1; return true; }, destroy() { this.destroyed = true; },
          once(event, callback) { events.set(event, callback); }, off(event, callback) { if (events.get(event) === callback) events.delete(event); },
          emit(event) { events.get(event)?.(); }, setVolume(value) { this.volume = value; }, setRate(value) { this.rate = value; }, setPan(value) { this.pan = value; },
        };
        handles.push(handle);
        return handle;
      },
    },
    cameras: { main: { worldView: { centerX: 0, centerY: 0 }, midPoint: { x: 0, y: 0 } } },
  };
  return { scene, handles };
}

function unlockFixture(initiallyUnlocked = false) {
  let unlocked = initiallyUnlocked;
  const callbacks = new Set();
  return {
    service: { isUnlocked: () => unlocked, onUnlocked(callback) { callbacks.add(callback); return () => callbacks.delete(callback); } },
    unlock() { unlocked = true; for (const callback of [...callbacks]) callback(); callbacks.clear(); },
    get pending() { return callbacks.size; },
  };
}

test('audio waits for the shared gesture gate, applies preferences, and destroys preview playback on exit', () => {
  const { scene, handles } = fakeAudioScene();
  const unlock = unlockFixture();
  const state = { volume: 0.4, muted: false };
  const preferences = { volume: () => state.volume, muted: () => state.muted };
  const audio = new t.AudioStreamPlayerNode({ runtimeId: 'audio/ui', name: 'Audio', scene, assetId: 'click', autoplay: true, volume: 0.5, pitch: 1.25, preferences, unlock: unlock.service });
  const tree = new t.SceneTree();
  tree.setRoot(audio);
  assert.equal(handles[0].plays, 0);
  assert.equal(unlock.pending, 1);
  unlock.unlock();
  assert.equal(handles[0].plays, 1);
  assert.equal(handles[0].volume, 0.2);
  assert.equal(handles[0].rate, 1.25);
  state.muted = true;
  tree.process(0);
  assert.equal(handles[0].volume, 0);
  tree.shutdown();
  assert.equal(handles[0].stops > 0, true);
  assert.equal(handles[0].destroyed, true);
  assert.equal(unlock.pending, 0);
});

test('explicit loops resume after detach/re-entry, while one-shots and pending unlock requests do not leak', () => {
  const { scene, handles } = fakeAudioScene();
  const unlocked = unlockFixture(true);
  const root = new t.Node({ runtimeId: 'audio/root', name: 'Root' });
  const loop = new t.AudioStreamPlayerNode({ runtimeId: 'audio/loop', name: 'Loop', scene, assetId: 'wind', loop: true, unlock: unlocked.service });
  const oneShot = new t.AudioStreamPlayerNode({ runtimeId: 'audio/shot', name: 'Shot', scene, assetId: 'hit', unlock: unlocked.service });
  root.add_child(loop); root.add_child(oneShot);
  const tree = new t.SceneTree(); tree.setRoot(root);
  loop.play(); oneShot.play();
  assert.deepEqual(handles.map((handle) => handle.plays), [1, 1]);
  root.remove_child(loop); root.remove_child(oneShot); tree.flushMutations();
  assert.equal(loop.playing, true);
  assert.equal(oneShot.playing, false);
  root.add_child(loop); root.add_child(oneShot); tree.flushMutations();
  assert.equal(handles.length, 4);
  assert.deepEqual(handles.map((handle) => handle.plays), [1, 1, 1, 0]);
  tree.shutdown();

  const locked = unlockFixture(false);
  const pending = new t.AudioStreamPlayerNode({ runtimeId: 'audio/pending', name: 'Pending', scene, assetId: 'late', autoplay: true, unlock: locked.service });
  const pendingTree = new t.SceneTree(); pendingTree.setRoot(pending);
  assert.equal(locked.pending, 1);
  pendingTree.shutdown();
  assert.equal(locked.pending, 0);
  locked.unlock();
  assert.equal(handles.at(-1).plays, 0);
});

test('AudioStreamPlayer2D synchronizes attenuation and pan from logical world position', () => {
  const { scene, handles } = fakeAudioScene();
  const audio = new t.AudioStreamPlayer2DNode({ runtimeId: 'audio/world', name: 'WorldAudio', scene, assetId: 'buzz', position: { x: 200, y: 0 }, maxDistance: 400, panDistance: 100, autoplay: true, unlock: unlockFixture(true).service });
  const tree = new t.SceneTree(); tree.setRoot(audio); tree.process(0);
  assert.equal(handles[0].plays, 1);
  assert.equal(handles[0].volume, 0.5);
  assert.equal(handles[0].pan, 1);
  tree.shutdown();
});

test('Phaser registry resolves audio resources into positional and non-positional nodes', () => {
  const { scene } = fakeAudioScene();
  scene.physics = { systems: {}, disableUpdate() {}, enableUpdate() {}, world: { step() {} }, add: { collider() { return { destroy() {} }; } } };
  const resource = { version: 1, resourceId: 'audio.wind', kind: 'audio', assetId: 'wind' };
  const context = new t.PhaserNodeContext(scene, new Map([['audio.wind', resource]]));
  const registry = t.createPhaserNodeRegistry(context, { audioUnlock: unlockFixture(true).service });
  const common = { resources: new Map([['audio.wind', resource]]), properties: { stream: { resourceId: 'audio.wind' }, volume: 0.25 } };
  const flat = registry.construct({ ...common, runtimeId: 'registry/audio', name: 'Audio', type: 'AudioStreamPlayer' });
  const spatial = registry.construct({ ...common, runtimeId: 'registry/audio-2d', name: 'Audio2D', type: 'AudioStreamPlayer2D' });
  assert.equal(flat instanceof t.AudioStreamPlayerNode, true);
  assert.equal(spatial instanceof t.AudioStreamPlayer2DNode, true);
});
