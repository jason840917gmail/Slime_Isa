import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { Readable } from 'node:stream';
import test from 'node:test';

import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const journalModule = await loadTypescriptModule('src/game/infrastructure/scenes/editor/ContentWriteJournal.ts');
const pluginModule = await loadTypescriptModule('src/game/infrastructure/scenes/editor/SceneStudioContentPlugin.ts');
const repositoryModule = await loadTypescriptModule('src/game/infrastructure/scenes/editor/SceneStudioRepository.ts');
const { ContentWriteJournal, contentHash } = journalModule;
const { sceneStudioContentPlugin } = pluginModule;
const { SceneStudioRepository, SceneStudioConflictError } = repositoryModule;

const canonical = (value) => `${JSON.stringify(value, null, 2)}\n`;
const scene = (id = 'test.scene') => ({
  version: 1,
  sceneId: id,
  rootNodeId: 'root',
  nodes: [{ id: 'root', name: 'Root', type: 'Node', parentId: null, order: 0, properties: {} }],
  instances: [],
});

async function temporaryRoot(prefix) {
  const root = await mkdtemp(path.join(os.tmpdir(), prefix));
  test.after(() => rm(root, { recursive: true, force: true }));
  return root;
}

test('journal commits stable write sets and rejects stale hashes and path traversal', async () => {
  const root = await temporaryRoot('scene-journal-contract-');
  await writeFile(path.join(root, 'a.scene.json'), 'before-a\r\n', 'utf8');
  const journal = new ContentWriteJournal(root);
  const result = await journal.commit([
    { relativePath: 'b.resource.json', content: 'new-b\n', expectedHash: null },
    { relativePath: 'a.scene.json', content: 'new-a\n', expectedHash: contentHash('before-a\r\n') },
  ]);
  assert.deepEqual(result.map((entry) => entry.relativePath), ['a.scene.json', 'b.resource.json']);
  assert.equal(await readFile(path.join(root, 'a.scene.json'), 'utf8'), 'new-a\n');
  assert.equal(await readFile(path.join(root, 'b.resource.json'), 'utf8'), 'new-b\n');
  await assert.rejects(
    () => journal.commit([{ relativePath: 'a.scene.json', content: 'lost\n', expectedHash: contentHash('before-a\r\n') }]),
    /Content conflict/,
  );
  await assert.rejects(
    () => journal.commit([{ relativePath: '../outside.scene.json', content: 'lost\n', expectedHash: null }]),
    /Unsafe content path/,
  );
  assert.equal(await readFile(path.join(root, 'a.scene.json'), 'utf8'), 'new-a\n');
});

test('journal restores every exact original after a partial write failure', async () => {
  const root = await temporaryRoot('scene-journal-rollback-');
  const first = Buffer.from([0, 13, 10, 255, 4]);
  const second = Buffer.from('second-before\r\n');
  await writeFile(path.join(root, 'a.scene.json'), first);
  await writeFile(path.join(root, 'b.scene.json'), second);
  const journal = new ContentWriteJournal(root, {
    transactionId: () => 'fault-injected',
    beforeReplace(_relativePath, index) { if (index === 1) throw new Error('injected replacement failure'); },
  });
  await assert.rejects(() => journal.commit([
    { relativePath: 'a.scene.json', content: 'replacement-a\n', expectedHash: contentHash(first) },
    { relativePath: 'b.scene.json', content: 'replacement-b\n', expectedHash: contentHash(second) },
  ]), /injected replacement failure/);
  assert.deepEqual(await readFile(path.join(root, 'a.scene.json')), first);
  assert.deepEqual(await readFile(path.join(root, 'b.scene.json')), second);
  assert.deepEqual(await readdir(path.join(root, '.scene-studio-transactions')), []);
});

