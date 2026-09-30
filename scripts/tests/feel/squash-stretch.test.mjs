import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { SquashStretch, SQUASH_PRESETS, squashStart, REDUCED_MOTION_SQUASH } = await loadTypescriptModule('src/game/features/feel/SquashStretch.ts');

function harness({ reduceMotion = false, busy = false } = {}) {
  const effects = { scaleX: 1, scaleY: 1, alpha: 1, offsetX: 0, offsetY: 0 };
  const tweens = [];
  const scene = {
    tweens: {
      add(config) {
        const tween = { config, stop() { config.onStop?.(); } };
        tweens.push(tween);
        return tween;
      },
    },
  };
  const state = { reduceMotion, busy };
  const squash = new SquashStretch({ scene, effects: () => effects, reduceMotion: () => state.reduceMotion, busy: () => state.busy });
  return { squash, effects, tweens, state, finish: () => tweens.at(-1).config.onComplete?.() };
}

test('each of the five events snaps to its shape and springs back to rest', () => {
  for (const event of ['move-start', 'jump', 'land', 'hit', 'gulp']) {
    const h = harness();
    h.squash.play(event);
    assert.equal(h.effects.scaleX, SQUASH_PRESETS[event].scaleX, `${event} x`);
    assert.equal(h.effects.scaleY, SQUASH_PRESETS[event].scaleY, `${event} y`);
    assert.deepEqual([h.tweens[0].config.scaleX, h.tweens[0].config.scaleY], [1, 1], `${event} tweens to rest`);
    h.finish();
    assert.deepEqual([h.effects.scaleX, h.effects.scaleY], [1, 1], `${event} ends at rest`);
  }
});

test('a new event replaces the one playing, and the body still ends at rest', () => {
  const h = harness();
  h.squash.play('hit');
  h.squash.play('land');
  assert.equal(h.tweens.length, 2);
  assert.equal(h.effects.scaleX, SQUASH_PRESETS.land.scaleX, 'the stopped hit did not overwrite the landing');
  h.finish();
  assert.deepEqual([h.effects.scaleX, h.effects.scaleY], [1, 1]);
  h.squash.play('gulp');
  h.squash.destroy();
  assert.deepEqual([h.effects.scaleX, h.effects.scaleY], [1, 1], 'destroy returns the body to rest');
});

test('reduce motion softens the shape; a busy ability blocks all but a forced landing', () => {
  const soft = squashStart(SQUASH_PRESETS.land, true);
  assert.ok(Math.abs(soft.x - (1 + (SQUASH_PRESETS.land.scaleX - 1) * REDUCED_MOTION_SQUASH)) < 1e-9);
  const h = harness({ reduceMotion: true, busy: true });
  h.squash.play('hit');
  assert.equal(h.tweens.length, 0, 'the ability owns the body');
  h.squash.play('land', true);
  assert.ok(h.effects.scaleX > 1 && h.effects.scaleX < SQUASH_PRESETS.land.scaleX, 'softened landing');
});
