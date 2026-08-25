import assert from 'node:assert/strict';
import test from 'node:test';
import { isGameSaveData } from '../../../src/game/infrastructure/persistence/SaveSchema.ts';

function validSave() {
  return {
    player: {
      schemaVersion: 2,
      coins: 50,
      boostBonus: 0,
      totalFriends: 0,
      level: 1,
      xp: 0,
      hp: 100,
      maxHpBonus: 0,
      energy: 100,
      maxEnergyBonus: 0,
      skillPoints: 0,
      perks: {},
      attributes: { strength: 10, vitality: 10, agility: 10, intellect: 10 },
      equipment: { weaponId: 'goo-gauntlet', weaponSlots: ['goo-gauntlet', null, null, null, null, null] },
    },
    inventory: [{ itemId: 'goo-gauntlet', count: 1 }],
    quests: [{ id: 'first-steps', status: 'active', progress: { snacks: 0 } }],
    location: { areaId: 'level-1', mapId: 'level-1', x: 640, y: 704, facing: 'down' },
    world: {
      discoveredAreas: ['level-1'],
      defeatedBossIds: [],
      completedDungeonIds: [],
      maps: {
        'level-1': {
          resources: { 'level-1-tree-01': { stage: 'depleted', value: 0 } },
          completedEncounterIds: [],
          openedRewardIds: [],
          unlockedGateIds: [],
          objectStates: {},
        },
      },
    },
    playTimeMs: 1250,
  };
}

test('accepts a complete multi-map save contract', () => {
  assert.equal(isGameSaveData(validSave()), true);
});

test('rejects invalid player locations without weakening the rest of the contract', () => {
  const invalid = validSave();
  invalid.location.x = Number.NaN;
  assert.equal(isGameSaveData(invalid), false);
});

test('rejects flat or missing map runtime containers', () => {
  const invalid = validSave();
  delete invalid.world.maps['level-1'].resources;
  assert.equal(isGameSaveData(invalid), false);
});
