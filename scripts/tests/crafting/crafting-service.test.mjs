import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { createServer } from 'vite';

const repositoryRoot = process.cwd();
const contentRoot = path.join(repositoryRoot, 'src/game/content');
const vite = await createServer({
  root: repositoryRoot,
  configFile: false,
  appType: 'custom',
  optimizeDeps: { noDiscovery: true },
  resolve: {
    alias: {
      'virtual-weapon-content': path.join(contentRoot, 'weapons/virtual-weapon-content.ts'),
    },
  },
  server: { middlewareMode: true, hmr: false },
});

const {
  CraftingService,
  normalizeQuantity,
} = await vite.ssrLoadModule('/src/game/crafting/CraftingService.ts');

test.after(async () => {
  await vite.close();
});

function item(id, maxStack = 99, extra = {}) {
  return {
    id,
    name: id,
    category: 'material',
    icon: id,
    description: `${id} description`,
    maxStack,
    ...extra,
  };
}

class FakeInventory {
  constructor(definitions, slots = [], maxSlots = 8) {
    this.definitions = definitions;
    this.slots = slots.map((slot) => ({ ...slot }));
    this.maxSlotsValue = maxSlots;
    this.transactionCount = 0;
  }

  count(itemId) {
    return this.slots.filter((slot) => slot.itemId === itemId).reduce((sum, slot) => sum + slot.count, 0);
  }

  previewTransact(removals, additions) {
    return this.createDraft(removals, additions) !== null;
  }

  transact(removals, additions) {
    const draft = this.createDraft(removals, additions);
    if (!draft) return false;
    this.slots = draft;
    this.transactionCount += 1;
    return true;
  }

  createDraft(removals, additions) {
    const draft = this.slots.map((slot) => ({ ...slot }));
    const removalTotals = new Map();
    for (const removal of removals) {
      if (!Number.isSafeInteger(removal.count) || removal.count <= 0) return null;
      removalTotals.set(removal.itemId, (removalTotals.get(removal.itemId) ?? 0) + removal.count);
    }
    for (const [itemId, count] of removalTotals) {
      let remaining = count;
      for (const slot of draft) {
        if (remaining <= 0) break;
        if (slot.itemId !== itemId) continue;
        const amount = Math.min(slot.count, remaining);
        slot.count -= amount;
        remaining -= amount;
      }
      if (remaining > 0) return null;
    }

    const compact = draft.filter((slot) => slot.count > 0);
    const additionTotals = new Map();
    for (const addition of additions) {
      if (!Number.isSafeInteger(addition.count) || addition.count <= 0) return null;
      additionTotals.set(addition.itemId, (additionTotals.get(addition.itemId) ?? 0) + addition.count);
    }
    for (const [itemId, count] of additionTotals) {
      const definition = this.definitions.get(itemId);
      if (!definition) return null;
      let remaining = count;
      for (const slot of compact) {
        if (remaining <= 0) break;
        if (slot.itemId !== itemId || slot.count >= definition.maxStack) continue;
        const amount = Math.min(definition.maxStack - slot.count, remaining);
        slot.count += amount;
        remaining -= amount;
      }
      while (remaining > 0 && compact.length < this.maxSlotsValue) {
        const amount = Math.min(definition.maxStack, remaining);
        compact.push({ itemId, count: amount });
        remaining -= amount;
      }
      if (remaining > 0) return null;
    }
    return compact;
  }
}

function recipe(id, ingredients, output, extra = {}) {
  return {
    id,
    name: id,
    description: `${id} recipe`,
    context: 'portable',
    tier: 1,
    ingredients,
    output,
    ...extra,
  };
}

function serviceFor({ definitions, slots, maxSlots, weapons = new Map() }) {
  const inventory = new FakeInventory(definitions, slots, maxSlots);
  const completed = [];
  const service = new CraftingService({
    inventory,
    getItem: (itemId) => definitions.get(itemId),
    getWeapon: (weaponId) => weapons.get(weaponId),
    emitCompleted: (payload) => completed.push(payload),
  });
  return { inventory, completed, service };
}

