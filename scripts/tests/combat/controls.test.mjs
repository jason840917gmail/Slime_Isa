import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { harvestToolAdvice } = await loadTypescriptModule('src/game/features/combat/HarvestAdvice.ts');
const { fitWeaponSlots } = await loadTypescriptModule('src/game/core/WeaponSlots.ts');
const { aimToward, snapToCardinal } = await loadTypescriptModule('src/game/features/player/PointerAim.ts');
const bindings = await loadTypescriptModule('src/game/features/player/PlayerInputActions.ts');
const labels = await loadTypescriptModule('src/game/features/player/ControlLabels.ts');
const { inputEventFromDom } = await loadTypescriptModule('src/game/runtime/scene/input/InputEvent.ts');

test('every input code drives one action, and the router map follows the table', () => {
  const seen = new Map();
  for (const table of [bindings.PLAYER_ACTION_BINDINGS, bindings.SHELL_ACTION_BINDINGS]) {
    for (const [action, codes] of Object.entries(table)) {
      assert.ok(codes.length > 0, `${action} has a binding`);
      for (const code of codes) {
        assert.equal(seen.has(code), false, `${code} is bound to both ${seen.get(code)} and ${action}`);
        seen.set(code, action);
      }
    }
  }
  assert.equal(bindings.PLAYER_INPUT_ACTIONS.KeyW, 'move-up');
  assert.equal(bindings.PLAYER_INPUT_ACTIONS.Mouse0, 'attack');
  assert.equal(bindings.PLAYER_INPUT_ACTIONS.Mouse2, 'interact');
  assert.equal(bindings.PLAYER_INPUT_ACTIONS.Space, 'jump');
  assert.equal(bindings.PLAYER_INPUT_ACTIONS.Digit1, 'dodge');
  assert.equal(bindings.PLAYER_INPUT_ACTIONS.KeyQ, 'eat');
  assert.equal(bindings.PLAYER_INPUT_ACTIONS.WheelDown, 'weapon-next');
  assert.equal(bindings.PLAYER_INPUT_ACTIONS.KeyE, undefined, 'the menu key works over open windows, outside the player');
  assert.equal(bindings.isControlCode('map', 'KeyM'), true);
});

test('labels come from the table', () => {
  assert.equal(labels.movementLabel(), 'WASD');
  assert.equal(labels.controlLabel('jump'), 'Space');
  assert.equal(labels.controlLabel('dodge'), '1');
  assert.equal(labels.controlLabel('attack'), 'Left click');
  assert.equal(labels.controlVerb('interact'), 'Right-click');
  assert.equal(labels.controlLabel('weapon-next'), 'Mouse wheel');
  assert.equal(labels.controlLabel('pause'), 'Esc');
  assert.equal(labels.controlLabels('zoom-in'), '+');
});

test('mouse buttons and the wheel act only over the game canvas', () => {
  const saved = { HTMLCanvasElement: globalThis.HTMLCanvasElement, PointerEvent: globalThis.PointerEvent, WheelEvent: globalThis.WheelEvent };
  class Canvas {}
  class PointerEventFixture extends Event {}
  class WheelEventFixture extends Event {}
  Object.assign(globalThis, { HTMLCanvasElement: Canvas, PointerEvent: PointerEventFixture, WheelEvent: WheelEventFixture });
  // Own properties shadow Event's read-only getters (type, timeStamp, target).
  const event = (Kind, type, fields) => {
    const value = Object.create(Kind.prototype);
    for (const [key, field] of Object.entries({ type, timeStamp: 10, ...fields })) Object.defineProperty(value, key, { value: field });
    return value;
  };
  try {
    const actions = bindings.PLAYER_INPUT_ACTIONS;
    const canvas = new Canvas();
    const press = inputEventFromDom(event(PointerEventFixture, 'pointerdown', { button: 2, clientX: 1, clientY: 2, target: canvas }), actions);
    assert.equal(press.action, 'interact');
    const overWindow = inputEventFromDom(event(PointerEventFixture, 'pointerdown', { button: 0, clientX: 1, clientY: 2, target: {} }), actions);
    assert.equal(overWindow.action, undefined, 'a click on a window never attacks');
    const release = inputEventFromDom(event(PointerEventFixture, 'pointerup', { button: 0, clientX: 1, clientY: 2, target: {} }), actions);
    assert.equal(release.action, 'attack', 'a release anywhere lets go of the button');
    const lines = inputEventFromDom(event(WheelEventFixture, 'wheel', { deltaY: -3, deltaMode: 1, target: canvas }), actions);
    assert.equal(lines.action, 'weapon-previous');
    assert.equal(lines.wheelDelta, 120);
    assert.equal(inputEventFromDom(event(WheelEventFixture, 'wheel', { deltaY: 100, deltaMode: 0, target: {} }), actions), undefined);
  } finally {
    for (const [name, value] of Object.entries(saved)) {
      if (value === undefined) delete globalThis[name];
      else globalThis[name] = value;
    }
  }
});

test('the pointer aims from the slime and snaps to four directions', () => {
  assert.equal(aimToward({ x: 0, y: 0 }, { x: 5, y: 5 }), undefined, 'a pointer on the slime gives no direction');
  const aim = aimToward({ x: 0, y: 0 }, { x: 30, y: 40 });
  assert.deepEqual(aim, { x: 0.6, y: 0.8, distance: 50 });
  assert.deepEqual(snapToCardinal(aim), { x: 0, y: 1 });
  assert.deepEqual(snapToCardinal({ x: -0.9, y: 0.3 }), { x: -1, y: 0 });
  assert.deepEqual(snapToCardinal({ x: 0.5, y: -0.5 }), { x: 1, y: 0 }, 'ties go sideways, like weapon swings');
});

test('the weapon in hand always swings; a blocked harvest says where the right tool is', () => {
  const capabilities = { 'basic-sword': undefined, 'stone-axe': { wood: 2 }, 'stone-pickaxe': { stone: 2 } };
  const lookup = (weaponId) => capabilities[weaponId];
  const wood = { targetTag: 'wood', minimumTier: 1 };
  assert.equal(harvestToolAdvice(wood, ['basic-sword', 'stone-axe'], ['basic-sword', 'stone-axe'], lookup), 'belt', 'switch to the axe on the belt');
  assert.equal(harvestToolAdvice(wood, ['basic-sword'], ['basic-sword', 'stone-axe'], lookup), 'bag', 'the axe is only in the bag');
  assert.equal(harvestToolAdvice({ targetTag: 'iron', minimumTier: 1 }, ['stone-pickaxe'], ['stone-pickaxe'], lookup), undefined, 'nothing owned can');
  assert.equal(harvestToolAdvice({ targetTag: 'wood', minimumTier: 3 }, ['stone-axe'], ['stone-axe'], lookup), undefined, 'a tier too low does not count');
});

test('an old belt fits the four-slot belt without losing the equipped weapon', () => {
  assert.deepEqual(fitWeaponSlots([null, 'sword', null]), [null, 'sword', null, null], 'a three-slot belt keeps its places');
  assert.deepEqual(fitWeaponSlots(['sword', null, null, null, null, 'spear']), ['sword', 'spear', null, null], 'two weapons fit: packed in order');
  assert.deepEqual(fitWeaponSlots(['a', 'b', 'c', 'd', 'e', null], 'd'), ['d', 'e', 'a', 'b'], 'the equipped weapon and the ones after it');
  assert.deepEqual(fitWeaponSlots(['a', 'b', 'c', 'd', 'e'], null), ['a', 'b', 'c', 'd']);
  assert.deepEqual(fitWeaponSlots(undefined), [null, null, null, null]);
});
