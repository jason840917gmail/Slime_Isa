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
      return id === eventBusStubId ? 'export const emitted = []; export const gameEvents = { on() { return this; }, off() { return this; }, emit(event, payload) { emitted.push({ event, payload }); return this; } };' : undefined;
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

const { QuestService, bindQuestStory } = await vite.ssrLoadModule('/src/game/quests/QuestService.ts');
const { getQuestDefinitions } = await vite.ssrLoadModule('/src/game/content/quests/QuestCatalog.ts');
const { validateQuestCatalog } = await vite.ssrLoadModule('/src/game/content/quests/validateQuestCatalog.ts');
const { emitted } = await vite.ssrLoadModule(eventBusStubId);
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
      inventoryCount: () => 0, hasDiscoveredArea: () => false,
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

test('ability rewards teach the slime through the story, announced once', () => {
  const story = new StoryProgress();
  story.load(undefined);
  bindQuestStory({
    hasDiscoveredArea: () => false, hasWorldFlag: (flagId) => story.hasFlag(flagId), hasTalkedToNpc: () => false,
    learnRecipes: (recipeIds) => story.learnRecipes(recipeIds),
    learnAbilities: (abilityIds) => story.learnAbilities(abilityIds),
    setFlags: (flagIds) => story.setFlags(flagIds),
  });
  const service = new QuestService({
    catalog: [quest('teach-jump', { rewards: { abilityIds: ['jump'] } })],
    events: { emit: () => {} },
    clock: { now: () => 1 },
    conditions: { inventoryCount: () => 0, hasDiscoveredArea: () => false, hasWorldFlag: () => false, hasTalkedToNpc: () => false },
  });
  service.start();
  const start = emitted.length;
  assert.equal(story.knowsAbility('jump'), false);
  service.handleEvent('furniture.placed', { mapId: 'm', placementId: 'a', itemId: 'workbench', sceneId: 's', x: 0, y: 0 });
  assert.equal(service.get('teach-jump').status, 'completed');
  assert.equal(story.knowsAbility('jump'), true);
  story.learnAbilities(['jump']);
  assert.deepEqual(emitted.slice(start).filter((entry) => entry.event === 'ability.learned').map((entry) => entry.payload), [{ abilityId: 'jump' }]);

  const restored = new StoryProgress();
  restored.load(story.serialize());
  assert.equal(restored.knowsAbility('jump'), true, 'a learned ability survives save and load');
  const older = new StoryProgress();
  older.load({ worldFlags: [], learnedRecipeIds: [], talkedNpcIds: [] });
  assert.equal(older.knowsAbility('jump'), false, 'stories saved before abilities load with none learned');
});

test('Chapter 1 teaches Jump from Worm Trouble and rewards no XP', () => {
  const quests = getQuestDefinitions();
  assert.deepEqual(quests.find((entry) => entry.id === 'worm-trouble').rewards.abilityIds, ['jump']);
  assert.equal(quests.some((entry) => 'xp' in entry.rewards), false);
  assert.throws(() => validateQuestCatalog([quest('bad-ability', { rewards: { abilityIds: ['fly'] } })]), /unknown ability 'fly'/);
  assert.throws(() => validateQuestCatalog([quest('old-xp', { rewards: { xp: 10 } })]), /XP was retired/);
});

test('saves accept an optional story block and reject a malformed one', () => {
  const base = createInitialRunState();
  assert.equal(isGameSaveData(base), true);
  assert.equal(isGameSaveData({ ...base, story: { worldFlags: [], learnedRecipeIds: ['x'], talkedNpcIds: [] } }), true);
  assert.equal(isGameSaveData({ ...base, story: { worldFlags: 'nope', learnedRecipeIds: [], talkedNpcIds: [] } }), false);
  assert.equal(isGameSaveData({ ...base, story: { worldFlags: [], learnedRecipeIds: [], learnedAbilityIds: ['jump'], talkedNpcIds: [] } }), true);
  assert.equal(isGameSaveData({ ...base, story: { worldFlags: [], learnedRecipeIds: [], learnedAbilityIds: 'jump', talkedNpcIds: [] } }), false);
});

test('reward text lists items, learned recipes and learned abilities', () => {
  const lines = questRewardLines({ coins: 20, items: [{ itemId: 'wood', count: 10 }], recipeIds: ['craft-wooden-spear'], abilityIds: ['jump'] });
  assert.deepEqual(lines, ['20 coins', '10× Wood', 'New recipe: Wooden Spear', 'New ability: Jump']);
});
