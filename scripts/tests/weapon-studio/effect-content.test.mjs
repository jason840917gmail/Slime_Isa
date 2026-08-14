import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let effects;
let validation;
async function load(entryPoint) {
  const result = await build({ absWorkingDir: repositoryRoot, entryPoints: [entryPoint], bundle: true, format: 'esm', platform: 'node', write: false });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}
before(async () => {
  [effects, validation] = await Promise.all([load('src/game/content/effects/normalize.ts'), load('src/game/content/effects/validation.ts')]);
});
const animation = (assetId = 'effect.spark') => ({ version: 2, durationSeconds: 0.2, framesPerSecond: 10, loop: false, layers: [{ layerId: 'spark', displayName: 'Spark', assetId, depthOffset: 0, blocks: [{ from: 0, through: 1, sourceFrame: 0 }] }] });
const lookup = (id) => id === 'effect.spark' ? { kind: 'spritesheet', frameCount: 2 } : undefined;

test('effect resolution prefers exact, then mirrored Left, then Default', () => {
  const effect = { version: 1, effectId: 'slash', displayName: 'Slash', default: animation(), directions: { right: { ...animation(), layers: [{ ...animation().layers[0], layerId: 'right' }] }, up: { ...animation(), layers: [{ ...animation().layers[0], layerId: 'up' }] } }, mirrorLeftFromRight: true };
  assert.equal(effects.resolveEffectVariant(effect, 'up').source, 'up');
  assert.deepEqual(effects.resolveEffectVariant(effect, 'left'), { animation: effects.resolveEffectVariant(effect, 'right').animation, authored: false, mirrorX: true, mirrorY: false, source: 'right' });
  assert.equal(effects.resolveEffectVariant(effect, 'down').source, 'default');
});

test('effect resolution mirrors DOWN into missing UP and keeps exact UP custom', () => {
  const inherited = { version: 1, effectId: 'slash', displayName: 'Slash', mirrorLeftFromRight: true, mirrorUpFromDown: true, directions: { right: animation(), down: animation() } };
  const up = effects.resolveEffectVariant(inherited, 'up');
  assert.equal(up.source, 'down');
  assert.equal(up.authored, false);
  assert.equal(up.mirrorX, false);
  assert.equal(up.mirrorY, true);

  const exact = { ...inherited, default: animation(), directions: { ...inherited.directions, up: animation() } };
  const exactUp = effects.resolveEffectVariant(exact, 'up');
  assert.equal(exactUp.source, 'up');
  assert.equal(exactUp.authored, true);
  assert.equal(exactUp.mirrorY, false);
  assert.deepEqual(validation.validateEffectDefinition(exact, { assetLookup: lookup }), []);
});

test('effect validation requires all directions and usable non-looping variants', () => {
  const valid = { version: 1, effectId: 'spark', displayName: 'Spark', default: animation() };
  assert.deepEqual(validation.validateEffectDefinition(valid, { assetLookup: lookup }), []);
  const invalid = { version: 1, effectId: 'bad', displayName: 'Bad', directions: { right: { ...animation('missing'), loop: true } }, mirrorLeftFromRight: true };
  const issues = validation.validateEffectDefinition(invalid, { assetLookup: lookup });
  assert.ok(issues.some((issue) => issue.includes("unknown asset 'missing'")));
  assert.ok(issues.some((issue) => issue.includes('loop: must be false')));
  assert.ok(issues.some((issue) => issue.includes("direction 'up'")));
  assert.ok(issues.some((issue) => issue.includes("direction 'down'")));
});
