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
      'virtual-animation-content': path.join(contentRoot, 'animations/virtual-animation-content.ts'),
    },
  },
  server: { middlewareMode: true },
});

const { SaveRepository, SaveRepositoryError } = await vite.ssrLoadModule(
  '/src/game/infrastructure/persistence/SaveRepository.ts',
);
const { STORAGE_KEYS } = await vite.ssrLoadModule(
  '/src/game/infrastructure/persistence/storageKeys.ts',
);
const { createInitialRunState } = await vite.ssrLoadModule(
  '/src/game/content/initial-state/InitialRun.ts',
);
const level1Map = (await vite.ssrLoadModule('/src/game/content/maps/level-1.map.json')).default;

test.after(async () => {
  await vite.close();
});

class MemoryStorage {
  values = new Map();
  failNextIndexWrite = false;

  getItem(key) {
    return this.values.get(key) ?? null;
  }

  setItem(key, value) {
    if (key === STORAGE_KEYS.saveIndex && this.failNextIndexWrite) {
      this.failNextIndexWrite = false;
      throw new Error('simulated index write failure');
    }
    this.values.set(key, value);
  }

  removeItem(key) {
    this.values.delete(key);
  }
}

function recordKey(saveId) {
  return `${STORAGE_KEYS.saveRecordPrefix}${saveId}`;
}

test('fresh initial runs do not share mutable state and use the authored Level 1 spawn', () => {
  const first = createInitialRunState();
  const second = createInitialRunState();

  first.player.equipment.weaponSlots[0] = 'changed-for-test';
  first.inventory.slots.push({ itemId: 'changed-for-test', count: 99 });
  first.world.discoveredAreas.push('changed-for-test');

  assert.notEqual(second.player.equipment.weaponSlots[0], 'changed-for-test');
  assert.deepEqual(second.player.equipment, {
    weaponId: null,
    weaponSlots: [null, null, null, null, null, null],
  });
  assert.deepEqual(second.inventory, { maxSlots: 24, slots: [] });
  assert.equal(second.world.discoveredAreas.includes('changed-for-test'), false);
  assert.deepEqual(second.location, {
    areaId: level1Map.mapId,
    mapId: level1Map.mapId,
    x: level1Map.player.spawn.x,
    y: level1Map.player.spawn.y,
    facing: 'down',
  });
});

test('overwriting stores metadata-only index entries', () => {
  const storage = new MemoryStorage();
  const repository = new SaveRepository(storage);
  const created = repository.create('Before Forest', createInitialRunState());
  const replacement = createInitialRunState();
  replacement.player.level = 3;

  repository.overwrite(created.saveId, replacement);

  const index = JSON.parse(storage.getItem(STORAGE_KEYS.saveIndex));
  assert.equal(index.saves.length, 1);
  assert.equal(index.saves[0].playerLevel, 3);
  assert.equal('data' in index.saves[0], false);
});

test('failed overwrite and delete index writes restore the existing snapshot', () => {
  const storage = new MemoryStorage();
  const repository = new SaveRepository(storage);
  const created = repository.create('Rollback Check', createInitialRunState());
  const key = recordKey(created.saveId);
  const originalRecord = storage.getItem(key);
  const replacement = createInitialRunState();
  replacement.player.level = 8;

  storage.failNextIndexWrite = true;
  assert.throws(
    () => repository.overwrite(created.saveId, replacement),
    (error) => error instanceof SaveRepositoryError,
  );
  assert.equal(storage.getItem(key), originalRecord);

  storage.failNextIndexWrite = true;
  assert.equal(repository.delete(created.saveId), false);
  assert.equal(storage.getItem(key), originalRecord);
  assert.equal(repository.list().length, 1);
});

test('corrupt indexed snapshots are isolated and reported', () => {
  const storage = new MemoryStorage();
  const repository = new SaveRepository(storage);
  const valid = repository.create('Valid Save', createInitialRunState());
  const corrupt = repository.create('Corrupt Save', createInitialRunState());
  storage.setItem(recordKey(corrupt.saveId), '{bad json');

  const records = repository.list();

  assert.deepEqual(records.map((record) => record.saveId), [valid.saveId]);
  assert.deepEqual(repository.validationIssues(), [
    { saveId: corrupt.saveId, reason: 'The snapshot contains invalid JSON.' },
  ]);
});

test('legacy flat resource progress migrates into its owning map', () => {
  const storage = new MemoryStorage();
  const repository = new SaveRepository(storage);
  const legacy = createInitialRunState();
  legacy.world = {
    discoveredAreas: ['level-1'],
    defeatedBossIds: [],
    completedDungeonIds: [],
    resourceStates: {
      'level-1:tree-01': { stage: 'depleted', value: 0 },
      'forest:stone-02': { stage: 'destroyed', value: 2 },
    },
  };
  storage.setItem(STORAGE_KEYS.legacySave, JSON.stringify({ savedAt: 123, data: legacy }));

  const migrated = repository.readLegacyEnvelope();

  assert.equal(migrated.savedAt, 123);
  assert.deepEqual(migrated.data.world.maps['level-1'].resources['tree-01'], { stage: 'depleted', value: 0 });
  assert.deepEqual(migrated.data.world.maps.forest.resources['stone-02'], { stage: 'destroyed', value: 2 });
});

