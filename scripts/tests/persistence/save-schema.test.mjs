import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'vite';

const vite = await createServer({
  configFile: false,
  root: process.cwd(),
  appType: 'custom',
  optimizeDeps: { noDiscovery: true },
  server: { middlewareMode: true, hmr: false },
});
const { isGameSaveData } = await vite.ssrLoadModule('/src/game/infrastructure/persistence/SaveSchema.ts');
test.after(async () => vite.close());

function validSave() {
  return {
    player: {
      schemaVersion: 3,
      coins: 50,
      boostBonus: 0,
      totalFriends: 0,
      level: 1,
      currentXp: 0,
      hp: 100,
      energy: 100,
      skillPoints: 0,
      perks: {},
      attributes: { strength: 10, vitality: 10, agility: 10, intellect: 10 },
      equipment: { weaponId: null, weaponSlots: [null, null, null, null, null, null] },
    },
    inventory: { maxSlots: 24, slots: [] },
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

test('accepts both an empty equipped state and legacy equipped weapons', () => {
  const empty = validSave();
  assert.equal(isGameSaveData(empty), true);

  const legacy = validSave();
  legacy.player.equipment.weaponId = 'goo-gauntlet';
  legacy.player.equipment.weaponSlots[0] = 'goo-gauntlet';
  legacy.inventory.slots.push({ itemId: 'goo-gauntlet', count: 1 });
  assert.equal(isGameSaveData(legacy), true);
});

test('rejects invalid inventory capacity', () => {
  const invalid = validSave();
  invalid.inventory = { maxSlots: 1, slots: [{ itemId: 'wood', count: 1 }, { itemId: 'stone', count: 1 }] };
  assert.equal(isGameSaveData(invalid), false);
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
