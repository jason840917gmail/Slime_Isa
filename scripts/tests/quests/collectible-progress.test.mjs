import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { createServer } from 'vite';

const contentRoot = path.resolve(process.cwd(), 'src/game/content');
const eventBusStubId = '\0quest-event-bus-stub';
const vite = await createServer({
  configFile: false,
  root: process.cwd(),
  appType: 'custom',
  plugins: [{
    name: 'quest-event-bus-stub',
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
      'virtual-animation-content': path.join(contentRoot, 'animations/virtual-animation-content.ts'),
    },
  },
  optimizeDeps: { noDiscovery: true },
  server: { middlewareMode: true, hmr: false },
});

const { collectibleProgressAmount } = await vite.ssrLoadModule('/src/game/quests/QuestCollectionProgress.ts');

test.after(async () => vite.close());

const berryEvent = (quantity) => ({
  mapId: 'level-1',
  instanceId: 'berry-01',
  objectId: 'collectible.purple-berry',
  itemId: 'purple-berry-mat',
  quantity,
});

test('collection objectives match item IDs and exact transferred quantities', () => {
  const snacks = {
    id: 'collect-test-berries',
    kind: 'collect',
    label: 'Collect test berries',
    target: 3,
    itemIds: ['purple-berry-mat'],
  };
  assert.equal(collectibleProgressAmount(snacks, berryEvent(2)), 2);
  assert.equal(collectibleProgressAmount(snacks, { ...berryEvent(10), itemId: 'wood' }), 0);
  assert.equal(collectibleProgressAmount(snacks, berryEvent(0)), 0);
});
