import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { promises as fs } from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const viteCli = path.join(repositoryRoot, 'node_modules', 'vite', 'bin', 'vite.js');

async function freePort() {
  const server = net.createServer();
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : undefined;
  await new Promise((resolve) => server.close(resolve));
  if (!port) throw new Error('Could not reserve a fixture port');
  return port;
}

async function waitForServer(child, baseUrl) {
  let output = '';
  child.stdout.on('data', (chunk) => { output += chunk.toString(); });
  child.stderr.on('data', (chunk) => { output += chunk.toString(); });
  for (let attempt = 0; attempt < 120; attempt += 1) {
    if (child.exitCode !== null) throw new Error(`Fixture Vite exited early (${child.exitCode}): ${output}`);
    try {
      const response = await fetch(`${baseUrl}/__map-editor/object-gameplay/update`);
      if (response.status === 405) return;
    } catch {
      // The server is still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`Fixture Vite did not become ready: ${output}`);
}

async function postGameplay(baseUrl, payload) {
  const response = await fetch(`${baseUrl}/__map-editor/object-gameplay/update`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  return { response, payload: await response.json() };
}

test('map gameplay saves enforce the current resource catalog before writing', async () => {
  const fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'slime-map-gameplay-'));
  const objectRoot = path.join(fixtureRoot, 'objects');
  const gameConstantsPath = path.join(fixtureRoot, 'game-constants.json');
  const configPath = path.join(repositoryRoot, `.map-gameplay-${path.basename(fixtureRoot)}.vite.config.ts`);
  const port = await freePort();
  const baseUrl = `http://127.0.0.1:${port}`;
  let child;

  try {
    await fs.cp(path.join(repositoryRoot, 'src', 'game', 'content', 'objects'), objectRoot, { recursive: true });
    await fs.copyFile(path.join(repositoryRoot, 'src', 'game', 'content', 'game-constants.json'), gameConstantsPath);
    const objectPath = path.join(objectRoot, 'resources', 'resource-stone-node.json');
    const originalDocument = JSON.parse(await fs.readFile(objectPath, 'utf8'));
    const originalFile = await fs.readFile(objectPath, 'utf8');
    const basePayload = { objectId: originalDocument.objectId, resourceNode: originalDocument.resourceNode };

    const config = `import { defineConfig } from 'vite';
import { mapEditorSavePlugin } from './vite.config.ts';

export default defineConfig({
  root: ${JSON.stringify(repositoryRoot.replaceAll('\\', '/'))},
  plugins: [mapEditorSavePlugin({
    objectDefinitionRoot: ${JSON.stringify(objectRoot.replaceAll('\\', '/'))},
    gameConstantsPath: ${JSON.stringify(gameConstantsPath.replaceAll('\\', '/'))},
  })],
});
`;
    await fs.writeFile(configPath, config);
    child = spawn(process.execPath, [viteCli, '--config', configPath, '--host', '127.0.0.1', '--port', String(port)], {
      cwd: repositoryRoot,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    await waitForServer(child, baseUrl);

    const unknownResult = await postGameplay(baseUrl, {
      ...basePayload,
      resourceNode: { ...basePayload.resourceNode, harvestRequirement: { targetTag: 'crystal', minimumTier: 1, failureMessage: 'No crystal tool' } },
    });
    assert.equal(unknownResult.response.status, 400);
    assert.match(unknownResult.payload.error, /Unknown resource tag 'crystal'/);
    assert.equal(await fs.readFile(objectPath, 'utf8'), originalFile);

    const configuredResult = await postGameplay(baseUrl, {
      ...basePayload,
      resourceNode: { ...basePayload.resourceNode, harvestRequirement: { targetTag: 'iron', minimumTier: 2, failureMessage: 'Requires iron' } },
    });
    assert.equal(configuredResult.response.status, 200);
    assert.equal(JSON.parse(await fs.readFile(objectPath, 'utf8')).resourceNode.harvestRequirement.targetTag, 'iron');

    const noRequirement = { ...basePayload.resourceNode };
    delete noRequirement.harvestRequirement;
    const removalResult = await postGameplay(baseUrl, { ...basePayload, resourceNode: noRequirement });
    assert.equal(removalResult.response.status, 200);
    assert.equal(Object.hasOwn(JSON.parse(await fs.readFile(objectPath, 'utf8')).resourceNode, 'harvestRequirement'), false);
    const fileWithoutRequirement = await fs.readFile(objectPath, 'utf8');

    const constants = JSON.parse(await fs.readFile(gameConstantsPath, 'utf8'));
    constants.resources.tags = constants.resources.tags.filter((tag) => tag !== 'iron');
    await fs.writeFile(gameConstantsPath, `${JSON.stringify(constants, null, 2)}\n`);
    const staleResult = await postGameplay(baseUrl, {
      ...basePayload,
      resourceNode: { ...basePayload.resourceNode, harvestRequirement: { targetTag: 'iron', minimumTier: 1, failureMessage: 'Stale client' } },
    });
    assert.equal(staleResult.response.status, 400);
    assert.equal(await fs.readFile(objectPath, 'utf8'), fileWithoutRequirement);
  } finally {
    if (child) child.kill();
    await fs.rm(configPath, { force: true });
    await fs.rm(fixtureRoot, { recursive: true, force: true });
  }
});