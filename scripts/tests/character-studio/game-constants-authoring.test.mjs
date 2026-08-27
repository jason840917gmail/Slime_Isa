import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import { createServer as createHttpServer } from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const vite = await createServer({ root: repositoryRoot, configFile: false, appType: 'custom', optimizeDeps: { noDiscovery: true }, server: { middlewareMode: true, hmr: false } });
after(() => vite.close());

const { GameConstantsStudioState } = await vite.ssrLoadModule('/src/game/editor/GameConstantsStudioState.ts');
const { CharacterDocumentState } = await vite.ssrLoadModule('/src/game/editor/CharacterDocumentState.ts');
const { readGameConstantsContent, saveGameConstantsContent, GameConstantsRevisionConflictError, gameConstantsContentPlugin } = await vite.ssrLoadModule('/src/game/content/gameConstantsContentPlugin.ts');
const sourcePath = path.join(repositoryRoot, 'src', 'game', 'content', 'game-constants.json');
const sourceDocument = JSON.parse(await fs.readFile(sourcePath, 'utf8'));
const characterDocument = JSON.parse(await fs.readFile(path.join(repositoryRoot, 'src', 'game', 'content', 'characters', 'player-slime', 'character.json'), 'utf8'));
const visualSetDocument = JSON.parse(await fs.readFile(path.join(repositoryRoot, 'src', 'game', 'content', 'characters', 'player-slime', 'visual-set.json'), 'utf8'));

test('gameplay-default inspector is restored by full and shelf-only renders', async () => {
  const source = await fs.readFile(path.join(repositoryRoot, 'src', 'game', 'editor', 'CharacterStudio.ts'), 'utf8');
  assert.match(source, /const renderStudioShell =/);
  assert.match(source, /const renderViewport[\s\S]*?renderStudioShell\(snapshot\)/);
  assert.match(source, /const rerenderShelf[\s\S]*?renderStudioShell\(currentState\.value\)/);
});

test('gameplay defaults state owns dirty history independently', () => {
  const state = new GameConstantsStudioState(sourceDocument, 'revision-a');
  assert.equal(state.value.dirty, false);

  state.updateScalar('initialAttributes', 'strength', 17);
  assert.equal(state.value.document.character.player.initialAttributes.strength, 17);
  assert.equal(state.value.dirty, true);

  state.undo();
  assert.equal(state.value.document.character.player.initialAttributes.strength, 10);
  assert.equal(state.value.dirty, false);

  state.redo();
  assert.equal(state.value.document.character.player.initialAttributes.strength, 17);
  assert.equal(state.value.dirty, true);
});

test('package and gameplay-default drafts keep independent dirty state', () => {
  const packageState = new CharacterDocumentState({ character: characterDocument, visualSet: visualSetDocument }, 'package-a');
  const constantsState = new GameConstantsStudioState(sourceDocument, 'constants-a');

  constantsState.updateScalar('initialAttributes', 'strength', 17);
  assert.equal(constantsState.value.dirty, true);
  assert.equal(packageState.value.dirty, false);

  packageState.mutate('Rename package', (draft) => { draft.character.displayName = 'Player Slime Test'; });
  assert.equal(packageState.value.dirty, true);
  constantsState.undo();
  assert.equal(constantsState.value.dirty, false);
  assert.equal(packageState.value.dirty, true);
});

test('level-row edits have their own undo and redo history', () => {
  const state = new GameConstantsStudioState(sourceDocument, 'revision-a');
  assert.equal(state.updateLevel(2, 'maxHp', 15), true);
  assert.equal(state.value.document.character.player.progression.levels[1].gains.maxHp, 15);
  state.undo();
  assert.equal(state.value.document.character.player.progression.levels[1].gains.maxHp, 12);
  state.redo();
  assert.equal(state.value.document.character.player.progression.levels[1].gains.maxHp, 15);
});

test('maximum level growth is deliberately incomplete and shrink restores a terminal row', () => {
  const state = new GameConstantsStudioState(sourceDocument, 'revision-a');
  assert.equal(state.setMaxLevel(11), true);
  assert.equal(state.value.document.character.player.progression.levels.length, 11);
  assert.equal(state.value.document.character.player.progression.levels[10].xpToNextLevel, null);
  assert.ok(state.value.errors.some((issue) => issue.path.includes('levels[9].xpToNextLevel')));
  assert.ok(state.value.errors.some((issue) => issue.path.includes('levels[10].gains')));

  state.undo();
  assert.equal(state.value.document.character.player.progression.maxLevel, 10);
  assert.equal(state.value.errors.length, 0);

  assert.equal(state.setMaxLevel(8), true);
  assert.equal(state.value.document.character.player.progression.levels.length, 8);
  assert.equal(state.value.document.character.player.progression.levels[7].xpToNextLevel, null);
  assert.equal(state.value.errors.length, 0);
});

