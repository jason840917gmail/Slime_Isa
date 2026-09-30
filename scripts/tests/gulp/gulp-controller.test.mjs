import test from 'node:test';
import assert from 'node:assert/strict';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { GulpController } = await loadTypescriptModule('src/game/features/gulp/GulpController.ts');
const { gulpWheelSlotAngle, pickGulpWheelSlot } = await loadTypescriptModule('src/game/features/gulp/GulpWheelLayout.ts');

function harness({ stone = 0, silk = 0, spots = [], player = { x: 0, y: 0 } } = {}) {
  let now = 0;
  const inventory = { stone, 'silk-clump': silk };
  const changes = [];
  const messages = [];
  const controller = new GulpController({
    now: () => now,
    formDurationMs: 60_000,
    playerPosition: () => player,
    spots: () => spots,
    inventoryCount: (itemId) => inventory[itemId] ?? 0,
    consume: (itemId) => {
      if ((inventory[itemId] ?? 0) <= 0) return false;
      inventory[itemId] -= 1;
      return true;
    },
    onFormChanged: (form, reason) => changes.push([form?.id ?? null, reason]),
    showMessage: (text) => messages.push(text),
  });
  return { controller, inventory, changes, messages, player, advance: (ms) => { now += ms; } };
}

const stoneSpot = { x: 50, y: 0, materialItemId: 'stone', radius: 100 };

test('W at a Gulp spot takes its form for free, any number of times', () => {
  const h = harness({ spots: [stoneSpot] });
  assert.equal(h.controller.eat(), 'spot');
  assert.equal(h.controller.activeForm?.id, 'heavy');
  assert.equal(h.controller.remainingMs(), 60_000);
  h.advance(20_000);
  assert.equal(h.controller.eat(), 'spot');
  assert.equal(h.controller.remainingMs(), 60_000, 'eating the same material at a spot restarts the timer');
  assert.deepEqual(h.changes, [['heavy', 'started'], ['heavy', 'refreshed']]);
  assert.equal(h.inventory.stone, 0);
});

test('W in a form away from any spot burps it; W with nothing to eat says so', () => {
  const h = harness({ spots: [stoneSpot] });
  h.controller.eat();
  h.player.x = 500;
  assert.equal(h.controller.eat(), 'burp');
  assert.equal(h.controller.activeForm, undefined);
  assert.equal(h.controller.eat(), 'nothing');
  assert.deepEqual(h.messages, ['Nothing to gulp']);
  assert.deepEqual(h.changes.at(-1), [null, 'burp']);
});

test('W away from spots eats one carried material', () => {
  const h = harness({ stone: 2 });
  assert.equal(h.controller.eat(), 'inventory');
  assert.equal(h.controller.activeForm?.id, 'heavy');
  assert.equal(h.inventory.stone, 1);
});

test('a form ends by itself when its time is up, and clear() drops it without a burp', () => {
  const h = harness({ stone: 1 });
  h.controller.eat();
  h.advance(59_999);
  h.controller.update();
  assert.equal(h.controller.activeForm?.id, 'heavy');
  h.advance(1);
  h.controller.update();
  assert.equal(h.controller.activeForm, undefined);
  assert.deepEqual(h.changes.at(-1), [null, 'expired']);

  const cleared = harness({ spots: [stoneSpot] });
  cleared.controller.eat();
  cleared.controller.clear();
  assert.deepEqual(cleared.changes.at(-1), [null, 'cleared']);
});

test('the nearest spot in reach wins; spots out of reach are ignored', () => {
  const far = { ...stoneSpot, x: 400 };
  const h = harness({ spots: [far, stoneSpot] });
  assert.equal(h.controller.nearestSpot(), stoneSpot);
  h.player.x = 300;
  assert.equal(h.controller.nearestSpot(), far);
  h.player.x = 1000;
  assert.equal(h.controller.nearestSpot(), undefined);
});

test('silk makes the slime Sticky (crosses webs), and eating stone switches to Heavy', () => {
  const silkSpot = { x: 50, y: 0, materialItemId: 'silk-clump', radius: 100 };
  const h = harness({ spots: [silkSpot], stone: 1 });
  assert.equal(h.controller.eat(), 'spot');
  assert.equal(h.controller.activeForm?.id, 'sticky');
  assert.equal(h.controller.activeForm?.crossesWebs, true);
  assert.equal(h.controller.activeForm?.pressesPlates, false);
  h.player.x = 500;
  assert.equal(h.controller.eat(), 'burp', 'W away from a spot burps the form');
  assert.equal(h.controller.eat(), 'inventory', 'then W eats the carried stone');
  assert.equal(h.controller.activeForm?.id, 'heavy');
  assert.equal(h.controller.activeForm?.crossesWebs, false);
});

test('the quick wheel lists carried Gulp materials and eats the chosen one, switching forms', () => {
  const h = harness({ stone: 2, silk: 1 });
  assert.deepEqual(h.controller.wheelEntries().map((entry) => [entry.itemId, entry.form.id, entry.count]), [['stone', 'heavy', 2], ['silk-clump', 'sticky', 1]]);
  assert.equal(h.controller.preferredMaterial, 'stone');
  assert.equal(h.controller.eatMaterial('silk-clump'), 'inventory');
  assert.equal(h.controller.activeForm?.id, 'sticky');
  assert.equal(h.controller.preferredMaterial, 'stone', 'silk is used up, so a tap would eat stone next');
  assert.equal(h.controller.eatMaterial('stone'), 'inventory', 'the wheel switches forms even while in one (no burp)');
  assert.equal(h.controller.activeForm?.id, 'heavy');
  assert.deepEqual(h.changes, [['sticky', 'started'], [null, 'switched'], ['heavy', 'started']]);
  assert.equal(h.controller.eatMaterial('silk-clump'), 'nothing', 'nothing left to eat');
  assert.equal(h.controller.eatMaterial('wood'), 'nothing', 'not a Gulp material');
  assert.deepEqual(h.controller.wheelEntries().map((entry) => entry.itemId), ['stone']);
});

test('the wheel layout starts at the top, goes clockwise, and any direction picks the nearest slot', () => {
  assert.equal(gulpWheelSlotAngle(0, 2), -90);
  assert.equal(gulpWheelSlotAngle(1, 2), 90);
  assert.equal(gulpWheelSlotAngle(1, 4), 0);
  assert.equal(pickGulpWheelSlot({ x: 0, y: 0 }, 2), undefined, 'no direction keeps the current choice');
  assert.equal(pickGulpWheelSlot({ x: 0, y: -1 }, 2), 0);
  assert.equal(pickGulpWheelSlot({ x: 0, y: 1 }, 2), 1);
  assert.equal(pickGulpWheelSlot({ x: 1, y: 0 }, 4), 1);
  assert.equal(pickGulpWheelSlot({ x: -1, y: 0 }, 4), 3);
  assert.equal(pickGulpWheelSlot({ x: -0.2, y: -1 }, 3), 0, 'wraps around the top');
  assert.equal(pickGulpWheelSlot({ x: 1, y: 1 }, 1), 0, 'one slot takes every direction');
});
