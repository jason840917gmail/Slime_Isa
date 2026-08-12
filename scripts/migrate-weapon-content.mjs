#!/usr/bin/env node
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { isDeepStrictEqual } from 'node:util';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const weaponRoot = path.join(repositoryRoot, 'src', 'game', 'content', 'weapons');
const effectRoot = path.join(repositoryRoot, 'src', 'game', 'content', 'effects');
const writeChanges = process.argv.includes('--write');
if (!writeChanges && !process.argv.includes('--check')) {
  console.error('Usage: node scripts/migrate-weapon-content.mjs --check | --write');
  process.exit(2);
}

const bundle = await build({
  absWorkingDir: repositoryRoot,
  entryPoints: ['src/game/content/weapons/migrateLegacyWeapon.ts'],
  bundle: true,
  format: 'esm',
  platform: 'node',
  write: false,
});
const migration = await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`);

function rotateAnimation(animation, rotationDeg) {
  return {
    ...structuredClone(animation),
    loop: false,
    layers: animation.layers.map((layer) => ({
      ...layer,
      blocks: layer.blocks.map((block) => ({
        ...block,
        transform: { ...(block.transform ?? {}), rotationDeg: (block.transform?.rotationDeg ?? 0) + rotationDeg },
      })),
    })),
  };
}

function basicSwordImpact(source) {
  if (source.weaponId !== 'basic-sword' || !source.assetId || !source.animations?.impact) return undefined;
  const right = migration.migrateLegacyAnimation(source, source.animations.impact, 'impact', true);
  return {
    $schema: '../effect.schema.json',
    version: 1,
    effectId: 'basic-sword-impact',
    displayName: 'Basic Sword impact',
    mirrorLeftFromRight: true,
    directions: { right, up: rotateAnimation(right, -90), down: rotateAnimation(right, 90) },
  };
}

const weaponDirectories = ['basic-sword', 'goo-gauntlet', 'slam-hammer'];
const changes = [];
for (const directory of weaponDirectories) {
  const file = path.join(weaponRoot, directory, 'weapon.json');
  const source = JSON.parse(await readFile(file, 'utf8'));
  if (source.version !== 1) continue;
  const impact = basicSwordImpact(source);
  const migrated = {
    $schema: '../weapon.schema.json',
    ...migration.migrateLegacyWeaponDefinition(source, impact ? { onHitEffectId: impact.effectId } : {}),
  };
  if (!isDeepStrictEqual(source, migrated)) {
    changes.push(path.relative(repositoryRoot, file));
    if (writeChanges) await writeFile(file, `${JSON.stringify(migrated, null, 2)}\n`, 'utf8');
  }
  if (impact) {
    const effectDirectory = path.join(effectRoot, impact.effectId);
    const effectFile = path.join(effectDirectory, 'effect.json');
    let current;
    try { current = JSON.parse(await readFile(effectFile, 'utf8')); } catch { /* new effect */ }
    if (!isDeepStrictEqual(current, impact)) {
      changes.push(path.relative(repositoryRoot, effectFile));
      if (writeChanges) {
        await mkdir(effectDirectory, { recursive: true });
        await writeFile(effectFile, `${JSON.stringify(impact, null, 2)}\n`, 'utf8');
      }
    }
  }
}

if (changes.length === 0) console.log('weapon migration: content is already current');
else console.log(`weapon migration: ${writeChanges ? 'wrote' : 'would write'}\n  - ${changes.join('\n  - ')}`);
