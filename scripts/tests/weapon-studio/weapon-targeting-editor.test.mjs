import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFile } from 'node:fs/promises';
import { build } from 'esbuild';
import { validateHarvestCapabilities } from '../../lib/weapon-targeting-validation.mjs';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let targeting;
let studioMutation;

async function loadTypeScriptModule(entryPoint) {
  const result = await build({ absWorkingDir: repositoryRoot, entryPoints: [entryPoint], bundle: true, format: 'esm', platform: 'node', write: false });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

before(async () => {
  [targeting, studioMutation] = await Promise.all([
    loadTypeScriptModule('src/game/editor/WeaponTargetingEditor.ts'),
    loadTypeScriptModule('src/game/editor/LayeredWeaponStudioMutation.ts'),
  ]);
});

function state(overrides = {}) {
  return {
    draft: { damageModifiers: undefined, harvestCapabilities: undefined, ...overrides },
    effectIsNew: false, effectDirty: false, dirty: false, selectedId: 'fixture', scope: 'attack', direction: 'right',
    effectDirection: 'right', playhead: 0, inspectorTab: 'targeting', playing: false,
  };
}

test('targeting mutations add, edit, remove, and reject collisions without losing data', () => {
  let next = targeting.reduceWeaponTargetingAction(state(), { type: 'add-modifier' });
  assert.deepEqual(next.draft.damageModifiers, [{ targetTag: 'enemy', modifier: 1 }]);
  next = targeting.reduceWeaponTargetingAction(next, { type: 'set-modifier-tag', index: 0, targetTag: ' wood ' });
  next = targeting.reduceWeaponTargetingAction(next, { type: 'set-modifier-value', index: 0, modifier: 0.25 });
  assert.deepEqual(next.draft.damageModifiers, [{ targetTag: 'wood', modifier: 0.25 }]);
  next = targeting.reduceWeaponTargetingAction(next, { type: 'add-modifier' });
  const collision = targeting.reduceWeaponTargetingAction(next, { type: 'set-modifier-tag', index: 1, targetTag: ' wood ' });
  assert.deepEqual(collision.draft.damageModifiers, next.draft.damageModifiers);
  assert.match(collision.notice, /already used/);
  next = targeting.reduceWeaponTargetingAction(next, { type: 'remove-modifier', index: 1 });
  next = targeting.reduceWeaponTargetingAction(next, { type: 'remove-modifier', index: 0 });
  assert.equal(next.draft.damageModifiers, undefined);

  next = targeting.reduceWeaponTargetingAction(next, { type: 'add-capability' });
  next = targeting.reduceWeaponTargetingAction(next, { type: 'set-capability-tier', targetTag: 'wood', tier: 2 });
  next = targeting.reduceWeaponTargetingAction(next, { type: 'add-capability' });
  const renamed = targeting.reduceWeaponTargetingAction(next, { type: 'rename-capability', targetTag: 'wood', nextTargetTag: 'timber' });
  assert.deepEqual(renamed.draft.harvestCapabilities, { timber: 2, stone: 1 });
  const capabilityCollision = targeting.reduceWeaponTargetingAction(renamed, { type: 'rename-capability', targetTag: 'timber', nextTargetTag: ' stone ' });
  assert.deepEqual(capabilityCollision.draft.harvestCapabilities, renamed.draft.harvestCapabilities);
  next = targeting.reduceWeaponTargetingAction(renamed, { type: 'remove-capability', targetTag: 'stone' });
  next = targeting.reduceWeaponTargetingAction(next, { type: 'remove-capability', targetTag: 'timber' });
  assert.equal(next.draft.harvestCapabilities, undefined);
  assert.equal(next.dirty, true);
});

test('targeting changes participate in Studio undo and redo', () => {
  const initial = state();
  const edited = targeting.reduceWeaponTargetingAction(initial, { type: 'add-capability' });
  const committed = studioMutation.commitWeaponStudioMutation(initial, edited, { undo: [], redo: [] });
  const undone = studioMutation.applyWeaponStudioHistory(committed.state, committed.history, false);
  assert.equal(undone.state.draft.harvestCapabilities, undefined);
  const redone = studioMutation.applyWeaponStudioHistory(undone.state, undone.history, true);
  assert.deepEqual(redone.state.draft.harvestCapabilities, { wood: 1 });
});

test('targeting mutations reject blank numeric commits without changing authored values', () => {
  const initial = state({
    damageModifiers: [{ targetTag: 'wood', modifier: 0.5 }],
    harvestCapabilities: { wood: 2 },
  });
  const blankModifier = targeting.reduceWeaponTargetingAction(initial, {
    type: 'set-modifier-value', index: 0, modifier: '',
  });
  assert.equal(blankModifier.draft.damageModifiers[0].modifier, 0.5);
  assert.match(blankModifier.notice, /finite number/);

  const blankTier = targeting.reduceWeaponTargetingAction(initial, {
    type: 'set-capability-tier', targetTag: 'wood', tier: ' ',
  });
  assert.equal(blankTier.draft.harvestCapabilities.wood, 2);
  assert.match(blankTier.notice, /integer/);
});

test('capability mutations treat prototype names as legal custom tags', () => {
  const initial = state({ harvestCapabilities: { wood: 1 } });
  const renamed = targeting.reduceWeaponTargetingAction(initial, {
    type: 'rename-capability', targetTag: 'wood', nextTargetTag: 'constructor',
  });
  assert.deepEqual(renamed.draft.harvestCapabilities, { constructor: 1 });
  assert.equal(renamed.notice, undefined);

  const updated = targeting.reduceWeaponTargetingAction(renamed, {
    type: 'set-capability-tier', targetTag: 'constructor', tier: '2',
  });
  assert.deepEqual(updated.draft.harvestCapabilities, { constructor: 2 });
  const removed = targeting.reduceWeaponTargetingAction(updated, {
    type: 'remove-capability', targetTag: 'constructor',
  });
  assert.equal(removed.draft.harvestCapabilities, undefined);
});

test('targeting renderer exposes existing values, constraints, actions, and accessible labels', () => {
  const html = targeting.renderWeaponTargetingInspector(state({
    damageModifiers: [{ targetTag: 'wood', modifier: 0.5 }, { targetTag: 'enemy', modifier: 0 }],
    harvestCapabilities: { wood: 1, stone: 2 },
  }).draft);
  assert.match(html, /data-action="add-target-modifier"/);
  assert.match(html, /data-action="remove-target-modifier"/);
  assert.match(html, /data-action="add-harvest-capability"/);
  assert.match(html, /data-action="remove-harvest-capability"/);
  assert.match(html, /min="0" step="0\.1" value="0\.5"/);
  assert.match(html, /min="1" step="1" value="2"/);
  assert.match(html, /aria-label="Remove damage modifier for wood"/);
  assert.match(html, /aria-label="Remove harvest capability for stone"/);
  assert.match(html, /id="weapon-target-tags"/);
  assert.match(html, /id="weapon-harvest-tags"/);
});

test('inspector tabs declare TARGETING between COMBAT and LAYER', () => {
  assert.deepEqual(studioMutation.WEAPON_STUDIO_INSPECTOR_TABS.map(({ id }) => id), ['identity', 'combat', 'targeting', 'layer', 'on-hit']);
});

test('mounted Studio routes targeting controls and CSS keeps five tab columns', async () => {
  const [studioSource, cssSource] = await Promise.all([
    readFile(path.join(repositoryRoot, 'src/game/editor/LayeredWeaponStudio.ts'), 'utf8'),
    readFile(path.join(repositoryRoot, 'src/game/editor/character-studio.css'), 'utf8'),
  ]);
  assert.match(studioSource, /renderWeaponTargetingInspector\(state\.draft!\)/);
  assert.match(studioSource, /action === 'add-target-modifier'/);
  assert.match(studioSource, /action === 'remove-harvest-capability'/);
  assert.match(studioSource, /dataset\.targetModifierTag/);
  assert.match(studioSource, /dataset\.harvestCapabilityTier/);
  assert.match(cssSource, /\.layered-inspector-tabs\s*\{[^}]*repeat\(5, minmax\(0, 1fr\)\)/s);
  assert.match(cssSource, /\.weapon-targeting-row/);
});

test('repository capability validation rejects malformed containers, tags, and tiers', () => {
  assert.deepEqual(validateHarvestCapabilities({ wood: 1, stone: 2 }), []);
  assert.ok(validateHarvestCapabilities([]).some((issue) => issue.includes('must be an object')));
  assert.ok(validateHarvestCapabilities({ ' ': 1 }).some((issue) => issue.includes('non-empty')));
  assert.ok(validateHarvestCapabilities({ ' wood ': 1 }).some((issue) => issue.includes('surrounding whitespace')));
  assert.ok(validateHarvestCapabilities({ stone: 0, metal: 1.5 }).every((issue) => issue.includes('integer tier')));
});
