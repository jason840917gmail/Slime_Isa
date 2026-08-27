import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let icons;
let catalogModule;
let mutation;
let migration;

async function loadTypeScriptModule(entryPoint) {
  const result = await build({
    absWorkingDir: repositoryRoot,
    entryPoints: [entryPoint],
    bundle: true,
    format: 'esm',
    platform: 'node',
    write: false,
  });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

before(async () => {
  [icons, catalogModule, mutation, migration] = await Promise.all([
    loadTypeScriptModule('src/game/content/weapons/WeaponIcon.ts'),
    loadTypeScriptModule('src/game/content/weapons/WeaponIconCatalog.ts'),
    loadTypeScriptModule('src/game/editor/LayeredWeaponStudioMutation.ts'),
    loadTypeScriptModule('src/game/content/weapons/migrateLegacyWeapon.ts'),
  ]);
});

const manifest = {
  assets: {
    single: {
      status: 'ready', tags: ['weapon'], runtime: { textureKey: 'weapon-single' },
      source: { kind: 'image', path: 'single.png', expect: { w: 32, h: 32 } },
    },
    sheet: {
      status: 'ready', tags: ['weapon'], runtime: { textureKey: 'weapon-sheet' },
      source: { kind: 'spritesheet', path: 'sheet.png', frame: { w: 32, h: 32, cols: 4, rows: 2, count: 7 } },
    },
    unrelated: {
      status: 'ready', tags: ['enemy'], runtime: { textureKey: 'enemy-sheet' },
      source: { kind: 'spritesheet', path: 'enemy.png', frame: { w: 32, h: 32, cols: 2, rows: 2 } },
    },
  },
};

const studioEntries = [
  { status: 'ready', kind: 'image', textureKey: 'weapon-single', tags: ['weapon'] },
  { status: 'ready', kind: 'spritesheet', textureKey: 'weapon-sheet', tags: ['weapon'], frame: { count: 7 } },
  { status: 'ready', kind: 'spritesheet', textureKey: 'enemy-sheet', tags: ['enemy'], frame: { count: 4 } },
];

test('manifest and Studio adapters produce one equivalent normalized icon catalog', () => {
  const fromManifest = [...catalogModule.weaponIconCatalogFromManifest(manifest).entries()];
  const fromStudio = [...catalogModule.weaponIconCatalogFromStudio(studioEntries).entries()];
  assert.deepEqual(fromStudio, fromManifest);
  assert.equal(new Map(fromManifest).has('enemy-sheet'), false);
  assert.equal(new Map(fromManifest).get('weapon-sheet').frameCount, 7);
});

test('catalog validation enforces frame rules for images, spritesheets, procedural keys, and unknown keys', () => {
  const catalog = catalogModule.weaponIconCatalogFromManifest(manifest);
  assert.deepEqual(catalogModule.validateWeaponIconAgainstCatalog({ iconKey: 'weapon-single', iconFrame: 0 }, catalog), []);
  assert.match(catalogModule.validateWeaponIconAgainstCatalog({ iconKey: 'weapon-single', iconFrame: 1 }, catalog)[0], /must use frame 0/);
  assert.deepEqual(catalogModule.validateWeaponIconAgainstCatalog({ iconKey: 'weapon-sheet', iconFrame: 6 }, catalog), []);
  assert.match(catalogModule.validateWeaponIconAgainstCatalog({ iconKey: 'weapon-sheet', iconFrame: 7 }, catalog)[0], /outside/);
  assert.deepEqual(catalogModule.validateWeaponIconAgainstCatalog({ iconKey: 'weapon-hammer', iconFrame: 0 }, catalog), []);
  assert.match(catalogModule.validateWeaponIconAgainstCatalog({ iconKey: 'weapon-hammer', iconFrame: 1 }, catalog)[0], /must use frame 0/);
  assert.match(catalogModule.validateWeaponIconAgainstCatalog({ iconKey: 'missing', iconFrame: 0 }, catalog)[0], /not an available/);
});

test('the pure icon resolver returns only complete valid key/frame pairs', () => {
  assert.deepEqual(icons.resolveWeaponIcon({ iconKey: '  weapon-sheet ', iconFrame: 3 }), { iconKey: 'weapon-sheet', iconFrame: 3 });
  assert.equal(icons.resolveWeaponIcon({ iconKey: '', iconFrame: 0 }), undefined);
  assert.equal(icons.resolveWeaponIcon({ iconKey: 'weapon-sheet', iconFrame: -1 }), undefined);
  assert.equal(icons.resolveWeaponIcon({ iconKey: 'weapon-sheet' }), undefined);
});

function legacyWeapon() {
  return {
    version: 1, weaponId: 'fixture', displayName: 'Fixture', category: 'melee', characterActionId: 'attack-1', assetId: 'weapon.fixture',
    animations: {
      idle: { frames: [0], framesPerSecond: 10, loop: true },
      attack: { frames: [1], framesPerSecond: 10, loop: false },
    },
    baseDamage: 1, cooldownMs: 100, hitboxWidth: 8, hitboxHeight: 8, hitboxOffset: 2,
    hitboxDurationMs: 100, knockStrength: 1, vfxColor: 0xffffff, unlockLevel: 1,
    iconKey: 'weapon-single', description: 'Fixture',
  };
}

function studioState() {
  return {
    draft: migration.migrateLegacyWeaponDefinition(legacyWeapon()),
    effectIsNew: false, effectDirty: false, dirty: false, selectedId: 'fixture',
    scope: 'attack', direction: 'right', effectDirection: 'right', playhead: 0,
    inspectorTab: 'identity', playing: false, iconPickerOpen: true, iconPickerAssetId: 'sheet',
  };
}

test('icon selection participates in dirty tracking and undo/redo history', () => {
  const initial = studioState();
  const selected = mutation.reduceWeaponIconAction(initial, {
    type: 'select', selection: icons.weaponIconSelection({ textureKey: 'weapon-sheet' }, 4),
  });
  assert.equal(selected.dirty, true);
  assert.equal(selected.iconPickerOpen, false);
  assert.equal(selected.draft.iconKey, 'weapon-sheet');
  assert.equal(selected.draft.iconFrame, 4);

  const committed = mutation.commitWeaponStudioMutation(initial, selected, { undo: [], redo: [mutation.captureWeaponHistory(initial)] });
  assert.equal(committed.history.undo.length, 1);
  assert.equal(committed.history.redo.length, 0);

  const undone = mutation.applyWeaponStudioHistory(committed.state, committed.history, false);
  assert.ok(undone);
  assert.equal(undone.state.draft.iconKey, 'weapon-single');
  assert.equal(undone.state.draft.iconFrame, 0);
  assert.equal(undone.state.dirty, false);

  const redone = mutation.applyWeaponStudioHistory(undone.state, undone.history, true);
  assert.ok(redone);
  assert.equal(redone.state.draft.iconKey, 'weapon-sheet');
  assert.equal(redone.state.draft.iconFrame, 4);
  assert.equal(redone.state.dirty, true);

  const cleared = mutation.reduceWeaponIconAction(redone.state, { type: 'clear' });
  assert.equal(cleared.draft.iconKey, '');
  assert.equal(cleared.draft.iconFrame, 0);
});
