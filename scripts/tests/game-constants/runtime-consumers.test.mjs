import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { createServer } from 'vite';

const contentRoot = path.resolve(process.cwd(), 'src/game/content');
const eventBusStubId = '\0game-constants-event-bus-stub';
const vite = await createServer({
  configFile: false,
  root: process.cwd(),
  appType: 'custom',
  plugins: [{
    name: 'game-constants-event-bus-stub',
    enforce: 'pre',
    resolveId(source, importer) {
      if (source === './EventBus' && importer?.endsWith('/core/GameState.ts')) return eventBusStubId;
      if (source === '../core/EventBus' && importer?.endsWith('/systems/Inventory.ts')) return eventBusStubId;
      return undefined;
    },
    load(id) {
      if (id !== eventBusStubId) return undefined;
      return 'export const emittedEvents = []; export const gameEvents = { emit(event, payload) { emittedEvents.push({ event, payload }); }, on() { return this; }, once() { return this; }, off() { return this; } };';
    },
  }],
  resolve: {
    alias: {
      'virtual-character-content': path.join(contentRoot, 'characters/virtual-character-content.ts'),
      'virtual-projectile-content': path.join(contentRoot, 'projectiles/virtual-projectile-content.ts'),
      'virtual-weapon-content': path.join(contentRoot, 'weapons/virtual-weapon-content.ts'),
      'virtual-effect-content': path.join(contentRoot, 'effects/virtual-effect-content.ts'),
    },
  },
  optimizeDeps: { noDiscovery: true },
  server: { middlewareMode: true, hmr: false },
});

const { GAME_CONSTANTS } = await vite.ssrLoadModule('/src/game/Constant.ts');
const { getBaseItemDefinitions } = await vite.ssrLoadModule('/src/game/content/items/ItemCatalog.ts');
const { createInitialRunState } = await vite.ssrLoadModule('/src/game/content/initial-state/InitialRun.ts');
const { Inventory, itemRegistry } = await vite.ssrLoadModule('/src/game/systems/Inventory.ts');
const { getStats, resolveMovementSpeed } = await vite.ssrLoadModule('/src/game/systems/PlayerStats.ts');
const { gameState } = await vite.ssrLoadModule('/src/game/core/GameState.ts');

const { emittedEvents } = await vite.ssrLoadModule(eventBusStubId);

test.after(async () => vite.close());

test('configured inventory rules preserve current capacity and stack behavior', () => {
  const baseItems = getBaseItemDefinitions();
  const initialMaxSlots = GAME_CONSTANTS.inventory.initialMaxSlots;
  const woodMaxStack = GAME_CONSTANTS.inventory.maxStackByItem.wood;
  assert.equal(baseItems.wood.maxStack, woodMaxStack);
  assert.equal(baseItems['hp-potion'].maxStack, GAME_CONSTANTS.inventory.maxStackByItem['hp-potion']);
  assert.ok(itemRegistry.all().some((item) => item.category === 'weapon'));
  assert.ok(itemRegistry.all().filter((item) => item.category === 'weapon').every((item) => item.maxStack === GAME_CONSTANTS.inventory.weaponMaxStack));

  const inventory = new Inventory();
  assert.equal(inventory.maxSlots(), initialMaxSlots);
  assert.equal(inventory.add('wood', initialMaxSlots * woodMaxStack), initialMaxSlots * woodMaxStack);
  assert.equal(inventory.add('wood', 1), 0);
  assert.equal(inventory.add('unknown-item', 1), 0);
});

test('new-run defaults and global player rules come from gameplay constants', () => {
  const initial = createInitialRunState();
  assert.deepEqual(initial.player.attributes, GAME_CONSTANTS.character.player.initialAttributes);
  assert.notEqual(initial.player.attributes, GAME_CONSTANTS.character.player.initialAttributes);
  assert.equal(resolveMovementSpeed(Number.MAX_SAFE_INTEGER), GAME_CONSTANTS.character.player.movement.movementSpeedCap);
  assert.equal(getStats().iFrameMs, GAME_CONSTANTS.character.player.hitInvulnerabilityMs);
});

