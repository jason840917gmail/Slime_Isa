import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
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

async function hashDirectory(directory) {
  const names = (await fs.readdir(directory, { withFileTypes: true }))
    .filter((entry) => entry.isFile() && entry.name.endsWith('.map.json'))
    .map((entry) => entry.name)
    .sort();
  const hash = createHash('sha256');
  for (const name of names) hash.update(name).update(await fs.readFile(path.join(directory, name)));
  return hash.digest('hex');
}

async function requestJson(baseUrl, requestPath, init) {
  const response = await fetch(`${baseUrl}${requestPath}`, init);
  const payload = await response.json();
  assert.equal(response.ok, true, `${requestPath} failed: ${JSON.stringify(payload)}`);
  return payload;
}

async function waitForServer(child, baseUrl) {
  let output = '';
  child.stdout.on('data', (chunk) => { output += chunk.toString(); });
  child.stderr.on('data', (chunk) => { output += chunk.toString(); });
  for (let attempt = 0; attempt < 120; attempt += 1) {
    if (child.exitCode !== null) throw new Error(`Fixture Vite exited early (${child.exitCode}): ${output}`);
    try {
      await requestJson(baseUrl, '/__character-studio/assets');
      await requestJson(baseUrl, '/__fixture/roster');
      return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
  }
  throw new Error(`Fixture Vite did not become ready: ${output}`);
}

test('created packages reach the enemy adapter without changing authored maps', async () => {
  const fixtureRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'slime-character-studio-'));
  const characterRoot = path.join(fixtureRoot, 'characters');
  const assetRoot = path.join(fixtureRoot, 'asset');
  const mapsRoot = path.join(repositoryRoot, 'src', 'game', 'content', 'maps');
  const port = await freePort();
  const baseUrl = `http://127.0.0.1:${port}`;
  let child;
  let configPath;

  try {
    await fs.mkdir(characterRoot, { recursive: true });
    await fs.mkdir(path.join(assetRoot, 'characters'), { recursive: true });
    for (const packageId of ['player-slime', 'worm-swordsman', 'worm-archer']) {
      await fs.cp(path.join(repositoryRoot, 'src', 'game', 'content', 'characters', packageId), path.join(characterRoot, packageId), { recursive: true });
    }
    await fs.copyFile(path.join(repositoryRoot, 'asset', 'assets.json'), path.join(assetRoot, 'assets.json'));

    const recoveryAssetId = 'character.player.slime';
    const recoveryCharacterId = 'recovered-raider';
    const recoveryVisualSetId = 'enemy.recovered.raider';
    const recoveryTransactionDirectory = path.join(assetRoot, '.character-studio-create-recovery.tmp');
    const recoveryManifest = JSON.parse(await fs.readFile(path.join(assetRoot, 'assets.json'), 'utf8'));
    const recoveryAsset = recoveryManifest.assets[recoveryAssetId];
    const recoveryCharacter = JSON.parse(await fs.readFile(path.join(characterRoot, 'worm-swordsman', 'character.json'), 'utf8'));
    recoveryCharacter.characterId = recoveryCharacterId;
    recoveryCharacter.displayName = 'Recovered Raider';
    recoveryCharacter.visualSetId = recoveryVisualSetId;
    const recoveryVisualSet = JSON.parse(await fs.readFile(path.join(characterRoot, 'worm-swordsman', 'visual-set.json'), 'utf8'));
    recoveryVisualSet.visualSetId = recoveryVisualSetId;
    recoveryVisualSet.assetId = recoveryAssetId;
    await fs.mkdir(path.join(recoveryTransactionDirectory, 'package'), { recursive: true });
    await fs.writeFile(path.join(recoveryTransactionDirectory, 'transaction.json'), JSON.stringify({
      transactionId: 'fixture-recovery',
      operation: 'create-character',
      assetId: recoveryAssetId,
      sourcePath: recoveryAsset.source.path,
      characterId: recoveryCharacterId,
    }, null, 2));
    await fs.copyFile(path.join(repositoryRoot, 'asset', 'characters', 'slime_normalized.png'), path.join(recoveryTransactionDirectory, 'asset.png'));
    await fs.writeFile(path.join(recoveryTransactionDirectory, 'assets.json'), `${JSON.stringify(recoveryManifest, null, 2)}\n`);
    await fs.writeFile(path.join(recoveryTransactionDirectory, 'package', 'character.json'), `${JSON.stringify(recoveryCharacter, null, 2)}\n`);
    await fs.writeFile(path.join(recoveryTransactionDirectory, 'package', 'visual-set.json'), `${JSON.stringify(recoveryVisualSet, null, 2)}\n`);

    const assetRecoveryId = 'fixture.recovered.asset';
    const assetRecoveryTransactionDirectory = path.join(assetRoot, `.character-studio-asset-${Buffer.from(assetRecoveryId, 'utf8').toString('base64url')}-fixture.tmp`);
    const assetRecoveryManifest = JSON.parse(JSON.stringify(recoveryManifest));
    const assetRecovery = JSON.parse(JSON.stringify(assetRecoveryManifest.assets[recoveryAssetId]));
    assetRecovery.source.path = 'characters/recovered_asset.png';
    assetRecovery.runtime.textureKey = 'fixture-recovered-asset';
    assetRecovery.tags = ['enemy', 'animated'];
    assetRecovery.notes = 'Fixture-only interrupted asset registration';
    assetRecoveryManifest.assets[assetRecoveryId] = assetRecovery;
    assetRecoveryManifest.bundles.boot = [...assetRecoveryManifest.bundles.boot, assetRecoveryId];
    await fs.mkdir(assetRecoveryTransactionDirectory, { recursive: true });
    await fs.writeFile(path.join(assetRecoveryTransactionDirectory, 'transaction.json'), JSON.stringify({
      transactionId: 'fixture-asset-recovery',
      operation: 'asset-register',
      assetId: assetRecoveryId,
      sourcePath: assetRecovery.source.path,
    }, null, 2));
    await fs.copyFile(path.join(repositoryRoot, 'asset', 'characters', 'slime_normalized.png'), path.join(assetRecoveryTransactionDirectory, 'asset.png'));
    await fs.writeFile(path.join(assetRecoveryTransactionDirectory, 'assets.json'), `${JSON.stringify(assetRecoveryManifest, null, 2)}\n`);

    const pluginPath = './src/game/content/characters/characterContentModulesPlugin.ts';
    const fixtureConfig = `import { defineConfig } from 'vite';
import { characterContentModulesPlugin } from ${JSON.stringify(pluginPath)};

const rosterPlugin = {
  name: 'character-studio-fixture-roster',
  configureServer(server) {
    server.middlewares.use('/__fixture/roster', async (_request, response) => {
      try {
        server.moduleGraph.invalidateAll();
        const module = await server.ssrLoadModule('src/game/enemies/library/EnemyTypes.ts');
        const catalog = await server.ssrLoadModule('virtual-character-content');
        const geometry = await server.ssrLoadModule('src/game/features/characters/characterHitboxGeometry.ts');
        const hitboxRuntime = await server.ssrLoadModule('src/game/features/characters/CharacterHitboxController.ts');
        const enemyAI = await server.ssrLoadModule('src/game/enemies/EnemyAI.ts');
        const enemyLifecycle = await server.ssrLoadModule('src/game/enemies/enemyCombatLifecycle.ts');
        const probe = geometry.resolveCharacterHitboxRectangle(
          { width: 20, height: 10, offsetX: 24, offsetY: -3, mirrorX: true },
          { x: 100, y: 80 },
          -1,
        );
        const hitboxHits = [];
        const hitboxController = new hitboxRuntime.CharacterHitboxController(
          { hitboxes: { strike: { width: 20, height: 10, offsetX: 24, offsetY: -3, mirrorX: true } } },
          {
            anchor: { x: 100, y: 80 },
            facingX: () => -1,
            targets: [{ getBounds: () => ({ x: 68, y: 74, width: 10, height: 10 }) }],
            onHit: (hitboxId, _target, activationId) => hitboxHits.push({ hitboxId, activationId }),
          },
        );
        hitboxController.activate('strike', 'fixture-activation');
        hitboxController.update();
        hitboxController.update();
        const activeHitboxesBeforeDeactivate = hitboxController.getResolvedHitboxes().length;
        hitboxController.deactivate('strike');
        const movementVelocities = [];
        const fakeBody = { velocity: { scale: () => {} }, setVelocity: (x, y) => movementVelocities.push({ x, y }) };
        const direction = (x, y) => ({ x, y, clone: () => direction(x, y) });
        const enemyAIConfig = {
          aggroRange: 220,
          attackRange: 50,
          wanderSpeed: 28,
          chaseSpeed: 80,
          attackCooldownMs: 1500,
          attackWindupMs: 400,
          attackRecoveryMs: 400,
          contactDamage: 37,
          knockbackStrength: 260,
          isRanged: false,
          knockbackResist: 0.45,
        };
        const stateContext = {
          enemy: { x: 0, y: 0, body: fakeBody },
          player: { x: 100, y: 0 },
          time: 0,
          delta: 16,
          distToPlayer: 100,
          dirToPlayer: direction(1, 0),
          config: enemyAIConfig,
        };
        const requestedAttacks = [];
        const idleToChase = enemyAI.runState('idle', stateContext);
        const chaseMovement = enemyAI.runState('chase', { ...stateContext, distToPlayer: 100 });
        const chaseVelocity = movementVelocities.at(-1);
        const chaseToAttack = enemyAI.runState('chase', { ...stateContext, distToPlayer: 40 });
        const attackResult = enemyAI.runState('attack', {
          ...stateContext,
          distToPlayer: 40,
          requestAttack: (nextDirection) => requestedAttacks.push(nextDirection),
        });
        const initialAttackState = { active: false, readyAt: 0, sequenceId: 0 };
        const attackStart = enemyLifecycle.tryBeginEnemyAttack(initialAttackState, 0, 1500);
        const blockedAttackStart = enemyLifecycle.tryBeginEnemyAttack(attackStart.state, 500, 1500);
        const attackDamage = enemyLifecycle.applyEnemyDamage(22, 90, 100);
        response.statusCode = 200;
        response.setHeader('Content-Type', 'application/json; charset=utf-8');
        response.end(JSON.stringify({
          enemyIds: Object.keys(module.ENEMY_CONFIGS),
          characterIds: catalog.characterPackages.map((entry) => entry.characterId),
          primaryIds: catalog.characterPackages.filter((entry) => entry.character.runtimeRole === 'primary-player').map((entry) => entry.characterId),
          hitboxProbe: {
            rectangle: probe,
            overlaps: geometry.characterHitboxesIntersect(probe, { x: 70, y: 70, width: 20, height: 20 }),
            edgeTouchingOverlaps: geometry.characterHitboxesIntersect(probe, { x: 70, y: 57, width: 20, height: 15 }),
          },
          hitboxControllerProbe: {
            hits: hitboxHits,
            activeHitboxesBeforeDeactivate,
            activeHitboxesAfterDeactivate: hitboxController.getResolvedHitboxes().length,
          },
          enemyRuntimeProbe: {
            idleToChase,
            chaseMovement,
            chaseToAttack,
            attackResult,
            movementVelocity: chaseVelocity,
            requestedAttack: requestedAttacks[0],
            attackStart,
            blockedAttackStart,
            attackDamage,
            attackCanResolve: enemyLifecycle.canResolveEnemyAttack(attackStart.state, attackStart.sequenceId),
            attackAfterFinish: enemyLifecycle.finishEnemyAttack(attackStart.state, attackStart.sequenceId),
            attackAfterCancel: enemyLifecycle.cancelEnemyAttack(attackStart.state),
          },
          fixtureEnemy: module.ENEMY_CONFIGS['fixture-raider']
            ? {
              maxHp: module.ENEMY_CONFIGS['fixture-raider'].maxHp,
              body: module.ENEMY_CONFIGS['fixture-raider'].body,
              ai: module.ENEMY_CONFIGS['fixture-raider'].ai,
            }
            : undefined,
        }));
      } catch (error) {
        response.statusCode = 500;
        response.end(JSON.stringify({ error: error instanceof Error ? error.message : String(error) }));
      }
    });
  },
};

export default defineConfig({
  root: ${JSON.stringify(repositoryRoot.replaceAll('\\', '/'))},
  plugins: [characterContentModulesPlugin({
    characterRoot: ${JSON.stringify(characterRoot.replaceAll('\\', '/'))},
    visualRoot: ${JSON.stringify(characterRoot.replaceAll('\\', '/'))},
    assetRoot: ${JSON.stringify(assetRoot.replaceAll('\\', '/'))},
    assetManifestPath: ${JSON.stringify(path.join(assetRoot, 'assets.json').replaceAll('\\', '/'))},
  }), rosterPlugin],
});
`;
    configPath = path.join(repositoryRoot, '.character-studio-fixture.vite.config.ts');
    await fs.writeFile(configPath, fixtureConfig, 'utf8');
    child = spawn(process.execPath, [viteCli, '--config', configPath, '--host', '127.0.0.1', '--port', String(port)], {
      cwd: repositoryRoot,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    await waitForServer(child, baseUrl);

    const mapsBefore = await hashDirectory(mapsRoot);
    const initial = await requestJson(baseUrl, '/__fixture/roster');
    assert.deepEqual(initial.primaryIds, ['player-slime']);
    assert.deepEqual(initial.enemyIds.sort(), ['recovered-raider', 'worm-archer', 'worm-swordsman']);
    const recoveredPackage = await requestJson(baseUrl, `/__character-studio/package/${recoveryCharacterId}`);
    assert.equal(recoveredPackage.data.character.characterId, recoveryCharacterId);
    assert.equal(recoveredPackage.data.visualSet.assetId, recoveryAssetId);
    assert.equal(await fs.access(path.join(assetRoot, recoveryAsset.source.path)).then(() => true).catch(() => false), true);
    assert.equal(await fs.access(recoveryTransactionDirectory).then(() => true).catch(() => false), false);
    const recoveredAssetCatalog = await requestJson(baseUrl, '/__character-studio/assets');
    assert.equal(recoveredAssetCatalog.data.assets.some((entry) => entry.assetId === assetRecoveryId), true);
    assert.equal(await fs.access(path.join(assetRoot, assetRecovery.source.path)).then(() => true).catch(() => false), true);
    assert.equal(await fs.access(assetRecoveryTransactionDirectory).then(() => true).catch(() => false), false);
    assert.deepEqual(initial.hitboxProbe.rectangle, { x: 66, y: 72, width: 20, height: 10 });
    assert.equal(initial.hitboxProbe.overlaps, true);
    assert.equal(initial.hitboxProbe.edgeTouchingOverlaps, false);
    assert.deepEqual(initial.hitboxControllerProbe.hits, [{ hitboxId: 'strike', activationId: 'fixture-activation' }]);
    assert.equal(initial.hitboxControllerProbe.activeHitboxesBeforeDeactivate, 1);
    assert.equal(initial.hitboxControllerProbe.activeHitboxesAfterDeactivate, 0);
    assert.equal(initial.enemyRuntimeProbe.idleToChase, 'chase');
    assert.equal(initial.enemyRuntimeProbe.chaseMovement, 'continue');
    assert.equal(initial.enemyRuntimeProbe.chaseToAttack, 'attack');
    assert.equal(initial.enemyRuntimeProbe.attackResult, 'continue');
    assert.deepEqual(initial.enemyRuntimeProbe.movementVelocity, { x: 80, y: 0 });
    assert.deepEqual(initial.enemyRuntimeProbe.requestedAttack, { x: 1, y: 0 });
    assert.equal(initial.enemyRuntimeProbe.attackStart.started, true);
    assert.equal(initial.enemyRuntimeProbe.blockedAttackStart.started, false);
    assert.deepEqual(initial.enemyRuntimeProbe.attackDamage, { hp: 0, actualDamage: 22, defeated: true });
    assert.equal(initial.enemyRuntimeProbe.attackCanResolve, true);
    assert.equal(initial.enemyRuntimeProbe.attackAfterFinish.active, false);
    assert.equal(initial.enemyRuntimeProbe.attackAfterCancel.sequenceId, 2);

    const createHeaders = { 'Content-Type': 'application/json' };
    const playerResponse = await requestJson(baseUrl, '/__character-studio/package/create', {
      method: 'POST',
      headers: createHeaders,
      body: JSON.stringify({ characterId: 'fixture-player', displayName: 'Fixture Player', kind: 'player', template: 'player', assetId: 'character.player.slime' }),
    });
    assert.equal(playerResponse.data.characterId, 'fixture-player');

    const enemyResponse = await requestJson(baseUrl, '/__character-studio/package/create', {
      method: 'POST',
      headers: createHeaders,
      body: JSON.stringify({ characterId: 'fixture-raider', displayName: 'Fixture Raider', kind: 'enemy', template: 'melee-enemy', assetId: 'character.player.slime' }),
    });
    assert.equal(enemyResponse.data.characterId, 'fixture-raider');

    const reloaded = await requestJson(baseUrl, '/__fixture/roster');
    assert.equal(reloaded.characterIds.includes('fixture-player'), true);
    assert.equal(reloaded.enemyIds.includes('fixture-raider'), true);
    assert.deepEqual(reloaded.primaryIds, ['player-slime']);
    assert.equal(reloaded.fixtureEnemy.maxHp > 0, true);
    assert.equal(reloaded.fixtureEnemy.ai.isRanged, false);
    assert.notEqual(reloaded.fixtureEnemy.ai.isLeaper, true);
    assert.equal(reloaded.fixtureEnemy.ai.attackWindupMs > 0, true);
    assert.equal(reloaded.fixtureEnemy.body.width > 0, true);

    const createdPlayer = JSON.parse(await fs.readFile(path.join(characterRoot, 'fixture-player', 'character.json'), 'utf8'));
    const createdPlayerVisual = JSON.parse(await fs.readFile(path.join(characterRoot, 'fixture-player', 'visual-set.json'), 'utf8'));
    const createdEnemy = JSON.parse(await fs.readFile(path.join(characterRoot, 'fixture-raider', 'character.json'), 'utf8'));
    const createdEnemyVisual = JSON.parse(await fs.readFile(path.join(characterRoot, 'fixture-raider', 'visual-set.json'), 'utf8'));
    for (const visualSet of [createdPlayerVisual, createdEnemyVisual]) {
      for (const clip of Object.values(visualSet.clips)) assert.deepEqual(clip.frames, [0]);
    }
    assert.deepEqual(Object.keys(createdPlayer.animationTracks).sort(), Object.keys(createdPlayerVisual.clips).sort());
    assert.deepEqual(Object.keys(createdEnemy.animationTracks).sort(), Object.keys(createdEnemyVisual.clips).sort());
    for (const clipId of ['idle-side', 'walk-side', 'attack-side', 'knockback-side', 'die-side', 'idle-up', 'walk-up', 'attack-up', 'knockback-up', 'die-up', 'idle-down', 'walk-down', 'attack-down', 'knockback-down', 'die-down']) {
      assert.deepEqual(createdEnemyVisual.clips[clipId].frames, [0]);
    }
    assert.equal(await hashDirectory(mapsRoot), mapsBefore);
    assert.equal((await fs.readFile(path.join(characterRoot, 'fixture-raider', 'character.json'), 'utf8')).includes('Fixture Raider'), true);
  } finally {
    if (child) child.kill();
    if (configPath) await fs.rm(configPath, { force: true });
    await fs.rm(fixtureRoot, { recursive: true, force: true });
  }
});
