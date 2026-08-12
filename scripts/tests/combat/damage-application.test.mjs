import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
async function load(entry) { const result = await build({ absWorkingDir: root, entryPoints: [entry], bundle: true, format: 'esm', platform: 'node', write: false }); return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`); }
test('accepted damage reports capped HP removed and fatal overkill', async () => {
  const damage = await load('src/game/combat/DamageableTarget.ts');
  assert.deepEqual(damage.acceptedDamage(20, 13), { status: 'accepted', actualDamage: 7, defeated: false });
  assert.deepEqual(damage.acceptedDamage(6, 0), { status: 'accepted', actualDamage: 6, defeated: true });
  assert.deepEqual(damage.acceptedDamage(6, -10), { status: 'accepted', actualDamage: 6, defeated: true });
  assert.deepEqual(damage.rejectedDamage('invulnerable'), { status: 'rejected', actualDamage: 0, defeated: false, reason: 'invulnerable' });
});
