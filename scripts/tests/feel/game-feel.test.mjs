import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { GameFeel, FEEL_PRESETS } = await loadTypescriptModule('src/game/features/feel/GameFeel.ts');

function harness(settings = { shakeScale: 1, reduceMotion: false }) {
  let now = 1000;
  const shakes = [];
  const current = { ...settings };
  const feel = new GameFeel(() => current);
  const unbind = feel.bind({ now: () => now, shake: (ms, intensity) => shakes.push([ms, intensity]) });
  return { feel, shakes, settings: current, unbind, advance: (ms) => { now += ms; } };
}

test('each preset shakes and holds the simulation as named', () => {
  const h = harness();
  h.feel.play('critical-hit');
  assert.deepEqual(h.shakes, [[FEEL_PRESETS['critical-hit'].shakeMs, FEEL_PRESETS['critical-hit'].shakeIntensity]]);
  assert.equal(h.feel.frozen, true);
  h.advance(FEEL_PRESETS['critical-hit'].hitStopMs);
  assert.equal(h.feel.frozen, false, 'the hit-stop ends on time');
  h.feel.play('hit');
  assert.equal(h.shakes.length, 1, 'a light hit only stops, it does not shake');
  assert.equal(h.feel.frozen, true);
  for (const event of ['player-defeated', 'boss-defeated', 'slam', 'player-hurt', 'combo-finisher']) {
    assert.ok(FEEL_PRESETS[event].shakeMs > 0 && FEEL_PRESETS[event].hitStopMs > 0, `${event} shakes and stops`);
  }
});

test('the Screen shake slider scales shakes, and overlapping hit-stops do not add up', () => {
  const h = harness({ shakeScale: 0.5, reduceMotion: false });
  h.feel.play('boss-landing', { durationMs: 200, intensity: 0.004 });
  assert.deepEqual(h.shakes, [[200, 0.002]], 'a boss\'s authored shake, scaled');
  h.settings.shakeScale = 0;
  h.feel.play('ground-crack');
  assert.equal(h.shakes.length, 1, 'a zero slider disables shake');
  h.feel.play('boss-defeated');
  h.feel.play('hit');
  h.advance(FEEL_PRESETS['boss-defeated'].hitStopMs - 1);
  assert.equal(h.feel.frozen, true);
  h.advance(1);
  assert.equal(h.feel.frozen, false, 'the longest stop wins; stops never stack');
});

test('reduce motion turns off both shake and hit-stop; nothing happens unbound', () => {
  const h = harness({ shakeScale: 0, reduceMotion: true });
  h.feel.play('player-defeated');
  assert.equal(h.shakes.length, 0);
  assert.equal(h.feel.frozen, false);
  const loose = harness();
  loose.unbind();
  loose.feel.play('slam');
  assert.equal(loose.shakes.length, 0);
  assert.equal(loose.feel.frozen, false);
});
