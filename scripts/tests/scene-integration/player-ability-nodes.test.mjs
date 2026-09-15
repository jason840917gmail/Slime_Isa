import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { PlayerAbilityPresentation } = await loadTypescriptModule('src/game/features/scripts/tooling.ts');

function intent(sequenceId, abilityId = 'jump') {
  return {
    abilityId,
    sequenceId,
    direction: { x: 1, y: 0 },
    start: { x: 10, y: 20 },
    target: { x: 30, y: 20 },
    definition: { abilityId, unlockLevel: 1, cooldownMs: 100, energyCost: 0 },
    cooldownUntilMs: 100,
  };
}

function backend() {
  const presentations = [];
  const rejections = [];
  return {
    presentations,
    rejections,
    present(value, complete) {
      const record = { value, complete, disposeCount: 0, completeCount: 0 };
      presentations.push(record);
      return {
        complete: () => { record.completeCount += 1; },
        dispose: () => { record.disposeCount += 1; },
      };
    },
    notifyRejected(...args) { rejections.push(args); },
  };
}

test('PlayerAbilityPresentation leases one active sequence and completes it once', () => {
  const renderer = backend();
  const presentation = new PlayerAbilityPresentation(renderer);
  const completed = [];
  assert.equal(presentation.present(intent(4), (sequenceId) => completed.push(sequenceId)), true);
  assert.equal(presentation.activeSequenceId, 4);
  assert.equal(presentation.present(intent(5), () => {}), false);

  renderer.presentations[0].complete();
  renderer.presentations[0].complete();
  assert.deepEqual(completed, [4]);
  assert.equal(renderer.presentations[0].completeCount, 1);
  assert.equal(renderer.presentations[0].disposeCount, 0);
  assert.equal(presentation.activeSequenceId, undefined);
  assert.equal(presentation.present(intent(5), (sequenceId) => completed.push(sequenceId)), true);
});

test('PlayerAbilityPresentation cancellation cleans effects without completing the decision', () => {
  const renderer = backend();
  const presentation = new PlayerAbilityPresentation(renderer);
  const completed = [];
  presentation.present(intent(7, 'teleport'), (sequenceId) => completed.push(sequenceId));
  presentation.cancel();
  renderer.presentations[0].complete();
  assert.deepEqual(completed, []);
  assert.equal(renderer.presentations[0].disposeCount, 1);
  assert.equal(renderer.presentations[0].completeCount, 0);
  assert.equal(presentation.activeSequenceId, undefined);
  presentation.dispose();
  assert.equal(presentation.present(intent(8), () => {}), false);
});

test('PlayerAbilityPresentation forwards rejection feedback without engine dependencies', () => {
  const renderer = backend();
  const presentation = new PlayerAbilityPresentation(renderer);
  presentation.notifyRejected('stretch-lash', 'locked', 4);
  presentation.notifyRejected('teleport', 'energy');
  assert.deepEqual(renderer.rejections, [
    ['stretch-lash', 'locked', 4],
    ['teleport', 'energy', undefined],
  ]);
});

test('PlayerAbilityPresentation disposes leases returned after synchronous completion', () => {
  let disposeCount = 0;
  const completed = [];
  const presentation = new PlayerAbilityPresentation({
    present(_intent, complete) {
      complete();
      return { dispose: () => { disposeCount += 1; } };
    },
    notifyRejected() {},
  });
  assert.equal(presentation.present(intent(11), (sequenceId) => completed.push(sequenceId)), true);
  assert.deepEqual(completed, [11]);
  assert.equal(disposeCount, 1);
  assert.equal(presentation.activeSequenceId, undefined);
});

test('PlayerAbilityPresentation releases its active slot when a backend throws', () => {
  const renderer = backend();
  const presentation = new PlayerAbilityPresentation({
    present() { throw new Error('render failed'); },
    notifyRejected: renderer.notifyRejected,
  });
  assert.throws(() => presentation.present(intent(12), () => {}), /render failed/);
  assert.equal(presentation.activeSequenceId, undefined);
});
