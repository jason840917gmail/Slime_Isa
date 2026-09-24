import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { GlobalAudioServices } = await loadTypescriptModule('src/game/infrastructure/audio/GlobalAudioServices.ts');

test('shared audio gate releases its only listener after unlock and on teardown', () => {
  const listeners = new Set();
  const manager = {
    locked: true,
    on(event, callback) { assert.equal(event, 'unlocked'); listeners.add(callback); },
    off(event, callback) { assert.equal(event, 'unlocked'); listeners.delete(callback); },
  };
  const audio = new GlobalAudioServices(manager);
  const calls = [];
  const cancel = audio.onUnlocked(() => calls.push('cancelled'));
  audio.onUnlocked(() => calls.push('played'));
  assert.equal(listeners.size, 1);
  cancel();
  manager.locked = false;
  for (const listener of [...listeners]) listener();
  assert.deepEqual(calls, ['played']);
  assert.equal(listeners.size, 0);
  audio.setVolume('music', 0.3);
  audio.setMuted('effects', true);
  assert.equal(audio.volume('music'), 0.3);
  assert.equal(audio.muted('effects'), true);
  assert.throws(() => audio.setVolume('music', 2), /between 0 and 1/);
  audio.destroy();

  manager.locked = true;
  const second = new GlobalAudioServices(manager);
  second.onUnlocked(() => calls.push('late'));
  assert.equal(listeners.size, 1);
  second.destroy();
  assert.equal(listeners.size, 0);
  manager.locked = false;
  assert.deepEqual(calls, ['played']);
});
