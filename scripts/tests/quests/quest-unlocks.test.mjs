import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { createServer } from 'vite';

const contentRoot = path.resolve(process.cwd(), 'src/game/content');
const eventBusStubId = '\0quest-unlocks-event-bus-stub';
const vite = await createServer({
  configFile: false,
  root: process.cwd(),
  appType: 'custom',
  plugins: [{
    name: 'quest-unlocks-event-bus-stub',
    enforce: 'pre',
    resolveId(source) {
      return /(^|\/)core\/EventBus$|^\.\/EventBus$/.test(source) ? eventBusStubId : undefined;
    },
    load(id) {
      return id === eventBusStubId ? 'export const gameEvents = { on() { return this; }, off() { return this; }, emit() { return this; } };' : undefined;
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

const { QuestService } = await vite.ssrLoadModule('/src/game/quests/QuestService.ts');
const { StoryProgress } = await vite.ssrLoadModule('/src/game/features/progression/StoryProgress.ts');
const { isGameSaveData } = await vite.ssrLoadModule('/src/game/infrastructure/persistence/SaveSchema.ts');
const { createInitialRunState } = await vite.ssrLoadModule('/src/game/content/initial-state/InitialRun.ts');
const { questRewardLines } = await vite.ssrLoadModule('/src/game/features/quests/QuestRewardText.ts');

test.after(async () => vite.close());

function quest(id, overrides = {}) {
  return {
    id, definitionVersion: 1, title: id, description: id, category: 'optional',
    prerequisites: [], acquisition: { kind: 'automatic' },
    stages: [{ id: 'only', title: 'Only', description: 'only', objectives: [{ id: 'place', kind: 'place-item', label: 'Place', target: 1, itemIds: ['workbench'] }] }],
    completion: { kind: 'automatic' }, failurePolicy: { kind: 'permanent' },
    abandonmentPolicy: { kind: 'retryable', reset: 'quest' }, rewards: {},
    ...overrides,
  };
}

function harness(catalog, flags = new Set()) {
  const granted = [];
  const service = new QuestService({
    catalog,
    events: { emit: () => {} },
    clock: { now: () => 1 },
    rewards: { grant: (questId, rewards) => granted.push({ questId, rewards }) },
    conditions: {
      playerLevel: () => 1, inventoryCount: () => 0, hasDiscoveredArea: () => false,
      hasWorldFlag: (flag) => flags.has(flag), hasTalkedToNpc: () => false,
    },
  });
  return { service, granted };
}

test('placing furniture advances place-item objectives once per placement', () => {
  const { service, granted } = harness([quest('bench', { stages: [{ id: 'only', title: 'Only', description: 'only', objectives: [{ id: 'place', kind: 'place-item', label: 'Place', target: 2, itemIds: ['workbench'] }] }] })]);
  service.start();
  const placed = { mapId: 'level-1', placementId: 'p1', itemId: 'workbench', sceneId: 's', x: 0, y: 0 };
  service.handleEvent('furniture.placed', placed);
  service.handleEvent('furniture.placed', placed);
  service.handleEvent('furniture.placed', { ...placed, itemId: 'bed', placementId: 'p2' });
  assert.equal(service.get('bench').progress.place, 1);
  service.handleEvent('furniture.placed', { ...placed, placementId: 'p3' });
  assert.equal(service.get('bench').status, 'completed');
  assert.equal(granted.length, 1);
});

test('recipe and flag rewards reach the reward port, and flags unlock follow-up quests', () => {
  const flags = new Set();
  const rewards = { recipeIds: ['craft-stone-axe'], flags: ['chapter-1-complete'] };
  const { service, granted } = harness([
    quest('first', { rewards }),
    quest('second', { prerequisites: [{ kind: 'world-flag', flagId: 'chapter-1-complete' }] }),
  ], flags);
  service.start();
  service.handleEvent('furniture.placed', { mapId: 'm', placementId: 'a', itemId: 'workbench', sceneId: 's', x: 0, y: 0 });
  assert.deepEqual(granted[0], { questId: 'first', rewards });
  assert.equal(service.get('second').status, 'locked');
  flags.add('chapter-1-complete');
  service.evaluatePrerequisites();
  assert.equal(service.get('second').status, 'active');
});

test('story progress round-trips learned recipes, flags, and talked NPCs', () => {
  const story = new StoryProgress();
  story.load(undefined);
  story.learnRecipes(['craft-stone-axe']);
  story.setFlags(['chapter-1-complete']);
  story.recordTalk('lili');
  const saved = story.serialize();
  const restored = new StoryProgress();
  restored.load(saved);
  assert.equal(restored.knowsRecipe('craft-stone-axe'), true);
  assert.equal(restored.knowsRecipe('craft-stone-spear'), false);
  assert.equal(restored.hasFlag('chapter-1-complete'), true);
  assert.equal(restored.hasTalkedTo('lili'), true);
});

test('saves accept an optional story block and reject a malformed one', () => {
  const base = createInitialRunState();
  assert.equal(isGameSaveData(base), true);
  assert.equal(isGameSaveData({ ...base, story: { worldFlags: [], learnedRecipeIds: ['x'], talkedNpcIds: [] } }), true);
  assert.equal(isGameSaveData({ ...base, story: { worldFlags: 'nope', learnedRecipeIds: [], talkedNpcIds: [] } }), false);
});

test('reward text lists items and learned recipes, not just coins and XP', () => {
  const lines = questRewardLines({ coins: 20, xp: 60, items: [{ itemId: 'wood', count: 10 }], recipeIds: ['craft-wooden-spear'] });
  assert.deepEqual(lines, ['20 coins', '60 XP', '10× Wood', 'New recipe: Wooden Spear']);
});