test('startup recovery rolls back prepared journals and only cleans committed journals', async () => {
  const root = await temporaryRoot('scene-journal-recovery-');
  const journalRoot = path.join(root, '.scene-studio-transactions');
  await mkdir(path.join(journalRoot, 'prepared'), { recursive: true });
  await writeFile(path.join(root, 'existing.scene.json'), 'interrupted\n');
  await writeFile(path.join(root, 'created.scene.json'), 'partial-new\n');
  await writeFile(path.join(journalRoot, 'prepared', '0.original'), 'exact-original\r\n');
  await writeFile(path.join(journalRoot, 'prepared', 'manifest.json'), JSON.stringify({
    version: 1,
    state: 'prepared',
    entries: [
      { relativePath: 'existing.scene.json', existed: true, originalHash: contentHash('exact-original\r\n'), backupName: '0.original' },
      { relativePath: 'created.scene.json', existed: false, originalHash: null, backupName: null },
    ],
  }));
  await mkdir(path.join(journalRoot, 'committed'), { recursive: true });
  await writeFile(path.join(journalRoot, 'committed', 'manifest.json'), JSON.stringify({ version: 1, state: 'committed', entries: [] }));
  await mkdir(path.join(journalRoot, 'preparing'), { recursive: true });
  await writeFile(path.join(journalRoot, 'preparing', 'manifest.json.tmp'), 'partial manifest');
  const journal = new ContentWriteJournal(root);
  await journal.recover();
  assert.equal(await readFile(path.join(root, 'existing.scene.json'), 'utf8'), 'exact-original\r\n');
  await assert.rejects(() => readFile(path.join(root, 'created.scene.json')), /ENOENT/);
  assert.deepEqual(await readdir(journalRoot), []);
});

class TestResponse {
  statusCode = 200;
  headers = {};
  body = '';
  setHeader(name, value) { this.headers[name] = value; }
  end(value = '') { this.body += String(value); }
}

async function mountPlugin(root, options = {}) {
  let middleware;
  const plugin = sceneStudioContentPlugin({ contentRoot: root, hasAsset: () => true, ...options });
  await plugin.configureServer({
    middlewares: {
      use(endpoint, handler) {
        assert.equal(endpoint, '/__scene-studio/content');
        middleware = handler;
      },
    },
  });
  assert.ok(middleware);
  return async ({ method = 'GET', url = '/', body }) => {
    const request = Readable.from(body === undefined ? [] : [body]);
    request.method = method;
    request.url = url;
    const response = new TestResponse();
    await middleware(request, response);
    return { status: response.statusCode, json: JSON.parse(response.body) };
  };
}

test('the single content endpoint loads repair drafts and validates canonical conflict-safe saves', async () => {
  const root = await temporaryRoot('scene-studio-endpoint-');
  const validSource = canonical(scene());
  await writeFile(path.join(root, 'test.scene.json'), validSource);
  await writeFile(path.join(root, 'repair.scene.json'), canonical({ ...scene('repair.scene'), opaqueFutureField: { retained: true } }));
  const request = await mountPlugin(root);

  const loaded = await request({ url: '/?action=load&kind=scene&id=test.scene' });
  assert.equal(loaded.status, 200);
  assert.equal(loaded.json.item.hash, contentHash(validSource));
  assert.equal(loaded.json.item.repairMode, false);
  const repair = await request({ url: '/?action=load&kind=scene&id=repair.scene' });
  assert.equal(repair.status, 200);
  assert.equal(repair.json.item.repairMode, true);
  assert.deepEqual(repair.json.item.document.opaqueFutureField, { retained: true });
  assert.equal((await request({ url: '/?action=load&kind=scene&id=missing.scene' })).status, 404);

  const updated = scene();
  updated.nodes[0].name = 'Updated';
  const saved = await request({
    method: 'POST',
    body: JSON.stringify({ writes: [{ kind: 'scene', id: 'test.scene', relativePath: 'test.scene.json', document: updated, expectedHash: contentHash(validSource) }] }),
  });
  assert.equal(saved.status, 200);
  assert.equal(await readFile(path.join(root, 'test.scene.json'), 'utf8'), canonical(updated));
  const conflict = await request({
    method: 'POST',
    body: JSON.stringify({ writes: [{ kind: 'scene', id: 'test.scene', relativePath: 'test.scene.json', document: scene(), expectedHash: contentHash(validSource) }] }),
  });
  assert.equal(conflict.status, 409);
  const traversal = await request({
    method: 'POST',
    body: JSON.stringify({ writes: [{ kind: 'scene', id: 'new.scene', relativePath: '../new.scene.json', document: scene('new.scene'), expectedHash: null }] }),
  });
  assert.equal(traversal.status, 400);
});

