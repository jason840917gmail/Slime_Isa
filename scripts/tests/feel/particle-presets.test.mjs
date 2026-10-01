import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { ParticlePresets, PARTICLE_PRESETS } = await loadTypescriptModule('src/game/features/feel/ParticlePresets.ts');

function fakeScene(textures = Object.values(PARTICLE_PRESETS).map((preset) => preset.texture)) {
  const emitters = [];
  return {
    emitters,
    textures: { exists: (key) => textures.includes(key) },
    add: {
      particles(_x, _y, texture, config) {
        const emitter = {
          texture, config, active: true, bursts: [], depth: 0,
          setDepth(depth) { this.depth = depth; return this; },
          emitParticleAt(x, y, count) { this.bursts.push([x, y, count]); },
          destroy() { this.active = false; },
        };
        emitters.push(emitter);
        return emitter;
      },
    },
  };
}

test('one pooled emitter per preset; every burst reuses it', () => {
  const scene = fakeScene();
  const fx = new ParticlePresets();
  const unbind = fx.bind(scene);
  assert.equal(scene.emitters.length, Object.keys(PARTICLE_PRESETS).length);
  assert.ok(scene.emitters.every((emitter) => emitter.config.emitting === false), 'emitters only burst on demand');
  for (let i = 0; i < 50; i += 1) fx.play('hit-spark', i, 10);
  fx.play('boss-burst', 5, 5);
  assert.equal(scene.emitters.length, Object.keys(PARTICLE_PRESETS).length, 'no emitter per hit');
  const spark = scene.emitters.find((emitter) => emitter.texture === PARTICLE_PRESETS['hit-spark'].texture);
  assert.equal(spark.bursts.length, 50);
  assert.equal(spark.bursts[0][2], PARTICLE_PRESETS['hit-spark'].count);
  unbind();
  assert.ok(scene.emitters.every((emitter) => !emitter.active), 'unbinding frees the pool');
  fx.play('hit-spark', 0, 0);
  assert.equal(spark.bursts.length, 50, 'nothing plays once unbound');
});

test('a preset whose texture is missing is skipped, and rebinding replaces the pool', () => {
  const fx = new ParticlePresets();
  const first = fakeScene(['dust-puff']);
  fx.bind(first);
  assert.equal(first.emitters.length, 1);
  fx.play('loot-sparkle', 0, 0);
  const second = fakeScene();
  fx.bind(second);
  assert.equal(first.emitters[0].active, false, 'the old scene pool is freed');
  assert.equal(second.emitters.length, Object.keys(PARTICLE_PRESETS).length);
});
