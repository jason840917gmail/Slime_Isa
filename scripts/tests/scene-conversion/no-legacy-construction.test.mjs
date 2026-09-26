import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { auditSourceOwnership, REPOSITORY_ROOT } from '../../check-scene-ownership.mjs';

test('production source cannot add another legacy constructor or editor import', () => {
  const candidate = 'src/game/features/new-feature/Controller.ts';
  assert.match(auditSourceOwnership(candidate, 'new ObjectFactory({});').join('\n'), /unapproved legacy ObjectFactory/);
  assert.match(auditSourceOwnership(candidate, "import('./editor/WeaponStudio');").join('\n'), /category-specific editor import/);
  assert.match(auditSourceOwnership(candidate, 'localStorage.setItem("save", "1");').join('\n'), /browser persistence/);
  assert.deepEqual(auditSourceOwnership('src/game/infrastructure/persistence/Store.ts', 'localStorage.getItem("save");'), []);
});

test('unused map and NPC constructors are retired after managed scene replacement', () => {
  for (const relative of [
    'src/game/features/world/MapBuilder.ts',
    'src/game/features/npcs/NpcActor.ts',
    'src/game/features/npcs/NpcRuntimeController.ts',
  ]) assert.equal(existsSync(path.join(REPOSITORY_ROOT, relative)), false);
});

test('production no longer constructs Phaser object or enemy factories', () => {
  for (const relative of [
    'src/game/scenes/WorldScene.ts',
    'src/game/enemies/AuthoredEnemyPopulationController.ts',
  ]) {
    const source = readFileSync(path.join(REPOSITORY_ROOT, relative), 'utf8');
    assert.doesNotMatch(source, /new\s+(?:ObjectFactory|Enemy)\s*\(/);
  }
});
