#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { ConversionRunner } from './lib/scene-conversion/ConversionRunner.mjs';
import { validateSceneWriteSet } from './lib/scene-conversion/validate-scene-write-set.mjs';

const repositoryRoot = fileURLToPath(new URL('..', import.meta.url));
const args = process.argv.slice(2);
const familyIndex = args.indexOf('--family');
const family = familyIndex >= 0 ? args[familyIndex + 1] : 'all';
const mode = args.includes('--apply') ? 'apply' : args.includes('--check') ? 'check' : 'dry-run';
const ledger = JSON.parse(await readFile(path.join(repositoryRoot, 'scripts/migrations/universal-scene-conversion-ledger.json'), 'utf8'));
const manifest = JSON.parse(await readFile(path.join(repositoryRoot, 'asset/assets.json'), 'utf8'));
const runner = new ConversionRunner({
  repositoryRoot,
  ledger,
  adapters: {},
  outputRoot: path.join(os.tmpdir(), 'slime-isa-scene-conversion'),
  validateWriteSet: (outputs) => validateSceneWriteSet(outputs, { hasAsset: (assetId) => Object.hasOwn(manifest.assets, assetId) }),
});

try {
  const report = await runner.run({ family, mode });
  console.log(JSON.stringify(report, null, 2));
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
