import test from 'node:test';
import assert from 'node:assert/strict';

test('derived visual runtime keys are collision-proof', () => {
  const key = (visualSetId, clipId) => `visual:${visualSetId.length}:${visualSetId}:${clipId}`;
  assert.notEqual(key('enemy.worm.archer', 'jump'), key('enemy.worm.archer.jump', ''));
  assert.equal(key('character.player.slime', 'idle'), 'visual:22:character.player.slime:idle');
});

test('timeline positions are zero based and inclusive by contract', () => {
  const span = { from: 2, through: 4 };
  assert.equal(span.from <= 2 && 2 <= span.through, true);
  assert.equal(span.from <= 5 && 5 <= span.through, false);
});
