import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { AudioEventBridge } = await loadTypescriptModule('src/game/features/audio/AudioEventBridge.ts');
const { ModalStack } = await loadTypescriptModule('src/game/ui/ModalStack.ts');

function fakeEvents() {
  const listeners = new Map();
  return {
    on(event, fn) { listeners.set(event, [...(listeners.get(event) ?? []), fn]); },
    off(event, fn) { listeners.set(event, (listeners.get(event) ?? []).filter((candidate) => candidate !== fn)); },
    emit(event, payload) { for (const fn of listeners.get(event) ?? []) fn(payload); },
    count() { return [...listeners.values()].reduce((sum, list) => sum + list.length, 0); },
  };
}

const fakeTarget = () => ({ addEventListener() {}, removeEventListener() {} });

test('global game events play their audio.global cues and unsubscribe on dispose', () => {
  const played = [];
  const events = fakeEvents();
  const bridge = new AudioEventBridge({ play: (cue) => played.push(cue) }, events);
  events.emit('player.action', { anim: 'dodge' });
  events.emit('player.action', { anim: 'walk' });
  events.emit('coins.changed', { coins: 10, delta: 5 });
  events.emit('coins.changed', { coins: 5, delta: -5 });
  events.emit('energy.changed', { energy: 30, maxEnergy: 60, delta: 2 });
  events.emit('energy.changed', { energy: 80, maxEnergy: 100, delta: 50 });
  events.emit('status.added', { kind: 'burn', stacks: 1 });
  events.emit('weapon.equipped', { weaponId: 'basic-sword' });
  events.emit('weapon.equipped', { weaponId: 'stone-pickaxe' });
  events.emit('weapon.equipped', { weaponId: null });
  events.emit('quest.completed', {});
  assert.deepEqual(played, ['Dodge', 'Coin', 'EnergyRestore', 'StatusBurn', 'EquipBlade', 'EquipTool', 'QuestComplete']);
  bridge.dispose();
  assert.equal(events.count(), 0);
});

test('modal surfaces sound on open and close, except those with their own cues', () => {
  const played = [];
  const stack = new ModalStack(fakeTarget());
  let inventoryOpen = false;
  const inventory = stack.register('inventory', { isOpen: () => inventoryOpen, close: () => { inventoryOpen = false; } });
  const journal = stack.register('quest-journal', { isOpen: () => true, close: () => undefined });
  const chest = stack.register('chest-inventory', { isOpen: () => true, close: () => undefined });
  const bridge = new AudioEventBridge({ play: (cue) => played.push(cue) }, fakeEvents(), stack);
  inventoryOpen = true; inventory.open(); inventory.open();
  stack.closeTopmost();
  inventory.close();
  journal.open(); journal.close();
  chest.open(); chest.close();
  assert.deepEqual(played, ['MenuOpen', 'MenuClose', 'JournalOpen', 'MenuClose']);
  bridge.dispose();
  inventory.open();
  assert.equal(played.length, 4);
  stack.destroy();
});
