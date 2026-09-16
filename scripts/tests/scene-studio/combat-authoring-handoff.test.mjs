import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { characterContentModulesPlugin } = await loadTypescriptModule('src/game/content/characters/characterContentModulesPlugin.ts');

test('converted combat entities declare Scene Studio as their writer', async () => {
  const ledger = JSON.parse(await readFile('scripts/migrations/universal-scene-conversion-ledger.json', 'utf8'));
  const entities = ledger.rows.filter((row) => ['weapon', 'projectile', 'effect'].includes(row.family) && row.classification === 'convert');
  assert.equal(entities.length, 16);
  assert.deepEqual([...new Set(entities.map((row) => row.writerState))], ['scene']);
});

test('read-only legacy combat endpoints reject every mutation while catalogs remain available', async () => {
  const handlers = new Map();
  const plugin = characterContentModulesPlugin({ combatAuthoring: 'read-only' });
  const configureServer = plugin.configureServer;
  assert.ok(configureServer);
  const server = {
    middlewares: { use(route, handler) { handlers.set(route, handler); } },
    moduleGraph: { getModuleById() { return undefined; }, invalidateModule() {} },
  };
  if (typeof configureServer === 'function') await configureServer(server);
  else await configureServer.handler(server);

  for (const route of [
    '/__character-studio/projectile/create', '/__character-studio/projectile/update',
    '/__character-studio/weapon/create', '/__character-studio/weapon/update', '/__character-studio/weapon/save-package',
    '/__character-studio/effect/create', '/__character-studio/effect/update',
  ]) {
    const handler = handlers.get(route);
    assert.ok(handler, `${route} is registered`);
    let payload;
    const response = { statusCode: 0, setHeader() {}, end(body) { payload = JSON.parse(body); } };
    handler({ method: 'POST' }, response, () => {});
    assert.equal(response.statusCode, 409);
    assert.equal(payload.error.code, 'scene-owned');
  }
});