test('constants persistence detects conflicts and preserves disk on atomic write failure', async () => {
  const fixtureDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'slime-game-constants-'));
  const fixturePath = path.join(fixtureDirectory, 'game-constants.json');
  await fs.copyFile(sourcePath, fixturePath);
  try {
    const initial = await readGameConstantsContent(fixturePath);
    const changed = structuredClone(initial.document);
    changed.character.player.initialAttributes.strength = 18;
    const saved = await saveGameConstantsContent(fixturePath, initial.revision, changed);
    assert.equal(saved.document.character.player.initialAttributes.strength, 18);

    await assert.rejects(
      saveGameConstantsContent(fixturePath, initial.revision, changed),
      (error) => error instanceof GameConstantsRevisionConflictError && error.currentRevision === saved.revision,
    );

    const beforeFailure = await fs.readFile(fixturePath, 'utf8');
    const next = structuredClone(saved.document);
    next.character.player.initialAttributes.strength = 19;
    await assert.rejects(saveGameConstantsContent(fixturePath, saved.revision, next, async () => {
      throw new Error('simulated atomic rename failure');
    }), /simulated atomic rename failure/);
    assert.equal(await fs.readFile(fixturePath, 'utf8'), beforeFailure);
  } finally {
    await fs.rm(fixtureDirectory, { recursive: true, force: true });
  }
});

test('development endpoint validates GET and POST while preserving invalid and stale writes', async () => {
  const fixtureDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'slime-game-constants-endpoint-'));
  const fixturePath = path.join(fixtureDirectory, 'game-constants.json');
  await fs.copyFile(sourcePath, fixturePath);
  const plugin = gameConstantsContentPlugin({ constantsPath: fixturePath });
  assert.equal(typeof plugin.configureServer, 'function');
  assert.equal('configurePreviewServer' in plugin, false);
  const endpointVite = await createServer({
    root: repositoryRoot,
    configFile: false,
    appType: 'custom',
    optimizeDeps: { noDiscovery: true },
    server: { middlewareMode: true, hmr: false },
    plugins: [plugin],
  });
  const httpServer = createHttpServer(endpointVite.middlewares);
  await new Promise((resolve) => httpServer.listen(0, '127.0.0.1', resolve));
  const address = httpServer.address();
  assert.ok(address && typeof address === 'object');
  const endpoint = `http://127.0.0.1:${address.port}/__game-constants`;
  try {
    const getResponse = await fetch(endpoint);
    const initial = await getResponse.json();
    assert.equal(getResponse.status, 200);
    assert.equal(initial.ok, true);
    assert.equal(initial.data.document.character.player.progression.maxLevel, 10);

    const diskBeforeInvalid = await fs.readFile(fixturePath, 'utf8');
    const invalid = structuredClone(initial.data.document);
    invalid.character.player.initialAttributes.strength = -1;
    const invalidResponse = await fetch(endpoint, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ expectedRevision: initial.data.revision, document: invalid }),
    });
    const invalidPayload = await invalidResponse.json();
    assert.equal(invalidResponse.status, 400);
    assert.equal(invalidPayload.ok, false);
    assert.ok(invalidPayload.error.issues.some((issue) => issue.path === 'character.player.initialAttributes.strength'));
    assert.equal(await fs.readFile(fixturePath, 'utf8'), diskBeforeInvalid);

    const changed = structuredClone(initial.data.document);
    changed.character.player.initialAttributes.strength = 18;
    const savedResponse = await fetch(endpoint, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ expectedRevision: initial.data.revision, document: changed }),
    });
    assert.equal(savedResponse.status, 200);
    const diskAfterSave = await fs.readFile(fixturePath, 'utf8');

    const staleResponse = await fetch(endpoint, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ expectedRevision: initial.data.revision, document: initial.data.document }),
    });
    assert.equal(staleResponse.status, 409);
    assert.equal(await fs.readFile(fixturePath, 'utf8'), diskAfterSave);
  } finally {
    await new Promise((resolve, reject) => httpServer.close((error) => error ? reject(error) : resolve()));
    await endpointVite.close();
    await fs.rm(fixtureDirectory, { recursive: true, force: true });
  }
});
