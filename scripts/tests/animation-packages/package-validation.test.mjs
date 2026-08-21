import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import os from 'node:os';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { build } from 'esbuild';

const repoRoot = process.cwd();
const validationEntry = path.join(repoRoot, 'src', 'game', 'content', 'animations', 'validation.ts');

async function loadValidation() {
  const result = await build({
    absWorkingDir: repoRoot,
    entryPoints: [validationEntry],
    bundle: true,
    format: 'esm',
    platform: 'node',
    write: false,
  });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

async function loadDiscovery() {
  const result = await build({
    absWorkingDir: repoRoot,
    entryPoints: [path.join(repoRoot, 'src', 'game', 'content', 'animations', 'animationContentModulesPlugin.ts')],
    bundle: true,
    format: 'esm',
    platform: 'node',
    write: false,
  });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

const validPackage = {
  $schema: './animation-package.schema.json',
  version: 1,
  animationId: 'weapon.player.test-idle',
  displayName: 'Test idle',
  description: 'A package validation fixture.',
  animation: {
    version: 2,
    durationSeconds: 0.2,
    framesPerSecond: 8,
    loop: true,
    loopMode: 'wrap',
    layers: [{
      layerId: 'base',
      displayName: 'Base',
      assetId: 'sheet.trees.8x6',
      depthOffset: 0,
      blocks: [{ from: 0, through: 1, sourceFrame: 0 }],
    }],
  },
};

test('validates a shared animation package', async () => {
  const { validateAnimationPackage } = await loadValidation();
  assert.deepEqual(validateAnimationPackage(validPackage), []);
});

test('reports package metadata and version errors', async () => {
  const { validateAnimationPackage } = await loadValidation();
  const issues = validateAnimationPackage({ ...validPackage, version: 2, description: '' });
  assert.ok(issues.some((issue) => issue.field === 'package.version'));
  assert.ok(issues.some((issue) => issue.field === 'package.description'));
});

test('reports unknown animation assets with a typed diagnostic', async () => {
  const { validateAnimationPackage } = await loadValidation();
  const issues = validateAnimationPackage({
    ...validPackage,
    animation: { ...validPackage.animation, layers: [{ ...validPackage.animation.layers[0], assetId: 'missing.asset' }] },
  });
  assert.ok(issues.some((issue) => issue.code === 'animation-asset-invalid'));
});

test('rejects animation packages without visual layers', async () => {
  const { validateAnimationPackage } = await loadValidation();
  const issues = validateAnimationPackage({ ...validPackage, animation: { ...validPackage.animation, layers: [] } });
  assert.ok(issues.some((issue) => issue.field === 'package.animation.layers'));
});

test('discovers nested packages and rejects duplicate IDs', async () => {
  const { discoverPackages } = await loadDiscovery();
  const root = await mkdtemp(path.join(os.tmpdir(), 'slime-animation-catalog-'));
  try {
    const packagePath = path.join(root, 'weapons', 'nested', 'animation.json');
    await mkdir(path.dirname(packagePath), { recursive: true });
    await writeFile(packagePath, JSON.stringify(validPackage));
    const discovered = await discoverPackages(root);
    assert.equal(discovered.length, 1);
    assert.equal(discovered[0].relativePath, 'weapons/nested/animation.json');

    const duplicatePath = path.join(root, 'objects', 'duplicate', 'animation.json');
    await mkdir(path.dirname(duplicatePath), { recursive: true });
    await writeFile(duplicatePath, JSON.stringify(validPackage));
    await assert.rejects(() => discoverPackages(root), /animationId.*duplicates/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('rejects unsafe package folders during discovery', async () => {
  const { discoverPackages } = await loadDiscovery();
  const root = await mkdtemp(path.join(os.tmpdir(), 'slime-animation-unsafe-'));
  try {
    const packagePath = path.join(root, 'Unsafe Folder', 'animation.json');
    await mkdir(path.dirname(packagePath), { recursive: true });
    await writeFile(packagePath, JSON.stringify(validPackage));
    await assert.rejects(() => discoverPackages(root), /lowercase kebab-case/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('moves packages transactionally and rewrites their relative schema path', async () => {
  const { applyAnimationLibraryTransaction, readCatalog } = await loadDiscovery();
  const contentRoot = await mkdtemp(path.join(os.tmpdir(), 'slime-animation-transaction-'));
  const root = path.join(contentRoot, 'animations');
  try {
    const sourcePath = path.join(root, 'weapons', 'test', 'animation.json');
    await mkdir(path.dirname(sourcePath), { recursive: true });
    await writeFile(sourcePath, JSON.stringify(validPackage));
    const catalog = await readCatalog(root);
    const source = catalog.packages[0];
    const destination = 'objects/nested/test/animation.json';
    const result = await applyAnimationLibraryTransaction(root, {
      expectedCatalogRevision: catalog.revision,
      writes: [{ packagePath: destination, operation: 'create', package: validPackage }],
      deletes: [{ packagePath: source.packagePath, expectedRevision: source.revision }],
    });
    assert.equal(result.catalog.packages[0].packagePath, destination);
    assert.equal(result.catalog.packages[0].$schema, '../../../animation-package.schema.json');
    await assert.rejects(() => readFile(sourcePath, 'utf8'));
  } finally {
    await rm(contentRoot, { recursive: true, force: true });
  }
});

test('blocks deletion when a weapon still references the animation ID', async () => {
  const { applyAnimationLibraryTransaction, readCatalog } = await loadDiscovery();
  const contentRoot = await mkdtemp(path.join(os.tmpdir(), 'slime-animation-reference-'));
  const root = path.join(contentRoot, 'animations');
  try {
    const packagePath = path.join(root, 'weapons', 'test', 'animation.json');
    await mkdir(path.dirname(packagePath), { recursive: true });
    await writeFile(packagePath, JSON.stringify(validPackage));
    const weaponPath = path.join(contentRoot, 'weapons', 'fixture', 'weapon.json');
    await mkdir(path.dirname(weaponPath), { recursive: true });
    await writeFile(weaponPath, JSON.stringify({
      weaponId: 'fixture',
      animations: { idleAnimationId: validPackage.animationId },
      directionalAttacks: {},
    }));
    const catalog = await readCatalog(root);
    await assert.rejects(() => applyAnimationLibraryTransaction(root, {
      deletes: [{ packagePath: catalog.packages[0].packagePath, expectedRevision: catalog.packages[0].revision }],
    }), /still references/);
    assert.equal(JSON.parse(await readFile(packagePath, 'utf8')).animationId, validPackage.animationId);
  } finally {
    await rm(contentRoot, { recursive: true, force: true });
  }
});

test('validates a whole batch before replacing any package', async () => {
  const { applyAnimationLibraryTransaction, readCatalog } = await loadDiscovery();
  const contentRoot = await mkdtemp(path.join(os.tmpdir(), 'slime-animation-batch-'));
  const root = path.join(contentRoot, 'animations');
  try {
    const packagePath = path.join(root, 'weapons', 'test', 'animation.json');
    await mkdir(path.dirname(packagePath), { recursive: true });
    await writeFile(packagePath, JSON.stringify(validPackage));
    const catalog = await readCatalog(root);
    await assert.rejects(() => applyAnimationLibraryTransaction(root, {
      writes: [
        { packagePath: catalog.packages[0].packagePath, operation: 'update', expectedRevision: catalog.packages[0].revision, package: { ...validPackage, displayName: 'Changed' } },
        { packagePath: 'objects/invalid/animation.json', operation: 'create', package: { ...validPackage, animationId: 'INVALID' } },
      ],
    }));
    assert.equal(JSON.parse(await readFile(packagePath, 'utf8')).displayName, validPackage.displayName);
  } finally {
    await rm(contentRoot, { recursive: true, force: true });
  }
});
