#!/usr/bin/env node
// One-shot maintenance: recompute ledger/UI-descriptor source hashes with the
// line-ending-independent content hash. Run only after reviewing source diffs.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { contentSha256 } from './lib/scene-conversion/contentHash.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const rehash = (relativePath) => contentSha256(readFileSync(path.join(root, relativePath)));

const ledgerPath = path.join(root, 'scripts/migrations/universal-scene-conversion-ledger.json');
const ledger = JSON.parse(readFileSync(ledgerPath, 'utf8'));
let changed = 0;
for (const row of ledger.rows) {
  if (!row.sourceHash || !row.oldSourcePath || !existsSync(path.join(root, row.oldSourcePath))) continue;
  const next = rehash(row.oldSourcePath);
  if (next !== row.sourceHash) { row.sourceHash = next; changed += 1; }
}
writeFileSync(ledgerPath, `${JSON.stringify(ledger, null, 2)}\n`);

const descriptorPath = path.join(root, 'scripts/migrations/ui-extraction-descriptors.json');
let descriptorText = readFileSync(descriptorPath, 'utf8');
for (const surface of JSON.parse(descriptorText).surfaces) {
  const next = rehash(surface.sourcePath);
  if (next === surface.sourceHash) continue;
  // Replace in place so the hand-formatted descriptor file keeps its layout.
  descriptorText = descriptorText.replace(`"sourceHash": "${surface.sourceHash}"`, `"sourceHash": "${next}"`);
  changed += 1;
}
writeFileSync(descriptorPath, descriptorText);
console.log(`Rehashed ${changed} source hashes.`);
