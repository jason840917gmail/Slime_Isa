import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/infrastructure/scenes/hostTooling.ts');
const { GlobalAudioServices } = await loadTypescriptModule('src/game/infrastructure/audio/GlobalAudioServices.ts');

test('Slider snaps and clamps user changes and emits only when the value moves', () => {
  const root = new t.Node({ runtimeId: 'ui/root', name: 'Root' });
  const slider = new t.SliderControlNode({ runtimeId: 'ui/volume', name: 'Music', value: 0.5, min: 0, max: 1, step: 0.05 });
  const receiver = new t.Node({ runtimeId: 'ui/receiver', name: 'Receiver' });
  const changes = [];
  receiver.registerSignalHandler('on_value_changed', (payload) => changes.push(payload));
  root.add_child(slider); root.add_child(receiver);
  const tree = new t.SceneTree(); tree.setRoot(root);
  slider.createSignal('value_changed').connect(receiver, 'on_value_changed');
  assert.equal(slider.change(0.52), false, '0.52 snaps back to 0.5, so nothing changes');
  assert.equal(slider.change(0.73), true);
  assert.equal(slider.value, 0.75);
  assert.equal(slider.change(4), true);
  assert.equal(slider.value, 1);
  slider.value = -3;
  assert.equal(slider.value, 0, 'model writes clamp without emitting');
  assert.deepEqual(changes, [{ control: 'Music', value: 0.75 }, { control: 'Music', value: 1 }]);
  tree.shutdown();
});

test('the master slider scales every bus and master mute silences them', () => {
  const services = new GlobalAudioServices({ on() {}, off() {} });
  services.setVolume('effects', 0.5);
  services.setMasterVolume(0.5);
  assert.equal(services.volume('effects'), 0.25);
  assert.equal(services.volume('music'), 0.5);
  services.setMasterMuted(true);
  assert.equal(services.muted('music'), true);
  assert.throws(() => services.setMasterVolume(2));
});