test('the content endpoint moves documents between folders and refuses tool-owned or clashing moves', async () => {
  const root = await temporaryRoot('scene-studio-move-');
  await mkdir(path.join(root, 'objects', 'houses'), { recursive: true });
  await mkdir(path.join(root, 'objects', 'interiors'), { recursive: true });
  await writeFile(path.join(root, 'objects', 'house.scene.json'), canonical(scene('object.house')));
  await writeFile(path.join(root, 'objects', 'owned.scene.json'), canonical(scene('object.owned')));
  const guard = async (relativePath) => relativePath === 'objects/owned.scene.json' ? 'owned by a converter'
    : relativePath.startsWith('objects/interiors/') ? 'generated folder' : undefined;
  const request = await mountPlugin(root, { moveGuard: guard });
  const move = (body) => request({ method: 'POST', url: '/?action=move', body: JSON.stringify(body) });

  const moved = await move({ kind: 'scene', id: 'object.house', folder: 'objects/houses' });
  assert.equal(moved.status, 200);
  assert.deepEqual(moved.json.item, { kind: 'scene', id: 'object.house', relativePath: 'objects/houses/house.scene.json' });
  assert.deepEqual(await readdir(path.join(root, 'objects', 'houses')), ['house.scene.json']);
  assert.equal((await request({ url: '/?action=load&kind=scene&id=object.house' })).json.item.relativePath, 'objects/houses/house.scene.json');

  // to the content root and back into a folder
  assert.equal((await move({ kind: 'scene', id: 'object.house', folder: '' })).json.item.relativePath, 'house.scene.json');
  assert.equal((await move({ kind: 'scene', id: 'object.house', folder: 'objects' })).json.item.relativePath, 'objects/house.scene.json');

  const refusals = [
    [{ kind: 'scene', id: 'object.owned', folder: 'objects/houses' }, /owned by a converter/],
    [{ kind: 'scene', id: 'object.house', folder: 'objects/interiors' }, /generated folder/],
    [{ kind: 'scene', id: 'object.house', folder: 'objects' }, /already in objects/],
    [{ kind: 'scene', id: 'object.house', folder: 'missing' }, /does not exist/],
    [{ kind: 'scene', id: 'object.house', folder: '../outside' }, /must use lowercase/],
    [{ kind: 'scene', id: 'object.missing', folder: 'objects/houses' }, /Unknown scene/],
  ];
  for (const [body, message] of refusals) {
    const response = await move(body);
    assert.equal(response.status, 400);
    assert.match(response.json.error, message);
  }
  await mkdir(path.join(root, 'other'));
  await writeFile(path.join(root, 'objects', 'twin.scene.json'), canonical(scene('object.twin')));
  await writeFile(path.join(root, 'other', 'twin.scene.json'), canonical(scene('object.other-twin')));
  assert.match((await move({ kind: 'scene', id: 'object.twin', folder: 'other' })).json.error, /already exists/);
  assert.ok((await readdir(path.join(root, 'objects'))).includes('twin.scene.json'), 'a refused move leaves the file in place');
  // a rename into a variant family, and rejected names
  const renamed = await move({ kind: 'scene', id: 'object.house', folder: 'objects', fileName: 'house-world-solid--house.scene.json' });
  assert.equal(renamed.json.item.relativePath, 'objects/house-world-solid--house.scene.json');
  for (const fileName of ['House.scene.json', 'house.resource.json', '../house.scene.json', 'a---b.scene.json']) {
    assert.match((await move({ kind: 'scene', id: 'object.house', folder: 'objects/houses', fileName })).json.error, /must be lowercase ID segments/);
  }
});

