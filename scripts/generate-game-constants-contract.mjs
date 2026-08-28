#!/usr/bin/env node
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { generateGameConstantsContractSources } from './lib/game-constants-contract-generator.mjs';

const repositoryRoot = fileURLToPath(new URL('..', import.meta.url));
const sources = await generateGameConstantsContractSources(repositoryRoot);

for (const [relativePath, content] of Object.entries(sources)) {
  const target = path.join(repositoryRoot, relativePath);
  await mkdir(path.dirname(target), { recursive: true });
  await writeFile(target, content, 'utf8');
}

console.log(`Generated ${Object.keys(sources).length} gameplay-constants contract file(s).`);
