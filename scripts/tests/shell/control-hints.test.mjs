import test from 'node:test';
import assert from 'node:assert/strict';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { ControlHintsController, CONTROL_HINTS } = await loadTypescriptModule('src/game/features/hints/ControlHints.ts');

function harness(relevant = new Set(['move'])) {
  const learned = new Set();
  const models = [];
  const hints = new ControlHintsController({
    isLearned: (id) => learned.has(id),
    learn: (id) => learned.add(id),
    isRelevant: (id) => relevant.has(id),
  });
  hints.subscribe('control-hint', (model) => models.push(model));
  return { hints, learned, relevant, models };
}

test('the first unlearned relevant hint shows, one at a time, in priority order', () => {
  const h = harness(new Set(['move', 'attack']));
  h.hints.update();
  assert.equal(h.hints.showing, 'move');
  assert.equal(h.models.at(-1).opacity, 1);
  h.hints.learn('move');
  assert.equal(h.hints.showing, undefined);
  assert.equal(h.models.at(-1).opacity, 0);
  assert.equal(h.models.at(-1).text, CONTROL_HINTS[0].text, 'the words stay while the banner fades');
  h.hints.update();
  assert.equal(h.hints.showing, 'attack');
});

test('a learned hint never returns; an unlearned one waits until it is relevant again', () => {
  const h = harness(new Set(['interact']));
  h.hints.update();
  assert.equal(h.hints.showing, 'interact');
  h.relevant.delete('interact');
  h.hints.update();
  assert.equal(h.hints.showing, undefined, 'walking away from the prompt hides it');
  h.relevant.add('interact');
  h.hints.update();
  assert.equal(h.hints.showing, 'interact');
  h.hints.learn('interact');
  h.hints.update();
  assert.equal(h.hints.showing, undefined);
  assert.ok(h.learned.has('interact'));
});

test('the hints cover every control a new player needs, in teaching order', () => {
  assert.deepEqual(CONTROL_HINTS.map((hint) => hint.id), ['move', 'interact', 'attack', 'dodge', 'inventory', 'crafting', 'weapon-switch', 'sprint', 'map', 'pause']);
  const text = Object.fromEntries(CONTROL_HINTS.map((hint) => [hint.id, hint.text]));
  assert.equal(text['weapon-switch'], 'Use the mouse wheel to switch weapons: tools only work in hand');
  assert.equal(text.sprint, 'Hold Shift to sprint');
  assert.equal(text.map, 'Press M for the map');
  assert.equal(text.pause, 'Press Esc to pause, save or change settings');
});