test('unsupported legacy pile progress is ignored', () => {
  const storage = new MemoryStorage();
  const repository = new SaveRepository(storage);
  const legacy = createInitialRunState();
  legacy.world = {
    discoveredAreas: [],
    defeatedBossIds: [],
    completedDungeonIds: [],
    resourceStates: {
      'level-1:wood-pile-01': { stage: 'pile', value: 3 },
    },
  };
  storage.setItem(STORAGE_KEYS.legacySave, JSON.stringify({ savedAt: 123, data: legacy }));

  const migrated = repository.readLegacyEnvelope();

  assert.equal(migrated.data.world.maps['level-1'], undefined);
});

test('legacy inventory arrays migrate without dropping occupied slots', () => {
  const storage = new MemoryStorage();
  const repository = new SaveRepository(storage);
  const legacy = createInitialRunState();
  legacy.inventory = Array.from({ length: 26 }, (_, index) => ({ itemId: `legacy-${index}`, count: 1 }));
  storage.setItem(STORAGE_KEYS.legacySave, JSON.stringify({ schemaVersion: 5, savedAt: 123, data: legacy }));

  const migrated = repository.readLegacyEnvelope();

  assert.equal(migrated.data.inventory.maxSlots, 26);
  assert.equal(migrated.data.inventory.slots.length, 26);
});

test('version 5 named and recovery saves migrate inventory capacity', () => {
  const storage = new MemoryStorage();
  const repository = new SaveRepository(storage);
  const legacy = createInitialRunState();
  legacy.inventory = [{ itemId: 'wood', count: 4 }];
  legacy.player = {
    ...legacy.player,
    schemaVersion: 2,
    xp: 0,
    maxHpBonus: 0,
    maxEnergyBonus: 0,
  };
  delete legacy.player.currentXp;
  const metadata = {
    saveId: 'legacy-named', name: 'Legacy Named', createdAt: 10, updatedAt: 20,
    schemaVersion: 5, currentMapId: legacy.location.mapId,
    playerLevel: legacy.player.level, playTimeMs: legacy.playTimeMs,
  };
  storage.setItem(STORAGE_KEYS.saveIndex, JSON.stringify({ version: 1, saves: [metadata] }));
  storage.setItem(recordKey(metadata.saveId), JSON.stringify({ ...metadata, data: legacy }));
  storage.setItem(STORAGE_KEYS.recovery, JSON.stringify({ schemaVersion: 5, savedAt: 30, data: legacy }));

  const named = repository.read(metadata.saveId);
  const recovery = repository.readRecovery();

  assert.deepEqual(named.data.inventory, { maxSlots: 24, slots: [{ itemId: 'wood', count: 4 }] });
  assert.equal(named.schemaVersion, 7);
  assert.deepEqual(recovery.inventory, named.data.inventory);
  assert.deepEqual(repository.list().map((entry) => entry.saveId), [metadata.saveId]);
});

test('malformed legacy inventory rejects named and recovery saves without changing stored data', () => {
  const storage = new MemoryStorage();
  const repository = new SaveRepository(storage);
  const legacy = createInitialRunState();
  legacy.inventory = [
    { itemId: 'wood', count: 4 },
    { itemId: 'stone', count: 1.5 },
  ];
  const metadata = {
    saveId: 'malformed-inventory', name: 'Repair Me', createdAt: 10, updatedAt: 20,
    schemaVersion: 5, currentMapId: legacy.location.mapId,
    playerLevel: legacy.player.level, playTimeMs: legacy.playTimeMs,
  };
  const namedRaw = JSON.stringify({ ...metadata, data: legacy });
  const recoveryRaw = JSON.stringify({ schemaVersion: 5, savedAt: 30, data: legacy });
  storage.setItem(recordKey(metadata.saveId), namedRaw);
  storage.setItem(STORAGE_KEYS.recovery, recoveryRaw);

  assert.equal(repository.read(metadata.saveId), null);
  assert.equal(repository.readRecovery(), null);
  assert.equal(storage.getItem(recordKey(metadata.saveId)), namedRaw);
  assert.equal(storage.getItem(STORAGE_KEYS.recovery), recoveryRaw);
  assert.equal(repository.hasRecovery(), true);
  assert.deepEqual(repository.validationIssues(), [
    {
      saveId: metadata.saveId,
      reason: 'Inventory slot 2 was rejected: "count" must be a positive whole number. The original save was left unchanged.',
    },
    {
      reason: 'Inventory slot 2 was rejected: "count" must be a positive whole number. The original save was left unchanged.',
    },
  ]);
});

test('legacy cumulative XP preserves saved level and follows exact clamp rules', () => {
  const migrate = (level, xp) => {
    const storage = new MemoryStorage();
    const repository = new SaveRepository(storage);
    const legacy = createInitialRunState();
    legacy.player = { ...legacy.player, schemaVersion: 2, level, xp, maxHpBonus: 999, maxEnergyBonus: 999 };
    delete legacy.player.currentXp;
    storage.setItem(STORAGE_KEYS.legacySave, JSON.stringify({ schemaVersion: 6, savedAt: 1, data: legacy }));
    return repository.readLegacyEnvelope()?.data.player;
  };

  assert.equal(migrate(3, 80 + 226 + 17).currentXp, 17);
  assert.equal(migrate(3, 1).currentXp, 0);
  assert.equal(migrate(3, 999_999).currentXp, 415);
  assert.equal(migrate(10, 999_999).currentXp, 0);
  assert.equal(migrate(11, 0), undefined);
  assert.equal('maxHpBonus' in migrate(2, 80), false);
  assert.equal('maxEnergyBonus' in migrate(2, 80), false);
});
