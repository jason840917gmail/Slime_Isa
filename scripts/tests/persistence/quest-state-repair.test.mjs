import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { createServer } from 'vite';

const contentRoot = path.resolve(process.cwd(), 'src/game/content');
const vite = await createServer({
  configFile: false,
  root: process.cwd(),
  appType: 'custom',
  resolve: {
    alias: {
      'virtual-character-content': path.join(contentRoot, 'characters/virtual-character-content.ts'),
      'virtual-projectile-content': path.join(contentRoot, 'projectiles/virtual-projectile-content.ts'),
      'virtual-weapon-content': path.join(contentRoot, 'weapons/virtual-weapon-content.ts'),
      'virtual-effect-content': path.join(contentRoot, 'effects/virtual-effect-content.ts'),
    },
  },
  server: { middlewareMode: true },
});

const { repairQuestStates } = await vite.ssrLoadModule('/src/game/infrastructure/persistence/quests/QuestStateRepair.ts');
const { validateQuestState } = await vite.ssrLoadModule('/src/game/content/quests/validateQuestCatalog.ts');
const { getQuestDefinition } = await vite.ssrLoadModule('/src/game/content/quests/QuestCatalog.ts');

test.after(async () => {
  await vite.close();
});

const state = (overrides) => ({
  questId: 'a-place-to-work',
  definitionVersion: 1,
  status: 'active',
  activeStageId: 'build-workbench',
  progress: {},
  consumedFactIds: {},
  rewardsGranted: false,
  ...overrides,
});

test('quest states that fit the catalog pass through untouched', () => {
  const states = [state({ progress: { 'craft-workbench': 1 } })];
  const result = repairQuestStates(states);
  assert.deepEqual(result.repairs, []);
  assert.equal(result.states[0], states[0]);
});

test('stale quest progress from an older build is fitted instead of failing the whole load', () => {
  const result = repairQuestStates([
    state({ progress: { 'old-objective-id': 1, 'craft-workbench': 7 }, consumedFactIds: { 'old-objective-id': ['x'] } }),
    state({ questId: 'stone-tools', activeStageId: 'removed-stage', progress: { 'craft-axe': 1 } }),
    state({ questId: 'worm-trouble', definitionVersion: 1, status: 'completed', activeStageId: null, rewardsGranted: true, progress: { 'defeat-worms': 5 } }),
    state({ questId: 'a-quest-that-never-existed' }),
  ]);
  const [workbench, tools, worms] = result.states;
  assert.deepEqual(workbench.progress, { 'craft-workbench': 1 }, 'unknown objectives dropped, progress kept within its target');
  assert.deepEqual(workbench.consumedFactIds, {});
  assert.equal(tools.activeStageId, 'craft-tools', 'an unknown stage restarts the quest at its first stage');
  assert.deepEqual(tools.progress, {});
  assert.equal(worms.status, 'completed');
  assert.equal(worms.definitionVersion, 2, 'registered reconcilers still run');
  assert.equal(result.states.length, 3, 'a quest that no longer exists is dropped');
  assert.equal(result.repairs.length, 3);

  for (const repaired of result.states) {
    assert.deepEqual(validateQuestState(repaired, getQuestDefinition(repaired.questId)), [], `${repaired.questId} now loads`);
  }
});
