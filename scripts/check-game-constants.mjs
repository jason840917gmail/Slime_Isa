#!/usr/bin/env node
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const root = fileURLToPath(new URL('..', import.meta.url));

async function loadTypeScriptModule(entryPoint) {
  const result = await build({ absWorkingDir: root, entryPoints: [entryPoint], bundle: true, format: 'esm', platform: 'node', write: false });
  return import(`data:text/javascript;base64,${Buffer.from(result.outputFiles[0].text).toString('base64')}`);
}

const constants = JSON.parse(readFileSync(join(root, 'src', 'game', 'content', 'game-constants.json'), 'utf8'));
const items = JSON.parse(readFileSync(join(root, 'src', 'game', 'content', 'items', 'items.json'), 'utf8'));
const primaryPlayer = JSON.parse(readFileSync(join(root, 'src', 'game', 'content', 'characters', 'player-slime', 'character.json'), 'utf8'));
const { validateGameConstants } = await loadTypeScriptModule('src/game/content/GameConstantsValidation.ts');
const errors = validateGameConstants(constants).map((entry) => `${entry.path}: ${entry.message}`);
const itemIds = Object.keys(items).sort();
const configuredIds = Object.keys(constants.inventory?.maxStackByItem ?? {}).sort();

for (const itemId of itemIds) {
  if (!configuredIds.includes(itemId)) errors.push(`inventory.maxStackByItem.${itemId}: missing configured base item`);
  if (items[itemId]?.id !== itemId) errors.push(`items.${itemId}.id: must match its catalog key`);
}
for (const itemId of configuredIds) {
  if (!itemIds.includes(itemId)) errors.push(`inventory.maxStackByItem.${itemId}: does not match a base item`);
}

if (primaryPlayer.attributes !== undefined) errors.push('characters.player-slime.attributes: primary-player attributes belong in game-constants.json');
if (primaryPlayer.player?.movement !== undefined) errors.push('characters.player-slime.player.movement: primary-player movement belongs in game-constants.json');
if (primaryPlayer.player?.progression !== undefined) errors.push('characters.player-slime.player.progression: primary-player progression belongs in game-constants.json');

function sourceFiles(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? sourceFiles(path) : entry.isFile() && path.endsWith('.ts') ? [path] : [];
  });
}

for (const path of sourceFiles(join(root, 'src'))) {
  if (path.endsWith(join('src', 'game', 'Constant.ts'))) continue;
  const source = readFileSync(path, 'utf8');
  if (/from\s+['"][^'"]*game-constants\.json['"]/.test(source)) {
    errors.push(`${path.slice(root.length + 1)}: import GAME_CONSTANTS through src/game/Constant.ts`);
  }
}

if (errors.length > 0) {
  console.error(`constants:check failed with ${errors.length} error(s):`);
  errors.forEach((error) => console.error(`  - ${error}`));
  process.exit(1);
}

console.log(`constants:check OK - ${itemIds.length} base item(s), ${constants.character.player.progression.maxLevel} level(s).`);