test('the default move guard protects conversion outputs and generated interiors', async () => {
  const { toolOwnedContentGuard } = await loadTypescriptModule('src/game/infrastructure/scenes/editor/ToolOwnedContent.ts');
  const repositoryRoot = await temporaryRoot('scene-studio-guard-');
  await mkdir(path.join(repositoryRoot, 'scripts', 'migrations'), { recursive: true });
  await writeFile(path.join(repositoryRoot, 'scripts', 'migrations', 'universal-scene-conversion-ledger.json'), JSON.stringify({
    rows: [{ key: 'object:house.world.solid', outputs: [{ path: 'src/game/content/scenes/authored/objects/house-world-solid.scene.json' }] }],
  }));
  const guard = toolOwnedContentGuard(repositoryRoot);
  assert.match(await guard('objects/house-world-solid.scene.json'), /conversion output of 'object:house\.world\.solid'/);
  assert.match(await guard('objects/interiors/decor/interior-decor-candle.scene.json'), /interiors:scenes/);
  assert.equal(await guard('objects/house-mushroom.scene.json'), undefined);
  assert.equal(await toolOwnedContentGuard(path.join(repositoryRoot, 'missing'))('objects/anything.scene.json'), undefined);
});

test('browser repository sends the complete write set and distinguishes conflicts', async () => {
  const calls = [];
  const fakeFetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    if (String(url).includes('conflict')) return new Response(JSON.stringify({ error: 'newer disk version' }), { status: 409 });
    if (init.method === 'POST') return new Response(JSON.stringify({ writes: [{ kind: 'scene', id: 'test.scene', relativePath: 'test.scene.json', hash: 'a'.repeat(64) }] }), { status: 200 });
    return new Response(JSON.stringify({ items: [] }), { status: 200 });
  };
  const repository = new SceneStudioRepository('/content', fakeFetch);
  const writes = [{ kind: 'scene', id: 'test.scene', relativePath: 'test.scene.json', document: scene(), expectedHash: null }];
  assert.equal((await repository.save(writes))[0].hash, 'a'.repeat(64));
  assert.deepEqual(JSON.parse(calls[0].init.body).writes, writes);
  const conflicting = new SceneStudioRepository('/conflict', fakeFetch);
  await assert.rejects(() => conflicting.save(writes), SceneStudioConflictError);
});

test('browser repository moves documents and surfaces refusals', async () => {
  const calls = [];
  const fakeFetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    const { folder } = JSON.parse(init.body);
    if (folder === 'locked') return new Response(JSON.stringify({ error: 'owned by a converter' }), { status: 400 });
    return new Response(JSON.stringify({ item: { kind: 'scene', id: 'object.house', relativePath: `${folder}/house.scene.json` } }), { status: 200 });
  };
  const repository = new SceneStudioRepository('/content', fakeFetch);
  assert.deepEqual(await repository.move('scene', 'object.house', 'objects/houses'), { kind: 'scene', id: 'object.house', relativePath: 'objects/houses/house.scene.json' });
  assert.equal(calls[0].url, '/content?action=move');
  assert.deepEqual(JSON.parse(calls[0].init.body), { kind: 'scene', id: 'object.house', folder: 'objects/houses' });
  await repository.move('scene', 'object.house', 'objects', 'house-world-solid--house.scene.json');
  assert.deepEqual(JSON.parse(calls[1].init.body), { kind: 'scene', id: 'object.house', folder: 'objects', fileName: 'house-world-solid--house.scene.json' });
  await assert.rejects(() => repository.move('scene', 'object.house', 'locked'), /owned by a converter/);
});
