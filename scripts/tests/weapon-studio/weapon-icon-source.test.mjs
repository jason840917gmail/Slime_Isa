import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let icons;
let catalogModule;

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
  [icons, catalogModule] = await Promise.all([
    loadTypeScriptModule('src/game/content/weapons/WeaponIcon.ts'),
    loadTypeScriptModule('src/game/content/weapons/WeaponIconCatalog.ts'),
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
    oversized: {
      status: 'ready', tags: ['weapon'], runtime: { textureKey: 'weapon-oversized' },
      source: { kind: 'spritesheet', path: 'oversized.png', frame: { w: 32, h: 32, cols: 2, rows: 2, count: 5 } },
    },
    missingDimensions: {
      status: 'ready', tags: ['weapon'], runtime: { textureKey: 'weapon-missing-dimensions' },
      source: { kind: 'image', path: 'missing-dimensions.png' },
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
  const sortEntries = (entries) => entries.toSorted(([left], [right]) => left.localeCompare(right));
  assert.deepEqual(sortEntries(fromStudio), sortEntries(fromManifest));
  assert.equal(new Map(fromManifest).has('enemy-sheet'), false);
  assert.equal(new Map(fromManifest).has('weapon-oversized'), false);
  assert.equal(new Map(fromManifest).has('weapon-missing-dimensions'), false);
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
