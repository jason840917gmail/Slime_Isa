import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import test from 'node:test';

const root = new URL('../../../', import.meta.url);
const read = (path) => readFileSync(new URL(path, root), 'utf8');

test('MapBuilder owns an NPC branch before the legacy object factory', () => {
  const source = read('src/game/features/world/MapBuilder.ts');
  const npcBranch = source.indexOf('if (definition.npc)');
  const factoryCall = source.indexOf('this.objectFactory.create(object.objectId', npcBranch);
  assert.ok(npcBranch >= 0);
  assert.ok(factoryCall > npcBranch);
  assert.match(source.slice(npcBranch, factoryCall), /new NpcActor/);
  assert.match(source.slice(npcBranch, factoryCall), /onNpcCreated/);
});

test('NPC actors expose isolated pause, interaction-lock, and teardown boundaries', () => {
  const actor = read('src/game/features/npcs/NpcActor.ts');
  const runtime = read('src/game/features/npcs/NpcRuntimeController.ts');
  assert.match(actor, /CharacterAnimationTrackRunner/);
  assert.match(actor, /acquireInteractionLock/);
  assert.match(actor, /this\.trackRunner\.destroy\(\)/);
  assert.match(runtime, /setSimulationPaused/);
  assert.match(runtime, /registration\.actor\.destroy\(\)/);
});

test('legacy NPC object animation packages are removed after character-package migration', () => {
  assert.equal(existsSync(new URL('src/game/content/animations/objects/npc/village-elder-plop/idle/animation.json', root)), false);
  assert.equal(existsSync(new URL('src/game/content/animations/objects/npc/mossy-scout/idle/animation.json', root)), false);
});
