import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/infrastructure/scenes/hostTooling.ts');
const { AudioSettingsSurfacePort } = await loadTypescriptModule('src/game/features/ui/AudioSettingsSurfacePort.ts');
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

test('sound settings apply on load, update the mixer live, persist, and reset to defaults', () => {
  const applied = [];
  const saved = [];
  const mixer = {
    setMasterVolume: (value) => applied.push(['master', value]),
    setMasterMuted: (value) => applied.push(['muted', value]),
    setVolume: (bus, value) => applied.push([bus, value]),
  };
  const keyListeners = new Set();
  globalThis.HTMLElement ??= class {};
  globalThis.document ??= { addEventListener: (_type, listener) => keyListeners.add(listener), removeEventListener: (_type, listener) => keyListeners.delete(listener) };
  const modalStack = { register: () => ({ open() {}, close() {}, unregister() {} }), hasActiveSurface: () => false };
  const pauses = [];
  const defaults = { master: 0.8, effects: 1, music: 0.7, muted: false };
  const port = new AudioSettingsSurfacePort({
    modalStack, mixer, defaults, load: () => ({ master: 0.6, effects: 0.4, music: 0.2, muted: false }),
    save: (settings) => saved.push(settings), onPausedChange: (paused) => pauses.push(paused),
  });
  assert.deepEqual(applied, [['master', 0.6], ['muted', false], ['effects', 0.4], ['ambience', 0.4], ['music', 0.2]]);
  port.open();
  assert.equal(port.snapshot('audio-settings').musicLabel, 'Music  20%');
  applied.length = 0;
  port.invoke('audio-settings', 'set-volume', { control: 'Music', value: 0.9 });
  port.invoke('audio-settings', 'set-volume', { control: 'Unknown', value: 0.1 });
  assert.deepEqual(applied.find(([bus]) => bus === 'music'), ['music', 0.9]);
  assert.equal(saved.length, 1);
  port.invoke('audio-settings', 'toggle-mute');
  assert.equal(port.snapshot('audio-settings').muteLabel, 'Unmute');
  port.invoke('audio-settings', 'reset');
  assert.deepEqual(saved.at(-1), defaults);
  port.invoke('audio-settings', 'close');
  assert.deepEqual(pauses, [true, false]);
  const escape = { key: 'Escape', repeat: false, defaultPrevented: false, target: null, preventDefault() { this.defaultPrevented = true; }, stopPropagation() {} };
  for (const listener of keyListeners) listener(escape);
  assert.equal(port.isOpen(), true, 'Esc opens settings when no other surface is open');
  const handled = { ...escape, defaultPrevented: true };
  port.close();
  for (const listener of keyListeners) listener(handled);
  assert.equal(port.isOpen(), false, 'Esc already consumed by the modal stack never reopens settings');
  port.destroy();
  assert.equal(keyListeners.size, 0);
});
