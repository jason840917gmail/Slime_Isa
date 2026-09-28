import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { applyJsonFormEdit, jsonFormFor, renderJsonForm, validateJsonForm } = await loadTypescriptModule('src/game/editor/scene-studio/JsonPropertyForms.ts');

const lists = {
  npcs: ['level-1-npc-lili'],
  enemyTypes: ['slime-spider', 'worm-brawler'],
  items: ['green-key', 'shard'],
  resourceTags: ['stone', 'wood', 'resource'],
};
const context = {
  options: (source) => ({ options: (lists[source] ?? []).map((value) => ({ value, label: value })), strict: source in lists }),
};

test('world-area data picks its form from the area kind', () => {
  assert.equal(jsonFormFor('game.world-area', 'data', { areaKind: 'npc-wander' }).fields[0].key, 'npcInstanceId');
  assert.equal(jsonFormFor('game.world-area', 'data', { areaKind: 'enemy-spawn' }).fields[0].key, 'enemies');
  assert.equal(jsonFormFor('game.world-area', 'data', { areaKind: 'enemy-safe-zone' }).fields.length, 0);
  assert.equal(jsonFormFor('game.weapon', 'attackPlans', {}), undefined);
  assert.equal(jsonFormFor(undefined, 'data', {}), undefined);
});

test('npc-wander form writes the chosen NPC and renders a dropdown of them', () => {
  const form = jsonFormFor('game.world-area', 'data', { areaKind: 'npc-wander' });
  const value = applyJsonFormEdit(form, { npcInstanceId: '' }, { kind: 'set', path: ['npcInstanceId'], raw: 'level-1-npc-lili' });
  assert.deepEqual(value, { npcInstanceId: 'level-1-npc-lili' });
  assert.match(renderJsonForm(form, value, context), /<option value="level-1-npc-lili" selected>/);
  assert.deepEqual(validateJsonForm(form, { npcInstanceId: 'ghost' }, context), ["NPC that wanders here: 'ghost' is not a known option"]);
  assert.deepEqual(validateJsonForm(form, { npcInstanceId: '' }, context), ['NPC that wanders here is not chosen']);
});

test('enemy-spawn rows add, edit, clear optional fields and remove', () => {
  const form = jsonFormFor('game.world-area', 'data', { areaKind: 'enemy-spawn' });
  let value = { enemies: [], intervalMs: 1500, maxPopulation: 4, extra: 'kept' };
  value = applyJsonFormEdit(form, value, { kind: 'add', path: ['enemies'] });
  value = applyJsonFormEdit(form, value, { kind: 'set', path: ['enemies', 0, 'type'], raw: 'slime-spider' });
  value = applyJsonFormEdit(form, value, { kind: 'set', path: ['enemies', 0, 'maxAlive'], raw: '' });
  assert.deepEqual(value, { enemies: [{ type: 'slime-spider', weight: 1 }], intervalMs: 1500, maxPopulation: 4, extra: 'kept' });
  assert.throws(() => applyJsonFormEdit(form, value, { kind: 'set', path: ['intervalMs'], raw: '1.5' }), /whole number/);
  assert.throws(() => applyJsonFormEdit(form, value, { kind: 'set', path: ['maxPopulation'], raw: '0' }), /at least 1/);
  value = applyJsonFormEdit(form, value, { kind: 'remove', path: ['enemies', 0] });
  assert.deepEqual(value.enemies, []);
});

test('hand-edited spawn JSON is checked field by field', () => {
  const form = jsonFormFor('game.world-area', 'data', { areaKind: 'enemy-spawn' });
  assert.deepEqual(validateJsonForm(form, { enemies: [{ type: 'worm-brawler', weight: 2 }], intervalMs: 2500, maxPopulation: 3 }, context), []);
  assert.deepEqual(validateJsonForm(form, { enemies: [{ type: 'dragon', weight: 0.5 }], intervalMs: '2500' }, context), [
    "Enemies (picked by weight) #1 · Enemy: 'dragon' is not a known option",
    'Enemies (picked by weight) #1 · Weight must be a whole number',
    'Spawn every (ms) must be a number',
    'Max population is missing',
  ]);
  assert.deepEqual(validateJsonForm(form, [], context), ['The value must be a JSON object ({ … })']);
});

test('chest contents edit item quantities as a whole-value form', () => {
  const form = jsonFormFor('game.chest', 'initialContents', {});
  let value = applyJsonFormEdit(form, {}, { kind: 'add', path: [], option: 'green-key' });
  value = applyJsonFormEdit(form, value, { kind: 'set', path: ['green-key'], raw: '3' });
  value = applyJsonFormEdit(form, value, { kind: 'rename', path: ['green-key'], to: 'shard' });
  assert.deepEqual(value, { shard: 3 });
  assert.throws(() => applyJsonFormEdit(form, value, { kind: 'add', path: [], option: 'shard' }), /already in the list/);
  assert.deepEqual(validateJsonForm(form, { shard: 0, nope: 1 }, context), ["Items inside: 'shard' needs a whole quantity of at least 1", "Items inside: 'nope' is not a known option"]);
});

test('gate toggles between unlocked ({}) and a locked gate', () => {
  const form = jsonFormFor('game.world-exit', 'gate', {});
  const locked = applyJsonFormEdit(form, {}, { kind: 'toggle', on: true });
  assert.equal(locked.consumeOnUnlock, true);
  assert.deepEqual(validateJsonForm(form, {}, context), []);
  assert.deepEqual(validateJsonForm(form, locked, context), ['Required item is not chosen']);
  assert.deepEqual(applyJsonFormEdit(form, locked, { kind: 'toggle', on: false }), {});
  assert.doesNotMatch(renderJsonForm(form, {}, context), /Required item/);
});

test('destructible tags are chips without duplicates', () => {
  const form = jsonFormFor('game.destructible', 'tags', {});
  let value = applyJsonFormEdit(form, ['stone'], { kind: 'add', path: [], option: 'resource' });
  value = applyJsonFormEdit(form, value, { kind: 'add', path: [], option: 'stone' });
  assert.deepEqual(value, ['stone', 'resource']);
  assert.deepEqual(applyJsonFormEdit(form, value, { kind: 'remove', path: [0] }), ['resource']);
  assert.deepEqual(validateJsonForm(form, ['stone', 'glass'], context), ["Tags: 'glass' is not a known option"]);
});

test('damage rules keep advanced keys the form does not show', () => {
  const form = jsonFormFor('game.enemy', 'damageRule', {});
  const rule = { priority: 100, damageMultiplier: 1, effectResponses: { knockback: { mode: 'immune' } } };
  assert.deepEqual(applyJsonFormEdit(form, rule, { kind: 'set', path: ['damageMultiplier'], raw: '0.5' }), { ...rule, damageMultiplier: 0.5 });
  assert.deepEqual(validateJsonForm(form, rule, context), []);
});
