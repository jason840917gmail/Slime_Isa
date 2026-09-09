import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
let catalogModule;
let routeModule;

async function loadTypeScriptModule(entryPoint) {
  const result = await build({ absWorkingDir: repositoryRoot, entryPoints: [entryPoint], bundle: true, format: 'esm', platform: 'node', write: false });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

before(async () => {
  [catalogModule, routeModule] = await Promise.all([
    loadTypeScriptModule('src/game/editor/AnimationStudioCatalog.ts'),
    loadTypeScriptModule('src/game/editor/AnimationStudioRoute.ts'),
  ]);
});

function character(characterId, kind = 'npc') {
  return { character: { characterId, displayName: characterId, kind }, visualSet: { visualSetId: `visual.${characterId}`, assetId: `sheet.${characterId}`, clips: { idle: { frames: [0], framesPerSecond: 8, loop: true } } } };
}

function weapon(overrides = {}) {
  return {
    version: 2, weaponId: 'tool.hammer', displayName: 'Hammer', revision: 'r1',
    animations: { idle: { version: 2, durationSeconds: 0.25, framesPerSecond: 8, loop: true, layers: [] }, ...overrides.animations },
    directionalAttacks: { right: { animation: { version: 2, durationSeconds: 0.25, framesPerSecond: 8, loop: false, layers: [] } }, ...overrides.directionalAttacks },
  };
}

test('catalog keys separate character, shared, and weapon-owned entries', () => {
  const result = catalogModule.buildAnimationStudioCatalog(
    [character('tool.hammer')],
    { packages: [{ animationId: 'tool.hammer', displayName: 'Shared Hammer', packagePath: 'objects/hammer/animation.json', revision: 'a1', animation: {} }] },
    [weapon()],
  );
  const keys = result.entries.map(catalogModule.animationStudioEntryKey);
  assert.deepEqual(keys, ['character:tool.hammer', 'shared:tool.hammer', 'weapon:tool.hammer:idle', 'weapon:tool.hammer:attack:right']);
});

test('inherited directional slots become aliases without materializing missing documents', () => {
  const result = catalogModule.buildAnimationStudioCatalog([], { packages: [] }, [weapon({ directionalAttacks: { right: { animation: {} } } })]);
  assert.equal(result.entries.filter((entry) => entry.kind === 'weapon-owned' && entry.slot === 'attack').length, 1);
  const left = result.aliases.find((alias) => alias.direction === 'left');
  const up = result.aliases.find((alias) => alias.direction === 'up');
  assert.equal(left?.reason, 'inherited');
  assert.equal(left?.targetKey, 'weapon:tool.hammer:attack:right');
  assert.equal(up?.reason, 'inherited');
});

test('route parsing rejects mixed families and serialization preserves unrelated query values', () => {
  const mixed = new URLSearchParams('studio=animations&character=hero&animation=shared.idle');
  assert.equal(routeModule.parseAnimationStudioRoute(mixed), undefined);
  const current = new URLSearchParams('studio=weapons&editor=level-1&foo=keep&weapon=old&slot=attack&direction=left');
  const next = routeModule.writeAnimationStudioRoute(current, { kind: 'character', characterId: 'village elder', clipId: 'walk' });
  assert.equal(next.get('studio'), 'animations');
  assert.equal(next.get('editor'), 'level-1');
  assert.equal(next.get('foo'), 'keep');
  assert.equal(next.get('character'), 'village elder');
  assert.equal(next.get('clip'), 'walk');
  assert.equal(next.has('weapon'), false);
  assert.equal(routeModule.parseAnimationStudioRoute(next)?.kind, 'character');
});
