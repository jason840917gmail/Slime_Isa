import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
async function load(entry) { const result = await build({ absWorkingDir: root, entryPoints: [entry], bundle: true, format: 'esm', platform: 'node', write: false }); return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`); }
test('cardinal attacks resolve the target near edge opposite incoming motion', async () => {
  const contact = await load('src/game/combat/ContactPoint.ts'); const bounds = { x: 10, y: 20, width: 40, height: 30 };
  assert.deepEqual(contact.contactPointAtTargetEdge(bounds, { x: 1, y: 0 }), { x: 10, y: 35 });
  assert.deepEqual(contact.contactPointAtTargetEdge(bounds, { x: -1, y: 0 }), { x: 50, y: 35 });
  assert.deepEqual(contact.contactPointAtTargetEdge(bounds, { x: 0, y: 1 }), { x: 30, y: 20 });
  assert.deepEqual(contact.contactPointAtTargetEdge(bounds, { x: 0, y: -1 }), { x: 30, y: 50 });
});
test('dominant-axis quantization and invalid fallback are deterministic', async () => {
  const contact = await load('src/game/combat/ContactPoint.ts');
  assert.equal(contact.quantizeContactDirection({ x: -9, y: 3 }), 'left'); assert.equal(contact.quantizeContactDirection({ x: 2, y: -7 }), 'up'); assert.equal(contact.quantizeContactDirection({ x: 0, y: 0 }), 'right');
  assert.deepEqual(contact.contactPointAtTargetEdge({ x: Number.NaN, y: 10, width: 20, height: 20 }, { x: 1, y: 0 }), { x: 0, y: 20 });
});
