import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { resolveQuestWaypoint } = await loadTypescriptModule('src/game/features/quests/QuestWaypoint.ts');
const { theOldWorkshop } = await loadTypescriptModule('src/game/content/quests/quests/chapterOne.ts');

const nowhere = {
  npcPosition: () => undefined,
  bossCampPosition: () => undefined,
  spawnAreaFor: () => undefined,
  exitToArea: () => undefined,
  nearestSource: () => undefined,
  nearestStation: () => undefined,
  restorationSite: () => undefined,
};

const view = (status, progress = {}) => ({
  questId: theOldWorkshop.id,
  definitionVersion: theOldWorkshop.definitionVersion,
  status,
  activeStageId: status === 'active' ? 'restore-workshop' : null,
  progress,
  rewardsGranted: false,
  definition: theOldWorkshop,
  visibleStages: theOldWorkshop.stages,
  readyToTurnIn: false,
});

test('The Old Workshop points at Elder Plop, then at the ruin, and nowhere once it stands', () => {
  const from = { x: 0, y: 0 };
  const world = {
    ...nowhere,
    npcPosition: (npcId) => (npcId === 'village-elder-plop' ? { x: 500, y: 700 } : undefined),
    restorationSite: (objectIds) => (objectIds.includes('workshop') ? { x: 640, y: 392 } : undefined),
  };
  assert.deepEqual(resolveQuestWaypoint(view('available'), world, from), { x: 500, y: 700, label: 'Talk to Village Elder Plop' });
  assert.deepEqual(resolveQuestWaypoint(view('active', { 'restore-workshop': 0 }), world, from), { x: 640, y: 392, label: 'Restore the Workshop (60 wood, 40 stone)' });
  // Restored: the site is gone from the map, so there is no arrow left to show.
  assert.equal(resolveQuestWaypoint(view('active', { 'restore-workshop': 0 }), { ...world, restorationSite: () => undefined }, from), undefined);
  assert.equal(resolveQuestWaypoint(view('completed', { 'restore-workshop': 1 }), world, from), undefined);
});
