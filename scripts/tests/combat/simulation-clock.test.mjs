import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { ComboSystem } = await loadTypescriptModule('src/game/combat/ComboSystem.ts');

function combo(clock) {
  const events = [];
  const system = new ComboSystem(() => clock.now, {
    onComboHit: (count) => events.push(['hit', count]),
    onComboReset: () => events.push(['reset']),
    onComboFinish: (count) => events.push(['finish', count]),
  });
  return { system, events };
}

test('the combo chain window is measured on the injected gameplay clock', () => {
  const clock = { now: 1000 };
  const { system, events } = combo(clock);
  assert.equal(system.registerHit(), 1.15);
  // A modal pause freezes the gameplay clock however long it lasts in wall time.
  system.update();
  assert.equal(system.current, 1);
  clock.now += 500;
  assert.equal(system.registerHit(), 1.5);
  clock.now += 601;
  system.update();
  assert.equal(system.current, 0);
  assert.deepEqual(events, [['hit', 1], ['hit', 2], ['reset']]);
});
