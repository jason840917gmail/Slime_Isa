import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let layered;
let validation;

async function loadTypeScriptModule(entryPoint) {
  const result = await build({
    absWorkingDir: repositoryRoot,
    entryPoints: [entryPoint],
    bundle: true,
    format: 'esm',
    platform: 'node',
    write: false,
  });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

before(async () => {
  [layered, validation] = await Promise.all([
    loadTypeScriptModule('src/game/shared/animation/layered.ts'),
    loadTypeScriptModule('src/game/shared/animation/layeredValidation.ts'),
  ]);
});

function animationFixture(overrides = {}) {
  return {
    version: 2,
    durationSeconds: 0.5,
    framesPerSecond: 10,
    loop: false,
    loopMode: 'wrap',
    layers: [
      {
        layerId: 'base', displayName: 'Sword', assetId: 'weapon.sword', depthOffset: 0,
        blocks: [{ from: 0, through: 4, sourceFrame: 0 }],
      },
      {
        layerId: 'trail', displayName: 'Trail', assetId: 'effect.trail', depthOffset: -0.1,
        blocks: [{ from: 1, through: 1, sourceFrame: 2 }, { from: 3, through: 4, sourceFrame: 3 }],
      },
      {
        layerId: 'glow', displayName: 'Glow', assetId: 'effect.glow', depthOffset: 0.1,
        blocks: [{ from: 2, through: 2, sourceFrame: 1 }],
      },
    ],
    ...overrides,
  };
}

const assets = new Map([
  ['weapon.sword', { kind: 'spritesheet', frameCount: 8 }],
  ['effect.trail', { kind: 'spritesheet', frameCount: 4 }],
  ['effect.glow', { kind: 'spritesheet', frameCount: 2 }],
  ['effect.image', { kind: 'image', frameCount: 1 }],
]);
const assetLookup = (assetId) => assets.get(assetId);

test('three visual layers resolve against one master frame and preserve transparent gaps', () => {
  const normalized = layered.normalizeLayeredAnimation(animationFixture());
  assert.equal(layered.layeredTimelineFrameCount(normalized), 5);
  assert.deepEqual(layered.resolveLayeredAnimationFrame(normalized, 0).map((entry) => entry.layerId), ['base']);
  assert.deepEqual(layered.resolveLayeredAnimationFrame(normalized, 1).map((entry) => entry.layerId), ['base', 'trail']);
  assert.deepEqual(layered.resolveLayeredAnimationFrame(normalized, 2).map((entry) => entry.layerId), ['base', 'glow']);
  assert.deepEqual(layered.resolveLayeredAnimationFrame(normalized, 3).map((entry) => entry.layerId), ['base', 'trail']);
  assert.equal(layered.resolveLayeredAnimationFrame(normalized, 5).length, 0);
});

test('normalization supplies transform defaults and deterministic authored depth order', () => {
  const normalized = layered.normalizeLayeredAnimation(animationFixture());
  const frame = layered.resolveLayeredAnimationFrame(normalized, 2);
  assert.deepEqual(frame[0].layerTransform, {
    offset: [0, 0], scale: [1, 1], rotationDeg: 0, flipX: false, flipY: false, origin: [0.5, 0.5],
  });
  assert.equal(frame[0].relativeDepth, 0);
  assert.ok(Math.abs(frame[1].relativeDepth - 0.102) < Number.EPSILON);
});

test('validation accepts adjacent blocks and rejects overlap and out-of-range blocks', () => {
  const adjacent = animationFixture({
    layers: [{
      layerId: 'base', displayName: 'Base', assetId: 'weapon.sword', depthOffset: 0,
      blocks: [{ from: 0, through: 1, sourceFrame: 0 }, { from: 2, through: 4, sourceFrame: 1 }],
    }],
  });
  assert.deepEqual(validation.validateLayeredAnimationDocument(adjacent, { assetLookup }), []);

  const invalid = animationFixture({
    layers: [{
      layerId: 'base', displayName: 'Base', assetId: 'weapon.sword', depthOffset: 0,
      blocks: [{ from: 0, through: 3, sourceFrame: 0 }, { from: 3, through: 5, sourceFrame: 99 }],
    }],
  });
  const issues = validation.validateLayeredAnimationDocument(invalid, { assetLookup });
  assert.ok(issues.some((issue) => issue.includes('overlaps the previous block')));
  assert.ok(issues.some((issue) => issue.includes('must be inside the animation timeline')));
  assert.ok(issues.some((issue) => issue.includes("must be inside asset 'weapon.sword'")));
});

test('validation rejects duplicate layers, non-spritesheets, invalid timing, and invalid scale', () => {
  const invalid = animationFixture({
    durationSeconds: 0.55,
    layers: [
      {
        layerId: 'same', displayName: 'First', assetId: 'effect.image', depthOffset: 0,
        transform: { scale: [1, 0] }, blocks: [{ from: 0, through: 1, sourceFrame: 0 }],
      },
      {
        layerId: 'same', displayName: 'Second', assetId: 'missing.asset', depthOffset: 0,
        blocks: [{ from: 2, through: 3, sourceFrame: 0 }],
      },
    ],
  });
  const issues = validation.validateLayeredAnimationDocument(invalid, { assetLookup });
  assert.ok(issues.some((issue) => issue.includes('must be a positive whole number')));
  assert.ok(issues.some((issue) => issue.includes("'same' is duplicated")));
  assert.ok(issues.some((issue) => issue.includes('must be a spritesheet')));
  assert.ok(issues.some((issue) => issue.includes("unknown asset 'missing.asset'")));
  assert.ok(issues.some((issue) => issue.includes('scale: values must be greater than zero')));
});

test('persisted documents require usable layers while draft validation may hold empties', () => {
  const empty = animationFixture({ layers: [] });
  assert.ok(validation.validateLayeredAnimationDocument(empty, { assetLookup }).some((issue) => issue.includes('at least one layer')));
  assert.deepEqual(validation.validateLayeredAnimationDocument(empty, { assetLookup, allowEmptyDraft: true }), []);
  const looping = animationFixture({ loop: true });
  assert.ok(validation.validateLayeredAnimationDocument(looping, { assetLookup, allowLoop: false }).some((issue) => issue.includes('loop: must be false')));
});
