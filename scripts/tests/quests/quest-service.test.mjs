import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { createServer } from 'vite';

const contentRoot = path.resolve(process.cwd(), 'src/game/content');
const eventBusStubId = '\0quest-service-event-bus-stub';
const vite = await createServer({
  configFile: false,
  root: process.cwd(),
  appType: 'custom',
  plugins: [{
    name: 'quest-service-event-bus-stub',
    enforce: 'pre',
    resolveId(source) {
      if (source === '../core/EventBus' || source === './EventBus') return eventBusStubId;
      return undefined;
    },
    load(id) {
      if (id !== eventBusStubId) return undefined;
      return `
        const listeners = new Map();
        export const gameEvents = {
          on(event, fn, context) {
            const handlers = listeners.get(event) ?? [];
            handlers.push({ fn, context });
            listeners.set(event, handlers);
            return this;
          },
          off(event, fn, context) {
            const handlers = listeners.get(event) ?? [];
            listeners.set(event, handlers.filter((handler) => handler.fn !== fn || handler.context !== context));
            return this;
          },
          emit(event, payload) {
            for (const handler of listeners.get(event) ?? []) handler.fn.call(handler.context, payload);
            return this;
          },
        };
      `;
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
const { createInitialQuestState, getQuestDefinitions } = await vite.ssrLoadModule('/src/game/content/quests/QuestCatalog.ts');
const { CollectibleController } = await vite.ssrLoadModule('/src/game/features/collectibles/CollectibleController.ts');

test.after(async () => vite.close());

test('new quest save states stay locked until the service emits their lifecycle transition', () => {
  const definition = {
    id: 'initial-demo', definitionVersion: 1, title: 'Initial Demo', description: 'demo', category: 'optional',
    prerequisites: [], acquisition: { kind: 'automatic' },
    stages: [{ id: 'finish', title: 'Finish', description: 'finish', objectives: [{ id: 'item', kind: 'collect', label: 'item', target: 1, itemIds: ['berry'] }] }],
    completion: { kind: 'automatic' }, failurePolicy: { kind: 'permanent' },
    abandonmentPolicy: { kind: 'retryable', reset: 'quest' }, rewards: {},
  };
  assert.deepEqual(createInitialQuestState(definition), {
    questId: 'initial-demo', definitionVersion: 1, status: 'locked', activeStageId: null,
    progress: {}, rewardsGranted: false,
  });

  const deps = dependencies();
  const service = new QuestService({ catalog: [definition], ...deps });
  service.load([createInitialQuestState(definition)]);
  service.start();
  assert.equal(service.get('initial-demo').status, 'active');
  assert.ok(deps.eventsLog.some((entry) => entry.event === 'quest.accepted' && entry.payload.questId === 'initial-demo'));
});

function dependencies() {
  const events = [];
  return {
    events: { emit: (event, payload) => events.push({ event, payload }) },
    rewards: { grant: () => {} },
    clock: { now: () => 1234 },
    conditions: {
      inventoryCount: () => 0,
      hasDiscoveredArea: () => false,
      hasWorldFlag: () => false,
      hasTalkedToNpc: () => false,
    },
    eventsLog: events,
  };
}

test('chapter 1 plays through from the workbench to Gloop Forest, each quest opening the next', () => {
  const deps = dependencies();
  const service = new QuestService({ catalog: getQuestDefinitions(), ...deps });
  service.start();
  assert.equal(service.get('a-place-to-work').status, 'locked');

  service.handleEvent('area.enter', { areaId: 'level-1' });
  assert.equal(service.get('a-place-to-work').status, 'available');
  assert.equal(service.get('slime-basics').status, 'active', 'the tutorial starts by itself beside the first quest');
  assert.equal(service.offersForNpc('village-elder-plop')[0].quest.questId, 'a-place-to-work');
  assert.equal(service.accept('a-place-to-work', 'village-elder-plop').ok, true);

  const craft = (itemId) => service.handleEvent('craft.completed', { recipeId: `craft-${itemId}`, itemId, quantity: 1 });
  const collect = (itemId, quantity) => service.handleEvent('collectible.collected', { mapId: 'level-1', instanceId: `${itemId}-${quantity}`, objectId: 'x', itemId, quantity });
  const turnIn = (questId, npcId) => assert.equal(service.turnIn(questId, npcId).ok, true, `${questId} turn-in`);

  craft('workbench');
  service.handleEvent('furniture.placed', { mapId: 'level-1', placementId: 'bench-1', itemId: 'workbench', sceneId: 'object.interior-workshop-workbench', x: 0, y: 0 });
  turnIn('a-place-to-work', 'village-elder-plop');
  assert.equal(service.get('stone-tools').status, 'available');
  assert.equal(service.get('a-tonic-for-lili').status, 'available');

  service.accept('stone-tools', 'village-elder-plop');
  craft('stone-axe');
  craft('stone-pickaxe');
  collect('wood', 20);
  collect('stone', 20);
  assert.equal(service.get('stone-tools').readyToTurnIn, false, 'the tools must be switched on the belt');
  service.handleEvent('control.used', { controlId: 'weapon-switch' });
  turnIn('stone-tools', 'village-elder-plop');

  for (const controlId of ['menu:inventory', 'menu:crafting', 'menu:journal', 'menu:map', 'sprint']) service.handleEvent('control.used', { controlId });
  assert.equal(service.get('slime-basics').status, 'active');
  service.handleEvent('control.used', { controlId: 'pause' });
  assert.equal(service.get('slime-basics').status, 'completed', 'every menu, a sprint and the pause menu finish the basics');

  service.accept('worm-trouble', 'level-1-spider-giver');
  craft('wooden-spear');
  service.handleEvent('enemy.died', { enemyId: 99, areaId: 'level-1', kind: 'worm-brawler' });
  assert.equal(service.get('worm-trouble').progress['defeat-worms'] ?? 0, 0, 'brawlers no longer count');
  for (let enemyId = 0; enemyId < 3; enemyId += 1) service.handleEvent('enemy.died', { enemyId, areaId: 'level-1', kind: 'worm-swordsman' });
  assert.equal(service.get('worm-trouble').readyToTurnIn, true, 'three swordsmen clear the camp');
  turnIn('worm-trouble', 'level-1-spider-giver');

  service.accept('the-one-eyed-guardian', 'village-elder-plop');
  craft('stone-spear');
  service.handleEvent('boss.defeated', { bossId: 'fatty-one-eye' });
  service.handleEvent('area.enter', { areaId: 'gloop-forest' });
  assert.equal(service.get('the-one-eyed-guardian').status, 'completed');
});

test('saves holding the retired starter quest still load and receive chapter 1', () => {
  const service = new QuestService({ catalog: getQuestDefinitions(), ...dependencies() });
  service.load([{ questId: 'gather-building-materials', definitionVersion: 1, status: 'active', activeStageId: 'gather-materials', progress: { 'collect-wood': 12 }, rewardsGranted: false }]);
  service.restoreKnownFacts({ discoveredAreas: ['level-1'] });
  service.start();
  assert.equal(service.get('gather-building-materials'), undefined);
  assert.equal(service.get('a-place-to-work').status, 'available');
});

test('objectives in one stage progress in parallel and later stages stay hidden', () => {
  const deps = dependencies();
  const service = new QuestService({
    catalog: [{
      id: 'stage-demo', definitionVersion: 1, title: 'Stage Demo', description: 'demo', category: 'mandatory',
      prerequisites: [], acquisition: { kind: 'automatic' },
      stages: [
        { id: 'supplies', title: 'Supplies', description: 'both', objectives: [
          { id: 'berries', kind: 'collect', label: 'berries', target: 1, itemIds: ['berry'] },
          { id: 'wood', kind: 'collect', label: 'wood', target: 1, itemIds: ['wood'] },
        ] },
        { id: 'report', title: 'Report', description: 'later', objectives: [
          { id: 'talk', kind: 'talk-to-npc', label: 'talk', target: 1, npcIds: ['elder'] },
        ] },
      ],
      completion: { kind: 'automatic' }, failurePolicy: { kind: 'permanent' },
      abandonmentPolicy: { kind: 'forbidden' }, rewards: {},
    }],
    ...deps,
  });
  service.start();
  service.handleEvent('collectible.collected', { mapId: 'm', instanceId: 'b', objectId: 'o', itemId: 'berry', quantity: 1 });
  assert.equal(service.get('stage-demo').activeStageId, 'supplies');
  assert.deepEqual(service.get('stage-demo').visibleStages.map((stage) => stage.id), ['supplies']);
  assert.equal(service.get('stage-demo').progress.berries, 1);
  service.handleEvent('npc.talked', { npcId: 'elder' });
  assert.equal(service.get('stage-demo').progress.talk ?? 0, 0);
  service.handleEvent('collectible.collected', { mapId: 'm', instanceId: 'w', objectId: 'o', itemId: 'wood', quantity: 1 });
  assert.equal(service.get('stage-demo').activeStageId, 'report');
  assert.deepEqual(service.get('stage-demo').visibleStages.map((stage) => stage.id), ['supplies', 'report']);
  service.handleEvent('npc.talked', { npcId: 'elder' });
  assert.equal(service.get('stage-demo').status, 'completed');
});

test('quest prerequisites activate later quests without a sequence entity', () => {
  const deps = dependencies();
  const service = new QuestService({
    catalog: [
      {
        id: 'quest-a', definitionVersion: 1, title: 'A', description: 'a', category: 'mandatory',
        prerequisites: [], acquisition: { kind: 'automatic' },
        stages: [{ id: 'finish', title: 'Finish', description: 'a', objectives: [{ id: 'a', kind: 'collect', label: 'a', target: 1, itemIds: ['berry'] }] }],
        completion: { kind: 'automatic' }, failurePolicy: { kind: 'permanent' }, abandonmentPolicy: { kind: 'forbidden' }, rewards: {},
      },
      {
        id: 'quest-b', definitionVersion: 1, title: 'B', description: 'b', category: 'optional',
        prerequisites: [{ kind: 'quest-status', questId: 'quest-a', status: 'completed' }],
        acquisition: { kind: 'automatic' },
        stages: [{ id: 'finish', title: 'Finish', description: 'b', objectives: [{ id: 'b', kind: 'collect', label: 'b', target: 1, itemIds: ['wood'] }] }],
        completion: { kind: 'automatic' }, failurePolicy: { kind: 'permanent' }, abandonmentPolicy: { kind: 'retryable', reset: 'quest' }, rewards: {},
      },
    ],
    ...deps,
  });
  service.start();
  assert.equal(service.get('quest-a').status, 'active');
  assert.equal(service.get('quest-b').status, 'locked');
  service.handleEvent('collectible.collected', { mapId: 'm', instanceId: 'b', objectId: 'o', itemId: 'berry', quantity: 1 });
  assert.equal(service.get('quest-a').status, 'completed');
  assert.equal(service.get('quest-b').status, 'active');
  assert.ok(deps.eventsLog.some((entry) => entry.event === 'quest.accepted' && entry.payload.questId === 'quest-b'));
});

test('fact-backed objectives count each fact once across repeated events', () => {
  const deps = dependencies();
  const service = new QuestService({
    catalog: [{
      id: 'boss-demo', definitionVersion: 1, title: 'Boss Demo', description: 'demo', category: 'optional',
      prerequisites: [], acquisition: { kind: 'automatic' },
      stages: [{ id: 'bosses', title: 'Bosses', description: 'demo', objectives: [{ id: 'bosses', kind: 'defeat-boss', label: 'bosses', target: 2, bossIds: ['one', 'two'] }] }],
      completion: { kind: 'automatic' }, failurePolicy: { kind: 'permanent' }, abandonmentPolicy: { kind: 'retryable', reset: 'quest' }, rewards: {},
    }],
    ...deps,
  });
  service.start();
  service.handleEvent('boss.defeated', { bossId: 'one' });
  service.handleEvent('boss.defeated', { bossId: 'one' });
  assert.equal(service.get('boss-demo').progress.bosses, 1);
  service.handleEvent('boss.defeated', { bossId: 'two' });
  assert.equal(service.get('boss-demo').status, 'completed');
  assert.deepEqual(service.serialize()[0].consumedFactIds.bosses, ['one', 'two']);
});

test('NPC offers require acceptance and retryable failures reset only the authored scope', () => {
  const deps = dependencies();
  const service = new QuestService({
    catalog: [{
      id: 'retry-demo', definitionVersion: 1, title: 'Retry Demo', description: 'demo', category: 'optional',
      prerequisites: [], acquisition: { kind: 'npc', npcIds: ['elder'] },
      stages: [
        { id: 'one', title: 'One', description: 'one', objectives: [{ id: 'first', kind: 'collect', label: 'first', target: 1, itemIds: ['berry'] }] },
        { id: 'two', title: 'Two', description: 'two', objectives: [{ id: 'second', kind: 'collect', label: 'second', target: 2, itemIds: ['wood'] }] },
      ],
      completion: { kind: 'automatic' }, failurePolicy: { kind: 'retryable', reset: 'current-stage' },
      abandonmentPolicy: { kind: 'retryable', reset: 'current-stage' }, rewards: {},
    }],
    ...deps,
  });
  service.start();
  assert.equal(service.get('retry-demo').status, 'available');
  service.decline('retry-demo', 'elder');
  assert.equal(service.get('retry-demo').status, 'available');
  service.accept('retry-demo', 'elder');
  service.handleEvent('collectible.collected', { mapId: 'm', instanceId: 'b', objectId: 'o', itemId: 'berry', quantity: 1 });
  service.handleEvent('collectible.collected', { mapId: 'm', instanceId: 'w', objectId: 'o', itemId: 'wood', quantity: 1 });
  assert.equal(service.get('retry-demo').progress.first, 1);
  assert.equal(service.get('retry-demo').progress.second, 1);
  service.fail('retry-demo', 'timeout');
  service.retryFailed('retry-demo');
  assert.equal(service.get('retry-demo').status, 'active');
  assert.equal(service.get('retry-demo').activeStageId, 'two');
  assert.equal(service.get('retry-demo').progress.first, 1);
  assert.equal(service.get('retry-demo').progress.second ?? 0, 0);
});

test('completion grants rewards exactly once and rejects mandatory abandonment', () => {
  const deps = dependencies();
  let grants = 0;
  const service = new QuestService({
    catalog: [{
      id: 'reward-demo', definitionVersion: 1, title: 'Reward Demo', description: 'demo', category: 'mandatory',
      prerequisites: [], acquisition: { kind: 'automatic' },
      stages: [{ id: 'finish', title: 'Finish', description: 'finish', objectives: [{ id: 'done', kind: 'collect', label: 'done', target: 1, itemIds: ['berry'] }] }],
      completion: { kind: 'automatic' }, failurePolicy: { kind: 'permanent' }, abandonmentPolicy: { kind: 'forbidden' }, rewards: { coins: 10 },
    }],
    ...deps,
    rewards: { grant: () => { grants += 1; } },
  });
  service.start();
  assert.equal(service.abandon('reward-demo').ok, false);
  service.handleEvent('collectible.collected', { mapId: 'm', instanceId: 'b', objectId: 'o', itemId: 'berry', quantity: 1 });
  service.handleEvent('collectible.collected', { mapId: 'm', instanceId: 'b', objectId: 'o', itemId: 'berry', quantity: 1 });
  assert.equal(service.get('reward-demo').status, 'completed');
  assert.equal(grants, 1);
});

test('a finished NPC turn-in stage emits stage completion only once', () => {
  const deps = dependencies();
  const service = new QuestService({
    catalog: [{
      id: 'turn-in-demo', definitionVersion: 1, title: 'Turn In Demo', description: 'demo', category: 'optional',
      prerequisites: [], acquisition: { kind: 'automatic' },
      stages: [{ id: 'finish', title: 'Finish', description: 'finish', objectives: [{ id: 'item', kind: 'collect', label: 'item', target: 1, itemIds: ['berry'] }] }],
      completion: { kind: 'npc-turn-in', npcIds: ['elder'] }, failurePolicy: { kind: 'permanent' },
      abandonmentPolicy: { kind: 'retryable', reset: 'quest' }, rewards: {},
    }],
    ...deps,
  });
  service.start();
  service.handleEvent('collectible.collected', { mapId: 'm', instanceId: 'b', objectId: 'o', itemId: 'berry', quantity: 1 });
  service.handleEvent('area.enter', { areaId: 'elsewhere' });
  service.handleEvent('collectible.collected', { mapId: 'm', instanceId: 'b2', objectId: 'o', itemId: 'berry', quantity: 1 });

  const stageEvents = deps.eventsLog.filter((entry) => entry.event === 'quest.stage-completed');
  assert.equal(stageEvents.length, 1);
  assert.equal(service.get('turn-in-demo').readyToTurnIn, true);
  assert.equal(service.turnIn('turn-in-demo', 'elder').ok, true);
  assert.equal(service.get('turn-in-demo').status, 'completed');
});

test('abandoned quests expose working NPC and automatic recovery paths', () => {
  const deps = dependencies();
  const service = new QuestService({
    catalog: [
      {
        id: 'npc-recovery', definitionVersion: 1, title: 'NPC Recovery', description: 'demo', category: 'optional',
        prerequisites: [], acquisition: { kind: 'npc', npcIds: ['elder'] },
        stages: [{ id: 'finish', title: 'Finish', description: 'finish', objectives: [{ id: 'item', kind: 'collect', label: 'item', target: 1, itemIds: ['berry'] }] }],
        completion: { kind: 'automatic' }, failurePolicy: { kind: 'permanent' },
        abandonmentPolicy: { kind: 'retryable', reset: 'quest' }, rewards: {},
      },
      {
        id: 'automatic-recovery', definitionVersion: 1, title: 'Automatic Recovery', description: 'demo', category: 'optional',
        prerequisites: [], acquisition: { kind: 'automatic' },
        stages: [{ id: 'finish', title: 'Finish', description: 'finish', objectives: [{ id: 'item', kind: 'collect', label: 'item', target: 1, itemIds: ['wood'] }] }],
        completion: { kind: 'automatic' }, failurePolicy: { kind: 'permanent' },
        abandonmentPolicy: { kind: 'retryable', reset: 'quest' }, rewards: {},
      },
    ],
    ...deps,
  });
  service.start();

  service.accept('npc-recovery', 'elder');
  service.abandon('npc-recovery');
  assert.deepEqual(service.reoffersForNpc('elder').map((offer) => offer.quest.questId), ['npc-recovery']);
  assert.equal(service.reoffer('npc-recovery', 'elder').ok, true);
  assert.equal(service.get('npc-recovery').status, 'available');
  assert.equal(service.accept('npc-recovery', 'elder').ok, true);
  assert.equal(service.get('npc-recovery').status, 'active');

  service.abandon('automatic-recovery');
  assert.equal(service.retryAbandonedAutomatic('automatic-recovery').ok, true);
  assert.equal(service.get('automatic-recovery').status, 'active');
});

test('load rejects reward flags that contradict quest status', () => {
  const deps = dependencies();
  const service = new QuestService({
    catalog: [{
      id: 'load-demo', definitionVersion: 1, title: 'Load Demo', description: 'demo', category: 'optional',
      prerequisites: [], acquisition: { kind: 'automatic' },
      stages: [{ id: 'finish', title: 'Finish', description: 'finish', objectives: [{ id: 'item', kind: 'collect', label: 'item', target: 1, itemIds: ['berry'] }] }],
      completion: { kind: 'automatic' }, failurePolicy: { kind: 'permanent' },
      abandonmentPolicy: { kind: 'retryable', reset: 'quest' }, rewards: {},
    }],
    ...deps,
  });

  assert.throws(() => service.load([{
    questId: 'load-demo', definitionVersion: 1, status: 'active', activeStageId: 'finish',
    progress: { item: 0 }, rewardsGranted: true,
  }]), /rewardsGranted/);
});

test('the real collectible controller advances a quest exactly once per transferred quantity', () => {
  const deps = dependencies();
  const service = new QuestService({
    catalog: [{
      id: 'controller-bridge', definitionVersion: 1, title: 'Controller Bridge', description: 'demo', category: 'optional',
      prerequisites: [], acquisition: { kind: 'automatic' },
      stages: [{ id: 'finish', title: 'Finish', description: 'finish', objectives: [{ id: 'wood', kind: 'collect', label: 'wood', target: 10, itemIds: ['wood'] }] }],
      completion: { kind: 'automatic' }, failurePolicy: { kind: 'permanent' },
      abandonmentPolicy: { kind: 'retryable', reset: 'quest' }, rewards: {},
    }],
    ...deps,
  });
  service.start();

  let collectibleState;
  const controller = new CollectibleController({
    scene: { time: { now: 10_000 } },
    mapId: 'level-1',
    transaction: {
      collectWorldItem({ remaining, requested }) {
        const moved = Math.min(remaining, requested);
        collectibleState = { remaining: remaining - moved };
        return moved;
      },
    },
    progress: { collectibleState: () => collectibleState },
    publisher: { publishCollected: (payload) => service.handleEvent('collectible.collected', payload) },
    showMessage: () => {},
  });
  controller.ensureInitialized('level-1', 'wood-01', 10);
  const pickup = {
    mapId: 'level-1', instanceId: 'wood-01', objectId: 'collectible.wood-pile', itemId: 'wood',
    requested: 10, collectorAreaNodeId: 'managed-player/PickupArea', x: 100, y: 100,
  };

  controller.pickup(pickup);
  controller.pickup(pickup);

  assert.equal(service.get('controller-bridge').status, 'completed');
  assert.equal(service.get('controller-bridge').progress.wood, 10);
  assert.equal(deps.eventsLog.filter((entry) => entry.event === 'quest.progressed').length, 1);
});

test('saves from before Worm Trouble v2 keep their progress within the new target', () => {
  const service = new QuestService({ catalog: getQuestDefinitions(), ...dependencies() });
  const states = getQuestDefinitions().map((definition) => ({ questId: definition.id, definitionVersion: definition.definitionVersion, status: 'locked', activeStageId: null, progress: {}, rewardsGranted: false }));
  const index = states.findIndex((state) => state.questId === 'worm-trouble');
  states[index] = { questId: 'worm-trouble', definitionVersion: 1, status: 'active', activeStageId: 'clear-camp', progress: { 'craft-wooden-spear': 1, 'defeat-worms': 4 }, rewardsGranted: false };
  service.load(states);
  const quest = service.get('worm-trouble');
  assert.equal(quest.definitionVersion, 2);
  assert.equal(quest.progress['defeat-worms'], 3);
  assert.equal(quest.readyToTurnIn, true);
});