test('normalizes the same quantity rules used by the DOM adapter and service', () => {
  assert.equal(normalizeQuantity('', 4), 1);
  assert.equal(normalizeQuantity('-5', 4), 1);
  assert.equal(normalizeQuantity('1.5', 4), 1);
  assert.equal(normalizeQuantity('99', 4), 4);
  assert.equal(normalizeQuantity(Number.NaN, 4), 1);
  assert.equal(normalizeQuantity(Number.POSITIVE_INFINITY, 4), 1);
  assert.equal(normalizeQuantity('10', 0), 0);
});

test('quotes quantity output, aggregated requirements, and contextual weapon stats', () => {
  const definitions = new Map([
    ['wood', item('wood')],
    ['stone', item('stone')],
    ['blade', item('blade', 1, { category: 'weapon', equipment: { weaponId: 'blade' } })],
  ]);
  const weapons = new Map([['blade', {
    weaponId: 'blade',
    baseDamage: 24,
    cooldownMs: 800,
  }]]);
  const { service } = serviceFor({
    definitions,
    weapons,
    slots: [{ itemId: 'wood', count: 40 }, { itemId: 'stone', count: 20 }],
    maxSlots: 8,
  });
  const selected = recipe('blade-recipe', [
    { itemId: 'wood', count: 10 },
    { itemId: 'stone', count: 5 },
  ], { itemId: 'blade', count: 1 });

  const quote = service.quote(selected, 3);
  assert.equal(quote.status, 'ready');
  assert.equal(quote.maxCraftable, 4);
  assert.equal(quote.requestedQuantity, 3);
  assert.equal(quote.outputQuantity, 3);
  assert.deepEqual(quote.requirements.map((entry) => [entry.required, entry.available, entry.missing]), [[30, 40, 0], [15, 20, 0]]);
  assert.deepEqual(quote.stats, [{ label: 'Damage', value: '24' }, { label: 'Cooldown', value: '0.8s' }]);
});

test('limits unique output and reports missing-material precedence', () => {
  const definitions = new Map([
    ['wood', item('wood')],
    ['blade', item('blade', 1, { category: 'weapon', equipment: { weaponId: 'blade' } })],
  ]);
  const weapons = new Map([['blade', { weaponId: 'blade', baseDamage: 10, cooldownMs: 1000 }]]);
  const selected = recipe('unique-blade', [{ itemId: 'wood', count: 20 }], { itemId: 'blade', count: 1 }, { uniqueOutput: true });
  const owned = serviceFor({ definitions, weapons, slots: [{ itemId: 'wood', count: 99 }, { itemId: 'blade', count: 1 }] });
  assert.equal(owned.service.quote(selected, 1).status, 'unique-owned');

  const missing = serviceFor({ definitions, weapons, slots: [] });
  assert.equal(missing.service.quote(selected, 1).status, 'missing-materials');
});

test('accounts for output slot capacity and allows output matching an ingredient', () => {
  const definitions = new Map([
    ['wood', item('wood', 99)],
    ['potion', item('potion', 1, { category: 'consumable', use: { healHp: 40 } })],
  ]);
  const full = serviceFor({ definitions, slots: [{ itemId: 'wood', count: 10 }], maxSlots: 1 });
  const potionRecipe = recipe('potion', [{ itemId: 'wood', count: 5 }], { itemId: 'potion', count: 1 });
  const fullQuote = full.service.quote(potionRecipe, 1);
  assert.equal(fullQuote.maxCraftable, 0);
  assert.equal(fullQuote.status, 'inventory-full');

  const sameItem = serviceFor({ definitions, slots: [{ itemId: 'wood', count: 10 }], maxSlots: 1 });
  const sameRecipe = recipe('wood-return', [{ itemId: 'wood', count: 10 }], { itemId: 'wood', count: 5 });
  assert.equal(sameItem.service.quote(sameRecipe, 1).status, 'ready');
  assert.equal(sameItem.service.craft(sameRecipe, 1).ok, true);
  assert.equal(sameItem.inventory.count('wood'), 5);
});

