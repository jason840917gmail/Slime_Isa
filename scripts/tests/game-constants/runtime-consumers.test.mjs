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
      'virtual-animation-content': path.join(contentRoot, 'animations/virtual-animation-content.ts'),
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
const { resolveLevelStats } = await vite.ssrLoadModule('/src/game/systems/PlayerProgression.ts');
const { gameState } = await vite.ssrLoadModule('/src/game/core/GameState.ts');

test('HUD initializes XP from the installed game state', async () => {
  const source = await fs.readFile(path.resolve(process.cwd(), 'src/game/HUD.ts'), 'utf8');
  assert.match(source, /private xpIntoLevel = gameState\.currentXp;/);
  assert.match(source, /private xpForNext: number \| null = gameState\.xpToNextLevel;/);
});
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

test('runtime XP grants one reward per crossed level and refills final maxima', () => {
  gameState.load(createInitialRunState().player);
  const eventStart = emittedEvents.length;
  const progression = GAME_CONSTANTS.character.player.progression;
  const levelOneXp = progression.levels[0].xpToNextLevel;
  const levelTwoXp = progression.levels[1].xpToNextLevel;
  assert.notEqual(levelOneXp, null);
  assert.notEqual(levelTwoXp, null);
  gameState.addXp(levelOneXp + levelTwoXp + 30);

  assert.equal(gameState.level, 3);
  assert.equal(gameState.currentXp, 30);
  assert.equal(gameState.xpToNextLevel, progression.levels[2].xpToNextLevel);
  assert.equal(gameState.skillPoints, 2);
  const levelThreeStats = resolveLevelStats(progression, 3);
  assert.equal(gameState.maxHp, levelThreeStats.maxHp);
  assert.equal(gameState.hp, levelThreeStats.maxHp);
  assert.equal(gameState.maxEnergy, levelThreeStats.maxEnergy);
  assert.equal(gameState.energy, levelThreeStats.maxEnergy);
  assert.deepEqual(emittedEvents.slice(eventStart).filter((entry) => entry.event === 'level.up').map((entry) => entry.payload.level), [2, 3]);
});

test('load clamps maxima without refill and maximum level cannot reward level 11', () => {
  const initial = createInitialRunState().player;
  const progression = GAME_CONSTANTS.character.player.progression;
  gameState.load({ ...initial, level: 3, currentXp: 0, hp: 999, energy: 999 });
  const levelThreeStats = resolveLevelStats(progression, 3);
  assert.equal(gameState.hp, levelThreeStats.maxHp);
  assert.equal(gameState.energy, levelThreeStats.maxEnergy);

  const finalLevel = progression.maxLevel;
  const previousLevelXp = progression.levels[finalLevel - 2].xpToNextLevel;
  assert.notEqual(previousLevelXp, null);
  gameState.load({ ...initial, level: finalLevel - 1, currentXp: previousLevelXp - 1, hp: 1, energy: 1 });
  gameState.addXp(1);
  assert.equal(gameState.level, finalLevel);
  assert.equal(gameState.currentXp, 0);
  assert.equal(gameState.xpToNextLevel, null);
  const skillPoints = gameState.skillPoints;
  gameState.addXp(999_999);
  assert.equal(gameState.level, finalLevel);
  assert.equal(gameState.currentXp, 0);
  assert.equal(gameState.skillPoints, skillPoints);
});
