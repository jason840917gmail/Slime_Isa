import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
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
      const response = await fetch(`${baseUrl}/__character-studio/assets`);
      if (response.ok) return;
    } catch {
      // The server is still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`Fixture Vite did not become ready: ${output}`);
}

async function postJson(baseUrl, requestPath, body) {
  const response = await fetch(`${baseUrl}${requestPath}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { response, payload: await response.json() };
}

test('weapon endpoints expose icon issues and reject before writing files', async () => {
  const fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'slime-weapon-icons-'));
  const weaponRoot = path.join(fixtureRoot, 'weapons');
  const effectRoot = path.join(fixtureRoot, 'effects');
  const assetRoot = path.join(fixtureRoot, 'asset');
  const configPath = path.join(repositoryRoot, `.weapon-icon-${path.basename(fixtureRoot)}.vite.config.ts`);
  const port = await freePort();
  const baseUrl = `http://127.0.0.1:${port}`;
  let child;

  try {
    await fs.mkdir(weaponRoot, { recursive: true });
    await fs.mkdir(effectRoot, { recursive: true });
    await fs.mkdir(assetRoot, { recursive: true });
    await fs.copyFile(path.join(repositoryRoot, 'asset', 'assets.json'), path.join(assetRoot, 'assets.json'));

    const sourceWeaponPath = path.join(repositoryRoot, 'src', 'game', 'content', 'weapons', 'basic-sword');
    const fixtureWeaponPath = path.join(weaponRoot, 'endpoint-fixture');
    await fs.cp(sourceWeaponPath, fixtureWeaponPath, { recursive: true });
    const validWeapon = JSON.parse(await fs.readFile(path.join(fixtureWeaponPath, 'weapon.json'), 'utf8'));
    validWeapon.weaponId = 'endpoint-fixture';
    await fs.writeFile(path.join(fixtureWeaponPath, 'weapon.json'), `${JSON.stringify(validWeapon, null, 2)}\n`);
    const originalFile = await fs.readFile(path.join(fixtureWeaponPath, 'weapon.json'), 'utf8');
    const invalidWeapon = { ...validWeapon, iconKey: 'not-a-weapon-icon', iconFrame: 0 };

    const config = `import { defineConfig } from 'vite';
import { characterContentModulesPlugin } from './src/game/content/characters/characterContentModulesPlugin.ts';

export default defineConfig({
  root: ${JSON.stringify(repositoryRoot.replaceAll('\\', '/'))},
  plugins: [characterContentModulesPlugin({
    characterRoot: ${JSON.stringify(path.join(repositoryRoot, 'src', 'game', 'content', 'characters').replaceAll('\\', '/'))},
    visualRoot: ${JSON.stringify(path.join(repositoryRoot, 'src', 'game', 'content', 'visuals').replaceAll('\\', '/'))},
    weaponRoot: ${JSON.stringify(weaponRoot.replaceAll('\\', '/'))},
    effectRoot: ${JSON.stringify(effectRoot.replaceAll('\\', '/'))},
    assetRoot: ${JSON.stringify(assetRoot.replaceAll('\\', '/'))},
    assetManifestPath: ${JSON.stringify(path.join(assetRoot, 'assets.json').replaceAll('\\', '/'))},
  })],
});
`;
    await fs.writeFile(configPath, config);
    child = spawn(process.execPath, [viteCli, '--config', configPath, '--host', '127.0.0.1', '--port', String(port)], {
      cwd: repositoryRoot,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    await waitForServer(child, baseUrl);

    const saveResult = await postJson(baseUrl, '/__character-studio/weapon/save-package', {
      weapon: invalidWeapon,
      weaponOperation: 'update',
    });
    assert.equal(saveResult.response.status, 400);
    assert.equal(saveResult.payload.error.code, 'validation');
    assert.equal(saveResult.payload.error.issues[0].path, 'weapon.iconKey');
    assert.match(saveResult.payload.error.issues[0].message, /not an available weapon icon/);
    assert.equal(await fs.readFile(path.join(fixtureWeaponPath, 'weapon.json'), 'utf8'), originalFile);

    for (const endpoint of ['/__character-studio/weapon/create', '/__character-studio/weapon/update']) {
      const result = await postJson(baseUrl, endpoint, { weapon: invalidWeapon });
      assert.equal(result.response.status, 400);
      assert.equal(result.payload.error.code, 'validation');
      assert.equal(result.payload.error.issues[0].path, 'weapon.iconKey');
      assert.equal(await fs.readFile(path.join(fixtureWeaponPath, 'weapon.json'), 'utf8'), originalFile);
    }
  } finally {
    if (child) child.kill();
    await fs.rm(configPath, { force: true });
    await fs.rm(fixtureRoot, { recursive: true, force: true });
  }
});
