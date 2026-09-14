import assert from 'node:assert/strict';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { changedSceneOwnedMapRecords } = await loadTypescriptModule('src/game/content/scenes/legacyAuthoringAuthority.ts');

test('mixed legacy map saves may edit other records but not scene-owned camp or chest fields', () => {
  const persisted = {
    bossCamps: [{ id: 'managed-camp', respawnMs: 100 }, { id: 'legacy-camp', respawnMs: 200 }],
    objects: [{ instanceId: 'managed-chest', x: 10 }, { instanceId: 'legacy-tree', x: 20 }],
  };
  const allowed = structuredClone(persisted);
  allowed.bossCamps[1].respawnMs = 250;
  allowed.objects[1].x = 30;
  assert.deepEqual(changedSceneOwnedMapRecords(persisted, allowed, new Set(['managed-camp', 'managed-chest'])), []);

  const rejected = structuredClone(allowed);
  rejected.bossCamps[0].respawnMs = 101;
  rejected.objects.splice(0, 1);
  assert.deepEqual(
    changedSceneOwnedMapRecords(persisted, rejected, new Set(['managed-camp', 'managed-chest'])),
    ['managed-camp', 'managed-chest'],
  );
});
