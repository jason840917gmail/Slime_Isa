import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
async function load(entry) { const result = await build({ absWorkingDir: root, entryPoints: [entry], bundle: true, format: 'esm', platform: 'node', write: false }); return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`); }
test('effects require an assigned ID and accepted positive damage', async () => {
  const effect = await load('src/game/combat/ConfirmedHitEffect.ts');
  assert.equal(effect.shouldSpawnConfirmedHitEffect('spark', { status: 'accepted', actualDamage: 1, defeated: false }), true);
  assert.equal(effect.shouldSpawnConfirmedHitEffect(undefined, { status: 'accepted', actualDamage: 1, defeated: false }), false);
  assert.equal(effect.shouldSpawnConfirmedHitEffect('spark', { status: 'accepted', actualDamage: 0, defeated: false }), false);
  assert.equal(effect.shouldSpawnConfirmedHitEffect('spark', { status: 'rejected', actualDamage: 0, defeated: false, reason: 'dead' }), false);
});