test('capacity is mutable and over-limit legacy stacks are grandfathered', () => {
  const inventory = new Inventory();
  const beforeEvents = emittedEvents.length;
  assert.equal(inventory.increaseMaxSlots(0), false);
  assert.equal(inventory.increaseMaxSlots(1.5), false);
  assert.equal(inventory.increaseMaxSlots(3), true);
  assert.equal(inventory.maxSlots(), GAME_CONSTANTS.inventory.initialMaxSlots + 3);
  assert.equal(emittedEvents.length, beforeEvents + 1);

  inventory.load({ maxSlots: 2, slots: [{ itemId: 'wood', count: 100 }] });
  assert.equal(inventory.add('wood', 1), 1);
  assert.deepEqual(inventory.serialize(), {
    maxSlots: 2,
    slots: [{ itemId: 'wood', count: 100 }, { itemId: 'wood', count: 1 }],
  });
  assert.equal(inventory.add('wood', 99), GAME_CONSTANTS.inventory.maxStackByItem.wood - 1);
  assert.equal(inventory.remove('wood', 2), 2);
});

test('slot removal cannot consume another stack of the same item', () => {
  const inventory = new Inventory();
  inventory.load({
    maxSlots: 3,
    slots: [
      { itemId: 'wood', count: 10 },
      { itemId: 'wood', count: 4 },
      { itemId: 'stone', count: 2 },
    ],
  });

  assert.equal(inventory.removeFromSlot(1, 3), 3);
  assert.deepEqual(inventory.getSlots(), [
    { itemId: 'wood', count: 10 },
    { itemId: 'wood', count: 1 },
    { itemId: 'stone', count: 2 },
  ]);
  assert.equal(inventory.removeFromSlot(1, 99), 1);
  assert.deepEqual(inventory.getSlots(), [
    { itemId: 'wood', count: 10 },
    { itemId: 'stone', count: 2 },
  ]);
});

test('player stats come from gameplay constants; there are no levels, XP or perks', () => {
  const stats = GAME_CONSTANTS.character.player.stats;
  gameState.load(createInitialRunState().player);
  const saved = gameState.serialize();
  for (const retired of ['level', 'currentXp', 'skillPoints', 'perks']) assert.equal(retired in saved, false, retired);
  assert.equal(gameState.maxHp, stats.maxHp);
  assert.equal(gameState.hp, stats.maxHp);
  assert.equal(gameState.maxEnergy, stats.maxEnergy);
  const derived = getStats();
  assert.equal(derived.attack, stats.attack);
  assert.equal(derived.defense, stats.defense);
  assert.equal(derived.critChance, stats.critChance);
  assert.equal(derived.critMult, stats.critMultiplier);
  assert.equal(derived.energyRegenPerSec, stats.energyRegenPerSecond);
  assert.equal(derived.damageTakenMult, 1);
});

test('a Goo Heart raises max HP for good, fills HP, and survives a save', () => {
  const stats = GAME_CONSTANTS.character.player.stats;
  const bonus = GAME_CONSTANTS.character.player.gooHeart.maxHpBonus;
  gameState.load({ ...createInitialRunState().player, hp: 10 });
  const eventStart = emittedEvents.length;
  gameState.addGooHeart();
  assert.equal(gameState.gooHearts, 1);
  assert.equal(gameState.maxHp, stats.maxHp + bonus);
  assert.equal(gameState.hp, stats.maxHp + bonus);
  assert.ok(emittedEvents.slice(eventStart).some((entry) => entry.event === 'hp.changed' && entry.payload.maxHp === stats.maxHp + bonus));
  gameState.load({ ...gameState.serialize(), hp: 999, energy: 999 });
  assert.equal(gameState.gooHearts, 1);
  assert.equal(gameState.hp, stats.maxHp + bonus, 'load clamps HP to the raised maximum');
  assert.equal(gameState.energy, stats.maxEnergy);
});
