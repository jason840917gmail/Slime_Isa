#!/usr/bin/env node
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  bakeProductionMap,
  getProductionMapIds,
} from './lib/procedural-map-generator.mjs';

const repoRoot = fileURLToPath(new URL('..', import.meta.url));
const mapsDirectory = join(repoRoot, 'src', 'game', 'content', 'maps');
mkdirSync(mapsDirectory, { recursive: true });

for (const mapId of getProductionMapIds()) {
  const filePath = join(mapsDirectory, `${mapId}.map.json`);
  const map = bakeProductionMap(mapId);
  writeFileSync(filePath, `${JSON.stringify(map, null, 2)}\n`, 'utf8');
  console.log(`Baked ${mapId} -> ${filePath}`);
}