test('crafts multiple units atomically and emits total output quantity', () => {
  const definitions = new Map([
    ['berry', item('berry')],
    ['tonic', item('tonic', 20, { category: 'consumable', use: { healHp: 40 } })],
  ]);
  const { service, inventory, completed } = serviceFor({
    definitions,
    slots: [{ itemId: 'berry', count: 10 }],
  });
  const selected = recipe('tonic', [{ itemId: 'berry', count: 2 }], { itemId: 'tonic', count: 2 });
  const result = service.craft(selected, 3);
  assert.equal(result.ok, true);
  assert.equal(result.outputQuantity, 6);
  assert.equal(inventory.count('berry'), 4);
  assert.equal(inventory.count('tonic'), 6);
  assert.deepEqual(completed, [{ recipeId: 'tonic', itemId: 'tonic', quantity: 6 }]);
});

test('failed craft does not mutate inventory or emit completion', () => {
  const definitions = new Map([
    ['berry', item('berry')],
    ['tonic', item('tonic', 20, { category: 'consumable', use: { healHp: 40 } })],
  ]);
  const { service, inventory, completed } = serviceFor({ definitions, slots: [{ itemId: 'berry', count: 1 }] });
  const selected = recipe('tonic', [{ itemId: 'berry', count: 2 }], { itemId: 'tonic', count: 1 });
  const result = service.craft(selected, 1);
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'missing-materials');
  assert.equal(inventory.count('berry'), 1);
  assert.equal(inventory.count('tonic'), 0);
  assert.equal(completed.length, 0);
});

test('maps tool harvest capabilities and consumable effects into stat lines', () => {
  const definitions = new Map([
    ['wood', item('wood')],
    ['axe', item('axe', 1, { category: 'weapon', equipment: { weaponId: 'axe' } })],
    ['tonic', item('tonic', 20, { category: 'consumable', use: { healHp: 40, healEnergy: 10 } })],
  ]);
  const weapons = new Map([['axe', {
    weaponId: 'axe',
    baseDamage: 12,
    cooldownMs: 1000,
    harvestCapabilities: { tree: 2 },
  }]]);
  const { service } = serviceFor({ definitions, weapons, slots: [{ itemId: 'wood', count: 99 }] });
  const axeQuote = service.quote(recipe('axe-recipe', [{ itemId: 'wood', count: 1 }], { itemId: 'axe', count: 1 }), 1);
  const tonicQuote = service.quote(recipe('tonic-recipe', [{ itemId: 'wood', count: 1 }], { itemId: 'tonic', count: 1 }), 1);
  assert.deepEqual(axeQuote.stats, [{ label: 'Harvest', value: 'tree: 2' }]);
  assert.deepEqual(tonicQuote.stats, [
    { label: 'Effect', value: '+40 HP' },
    { label: 'Effect', value: '+10 energy' },
  ]);
});

test('quest-learned recipes stay locked until the story grants them', () => {
  const definitions = new Map([['wood', item('wood')], ['spear', item('spear', 1)]]);
  const inventory = new FakeInventory(definitions, [{ itemId: 'wood', count: 20 }]);
  const learned = new Set();
  const service = new CraftingService({
    inventory,
    getItem: (itemId) => definitions.get(itemId),
    getWeapon: () => undefined,
    emitCompleted: () => {},
    isRecipeLearned: (recipeId) => learned.has(recipeId),
  });
  const locked = recipe('craft-spear', [{ itemId: 'wood', count: 10 }], { itemId: 'spear', count: 1 }, { learnedByQuest: true });
  const open = recipe('craft-open-spear', [{ itemId: 'wood', count: 10 }], { itemId: 'spear', count: 1 });

  assert.equal(service.quote(locked, 1).status, 'not-learned');
  assert.equal(service.craft(locked, 1).ok, false);
  assert.equal(inventory.count('wood'), 20);
  assert.equal(service.quote(open, 1).status, 'ready');

  learned.add('craft-spear');
  assert.equal(service.quote(locked, 1).status, 'ready');
  assert.equal(service.craft(locked, 1).ok, true);
});
