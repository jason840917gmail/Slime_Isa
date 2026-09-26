#!/usr/bin/env node

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const REPOSITORY_ROOT = fileURLToPath(new URL('..', import.meta.url));

const APPROVED_LEGACY_CONSTRUCTORS = new Map();
const LEGACY_CONSTRUCTORS = ['LegacyWorldAdapter', 'ObjectFactory', 'NpcActor', 'Enemy', 'PlayerFactory'];
const RETIRED_EDITOR_IMPORT = /\b(?:from\s*['"][^'"]*\/(?:CharacterStudio|AnimationStudio|WeaponStudio|ProjectileStudio|MapEditor(?:LoadScene|Scene))['"]|import\(['"][^'"]*\/(?:CharacterStudio|AnimationStudio|WeaponStudio|ProjectileStudio|MapEditor(?:LoadScene|Scene))['"]\))/;
const RETIRED_PATHS = [
  'src/game/editor/CharacterStudio.ts',
  'src/game/editor/AnimationStudio.ts',
  'src/game/editor/WeaponStudio.ts',
  'src/game/editor/ProjectileStudio.ts',
  'src/game/editor/MapEditorScene.ts',
  'src/game/features/world/MapBuilder.ts',
  'src/game/features/objects/ObjectFactory.ts',
  'src/game/features/npcs/NpcActor.ts',
  'src/game/enemies/Enemy.ts',
  'src/game/infrastructure/scenes/compatibility/LegacyWorldAdapter.ts',
  'src/game/infrastructure/scenes/compatibility/LegacyChestUiBridge.ts',
  'src/game/infrastructure/scenes/compatibility/LegacyBossUiBridge.ts',
];

function sourceFiles(root, relative = 'src/game') {
  const directory = path.join(root, relative);
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const candidate = `${relative}/${entry.name}`;
    return entry.isDirectory() ? sourceFiles(root, candidate) : entry.name.endsWith('.ts') ? [candidate] : [];
  });
}

export function auditSourceOwnership(relative, source) {
  const problems = [];
  if (!relative.startsWith('src/game/infrastructure/persistence/') && /\b(?:localStorage|sessionStorage|indexedDB)\b/.test(source)) {
    problems.push(`${relative}: browser persistence belongs in infrastructure/persistence`);
  }
  if (!relative.startsWith('src/game/editor/') && RETIRED_EDITOR_IMPORT.test(source)) {
    problems.push(`${relative}: category-specific editor import`);
  }
  if (!relative.startsWith('src/game/infrastructure/scenes/compatibility/')
    && !relative.endsWith('/tooling.ts')
    && /\b(?:from|import\()\s*['"][^'"]*Legacy(?:Chest|Boss)UiBridge/.test(source)) {
    problems.push(`${relative}: retired UI bridge import`);
  }
  if (/procedural-map-generator|scripts\/lib\/procedural/.test(source)) {
    problems.push(`${relative}: production source imports procedural map generation`);
  }
  if (relative.startsWith('src/game/editor/')) return problems;
  const permitted = APPROVED_LEGACY_CONSTRUCTORS.get(relative) ?? [];
  for (const name of LEGACY_CONSTRUCTORS) {
    if (new RegExp(`\\bnew\\s+${name}\\s*\\(`).test(source) && !permitted.includes(name)) {
      problems.push(`${relative}: unapproved legacy ${name} construction`);
    }
  }
  return problems;
}

export function auditSceneOwnership(root = REPOSITORY_ROOT) {
  const problems = [];
  const config = readFileSync(path.join(root, 'src/game/config.ts'), 'utf8');
  const world = readFileSync(path.join(root, 'src/game/features/world/UniversalSceneWorldController.ts'), 'utf8');
  const ledger = JSON.parse(readFileSync(path.join(root, 'scripts/migrations/universal-scene-conversion-ledger.json'), 'utf8'));
  for (const row of ledger.rows.filter((entry) => entry.classification === 'convert' && entry.writerState !== 'scene')) {
    problems.push(`${row.key}: conversion has no scene owner`);
  }
  for (const relative of RETIRED_PATHS) {
    if (existsSync(path.join(root, relative))) problems.push(`${relative}: retired owner still exists`);
  }
  const vite = readFileSync(path.join(root, 'vite.config.ts'), 'utf8');
  if (/\b(?:mapEditor|characterStudio|animationStudio|weaponStudio|projectileStudio|objectStudio)(?:Write|Save|Update|Plugin)\b/i.test(vite)) {
    problems.push('vite.config.ts still registers a category-specific writer');
  }
  if (RETIRED_EDITOR_IMPORT.test(config) || /\bisEditor\b|\beditorScenes\b/.test(config)) {
    problems.push('config.ts still mounts a category-specific editor');
  }
  for (const row of ledger.rows.filter((entry) => entry.family === 'ui' && entry.writerState === 'scene')) {
    const id = `ui.${row.stableId}`;
    const document = path.join(root, 'src/game/content/scenes/authored/ui', `${row.stableId}.scene.json`);
    let authoredId;
    try { authoredId = JSON.parse(readFileSync(document, 'utf8')).sceneId; }
    catch { problems.push(`${row.key}: authored UI scene is missing`); continue; }
    if (authoredId !== id || !world.includes(`sceneId('${id}')`)) {
      problems.push(`${row.key}: authored UI scene is not mounted by the world composition`);
    }
  }
  for (const relative of sourceFiles(root)) {
    const source = readFileSync(path.join(root, relative), 'utf8');
    problems.push(...auditSourceOwnership(relative, source));
  }
  return problems;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const problems = auditSceneOwnership();
  if (problems.length) {
    for (const problem of problems) console.error(`scene ownership: ${problem}`);
    process.exitCode = 1;
  } else {
    console.log('Scene ownership guard passed.');
  }
}
