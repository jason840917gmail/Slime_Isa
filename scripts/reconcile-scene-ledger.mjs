#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const ledgerPath = path.join(root, 'scripts/migrations/universal-scene-conversion-ledger.json');
const ledger = JSON.parse(readFileSync(ledgerPath, 'utf8'));
const result = spawnSync(process.execPath, [path.join(root, 'scripts/convert-scenes.mjs'), '--include-scene-owned'], {
  cwd: root,
  encoding: 'utf8',
  maxBuffer: 16 * 1024 * 1024,
});
if (result.status !== 0) throw new Error(result.stderr || result.stdout || 'Scene conversion check failed');
const report = JSON.parse(result.stdout);
const grouped = new Map();
for (const output of report.outputs) {
  const current = grouped.get(output.unitKey) ?? [];
  current.push(output);
  grouped.set(output.unitKey, current);
}

const rows = ledger.rows.map((row) => {
  const outputs = grouped.get(row.key);
  if (!outputs) {
    if (row.writerState === 'scene' && row.classification === 'convert') throw new Error(`Scene-owned row '${row.key}' has no conversion output`);
    return row;
  }
  const paths = outputs.map((output) => {
    const relativePath = `src/game/content/scenes/authored/${output.path}`;
    const bytes = readFileSync(path.join(root, relativePath));
    const sha256 = createHash('sha256').update(bytes).digest('hex');
    if (row.writerState !== 'scene' && sha256 !== output.sha256) {
      throw new Error(`Legacy-owned conversion output changed at '${relativePath}'`);
    }
    return { path: relativePath, sha256, bytes: bytes.length };
  }).sort((a, b) => a.path.localeCompare(b.path));
  const consumedFieldPaths = [...new Set(outputs.flatMap((output) => output.consumedFieldPaths))].sort();
  const retained = new Map(outputs.flatMap((output) => output.intentionallyRetainedFields)
    .map((entry) => [`${entry.path}\0${entry.owner}`, entry]));
  const intentionallyRetainedFields = [...retained.values()].sort((a, b) => a.path.localeCompare(b.path) || a.owner.localeCompare(b.owner));
  return { ...row, outputs: paths, consumedFieldPaths, intentionallyRetainedFields };
});
const expected = `${JSON.stringify({ ...ledger, rows }, null, 2)}\n`;
const migrationView = (document) => ({ ...document, rows: document.rows.map((row) => row.writerState === 'scene'
  ? { ...row, outputs: row.outputs.map(({ path: outputPath }) => ({ path: outputPath })) }
  : row) });
if (process.argv.includes('--write')) {
  writeFileSync(ledgerPath, expected);
  console.log(`Reconciled ${grouped.size} scene conversion rows without changing source hashes or writer states.`);
} else if (JSON.stringify(migrationView(ledger)) !== JSON.stringify(migrationView({ ...ledger, rows }))) {
  throw new Error('Conversion ledger output metadata is stale; run node scripts/reconcile-scene-ledger.mjs --write');
} else {
  console.log(`Scene conversion ledger matches ${grouped.size} checked units.`);
}
