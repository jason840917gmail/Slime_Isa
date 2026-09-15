import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const { characterContentModulesPlugin } = await loadTypescriptModule('src/game/content/characters/characterContentModulesPlugin.ts');

test('all converted characters declare Scene Studio as their writer', async () => {
  const ledger = JSON.parse(await readFile('scripts/migrations/universal-scene-conversion-ledger.json', 'utf8'));
  const characters = ledger.rows.filter((row) => row.family === 'character' && row.classification === 'convert');
  assert.ok(characters.length > 0);
  assert.deepEqual([...new Set(characters.map((row) => row.writerState))], ['scene']);
});

test('read-only legacy character endpoints reject every package mutation', async () => {
  const handlers = new Map();
  const plugin = characterContentModulesPlugin({ characterAuthoring: 'read-only' });
  const configureServer = plugin.configureServer;
  assert.ok(configureServer);
  const server = {
    middlewares: { use(route, handler) { handlers.set(route, handler); } },
    moduleGraph: { getModuleById() { return undefined; }, invalidateModule() {} },
  };
  if (typeof configureServer === 'function') await configureServer(server);
  else await configureServer.handler(server);

  for (const route of [
    '/__character-studio/create',
    '/__character-studio/package/create',
    '/__character-studio/package/update',
    '/__character-studio/package/duplicate',
  ]) {
    const handler = handlers.get(route);
    assert.ok(handler, `${route} is registered`);
    let payload;
    const response = {
      statusCode: 0,
      setHeader() {},
      end(body) { payload = JSON.parse(body); },
    };
    handler({ method: 'POST' }, response, () => {});
    assert.equal(response.statusCode, 409);
    assert.equal(payload.error.code, 'scene-owned');
  }
});
