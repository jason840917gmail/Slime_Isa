#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const REPOSITORY_ROOT = fileURLToPath(new URL('..', import.meta.url));
export const LEDGER_PATH = 'scripts/migrations/universal-scene-conversion-ledger.json';
export const EVIDENCE_PATH = 'docs/superpowers/plans/evidence/universal-scene-conversion-ledger.md';

const PRODUCTION_MAPS = new Set(['crystal-caverns', 'gloop-forest', 'level-1']);
const UI_MODULES = [
  'src/game/HUD.ts',
  'src/game/Minimap.ts',
  'src/game/ui/AbilityBar.ts',
  'src/game/ui/AreaTitleCard.ts',
  'src/game/ui/BossHealthBar.ts',
  'src/game/ui/ChestInventoryPanel.ts',
  'src/game/ui/CraftingUI.ts',
  'src/game/ui/FloatingText.ts',
  'src/game/ui/HealthBar.ts',
  'src/game/ui/InventoryUI.ts',
  'src/game/ui/LevelUpModal.ts',
  'src/game/ui/QuestJournal.ts',
  'src/game/ui/QuestOfferModal.ts',
  'src/game/ui/WeaponHotbar.ts',
  'src/game/ui/WorldMapUI.ts',
];

const FAMILY_CONTRACTS = {
  animation: {
    catalog: ['AnimationCatalog', 'animation-package.schema.json', 'animation validation'],
    runtime: ['AnimationClock', 'LayeredAnimationPlayer', 'AnimatedVisual'],
    writers: ['/__animation-library/save', '/__animation-library/transaction'],
    destination: (id) => `resource://animations/${id}`,
    migrationWorkPackage: 6,
    verification: ['test:scene-content', 'test:scene-runtime', 'test:scene-conversion'],
  },
  asset: {
    catalog: ['asset/assets.json', 'check-assets.mjs'],
    runtime: ['AssetLoader', 'manifest'],
    writers: ['/__character-studio/asset/register'],
    destination: (id) => `asset://${id}`,
    migrationWorkPackage: null,
    verification: ['assets:check', 'test:scene-conversion'],
    classification: 'retain',
  },
  boss: {
    catalog: ['BossCatalog', 'boss.schema.json'],
    runtime: ['BossCampController', 'FattyOneEyeBoss'],
    writers: ['/__map-editor/save'],
    destination: (id) => `scene://characters/${id}`,
    migrationWorkPackage: 9,
    verification: ['test:scene-integration', 'test:scene-conversion'],
  },
  character: {
    catalog: ['CharacterCatalog', 'character.schema.json', 'character validation'],
    runtime: ['PlayerFactory', 'Enemy', 'NpcActor', 'FattyOneEyeBoss'],
    writers: ['/__character-studio/package/create', '/__character-studio/package/update', '/__character-studio/package/duplicate'],
    destination: (id) => `scene://characters/${id}`,
    migrationWorkPackage: 10,
    verification: ['test:scene-integration', 'test:scene-conversion'],
  },
  effect: {
    catalog: ['EffectCatalog', 'effect.schema.json', 'effect validation'],
    runtime: ['WorldEffectPool', 'WorldEffectAdapter'],
    writers: ['/__character-studio/effect/create', '/__character-studio/effect/update'],
    destination: (id) => `scene://effects/${id}`,
    migrationWorkPackage: 11,
    verification: ['test:scene-integration', 'test:scene-conversion'],
  },
  enemy: {
    catalog: ['EnemyTypes', 'enemy-types.schema.json'],
    runtime: ['EnemySpawner', 'Enemy'],
    writers: ['/__character-studio/package/update'],
    destination: (id) => `scene://characters/${id}`,
    migrationWorkPackage: 9,
    verification: ['test:scene-integration', 'test:scene-conversion'],
  },
  map: {
    catalog: ['MapRepository', 'maps.schema.json', 'mapFormat'],
    runtime: ['MapBuilder', 'ObjectFactory', 'TileFactory'],
    writers: ['/__map-editor/create', '/__map-editor/save'],
    destination: (id) => `scene://worlds/${id}`,
    migrationWorkPackage: 13,
    verification: ['test:scene-integration', 'test:scene-conversion'],
  },
  npc: {
    catalog: ['NpcCatalog', 'NpcDefinitions'],
    runtime: ['NpcRuntimeController', 'NpcActor'],
    writers: ['/__character-studio/package/update', '/__map-editor/save'],
    destination: (id) => `scene://characters/${id}`,
    migrationWorkPackage: 10,
    verification: ['test:scene-integration', 'test:scene-conversion'],
  },
  object: {
    catalog: ['ObjectCatalog', 'objects.schema.json'],
    runtime: ['ObjectFactory', 'MapBuilder'],
    writers: ['/__map-editor/object-template/update', '/__map-editor/object-gameplay/update', '/__map-editor/object-template/create', '/__map-editor/object-template/duplicate'],
    destination: (id) => `scene://objects/${id}`,
    migrationWorkPackage: 12,
    verification: ['test:scene-integration', 'test:scene-conversion'],
  },
  projectile: {
    catalog: ['ProjectileCatalog', 'projectile.schema.json', 'projectile validation'],
    runtime: ['ProjectilePoolImpl', 'CombatController'],
    writers: ['/__character-studio/projectile/create', '/__character-studio/projectile/update'],
    destination: (id) => `scene://projectiles/${id}`,
    migrationWorkPackage: 11,
    verification: ['test:scene-integration', 'test:scene-conversion'],
  },
  terrain: {
    catalog: ['TileCatalog'],
    runtime: ['TileFactory', 'TerrainTransitionRenderer'],
    writers: ['/__map-editor/save'],
    destination: (id) => `resource://terrain/${id}`,
    migrationWorkPackage: 13,
    verification: ['test:scene-integration', 'test:scene-conversion'],
  },
  ui: {
    catalog: ['WorldScene UI composition'],
    runtime: ['WorldScene', 'ModalStack'],
    writers: [],
    destination: (id) => `scene://ui/${id}`,
    migrationWorkPackage: 14,
    verification: ['test:scene-studio', 'test:scene-browser', 'test:scene-conversion'],
  },
  visual: {
    catalog: ['VisualCatalog', 'visual-set.schema.json', 'character validation'],
    runtime: ['AnimatedVisual', 'LayeredAnimationVisual'],
    writers: ['/__character-studio/package/update'],
    destination: (id) => `resource://visuals/${id}`,
    migrationWorkPackage: 6,
    verification: ['test:scene-content', 'test:scene-runtime', 'test:scene-conversion'],
  },
  weapon: {
    catalog: ['WeaponCatalog', 'weapon.schema.json', 'weapon validation'],
    runtime: ['Weapon', 'WeaponVisual', 'CombatController'],
    writers: ['/__character-studio/weapon/create', '/__character-studio/weapon/update', '/__character-studio/weapon/save-package'],
    destination: (id) => `scene://weapons/${id}`,
    migrationWorkPackage: 11,
    verification: ['test:scene-integration', 'test:scene-conversion'],
  },
};

function posix(relativePath) {
  return relativePath.replaceAll('\\', '/');
}

function absolute(repositoryRoot, relativePath) {
  return path.resolve(repositoryRoot, relativePath);
}

function json(repositoryRoot, relativePath) {
  return JSON.parse(readFileSync(absolute(repositoryRoot, relativePath), 'utf8'));
}

function walk(repositoryRoot, relativeDirectory, filename) {
  const output = [];
  const visit = (directory) => {
    for (const entry of readdirSync(absolute(repositoryRoot, directory), { withFileTypes: true })) {
      const candidate = posix(path.join(directory, entry.name));
      if (entry.isDirectory()) visit(candidate);
      else if (entry.isFile() && entry.name === filename) output.push(candidate);
    }
  };
  visit(relativeDirectory);
  return output.sort();
}

function row(family, stableId, oldSourcePath, extra = {}) {
  const contract = FAMILY_CONTRACTS[family];
  if (!contract) throw new Error(`Missing inventory contract for '${family}'`);
  return {
    key: `${family}:${stableId}`,
    family,
    stableId,
    environment: 'production',
    classification: contract.classification ?? 'convert',
    oldSourcePath: posix(oldSourcePath),
    oldCatalogValidator: contract.catalog,
    oldFactoryController: contract.runtime,
    oldEditorWriteEndpoints: contract.writers,
    destinationId: contract.destination(stableId),
    persistenceKeys: [],
    migrationWorkPackage: contract.migrationWorkPackage,
    focusedVerification: contract.verification,
    legacyRemovalWorkPackage: contract.classification === 'retain' ? null : 15,
    ...extra,
  };
}

function retainedRow(family, stableId, oldSourcePath, destinationId, catalog, runtime, verification, extra = {}) {
  return {
    key: `${family}:${stableId}`,
    family,
    stableId,
    environment: 'production',
    classification: 'retain',
    oldSourcePath: posix(oldSourcePath),
    oldCatalogValidator: catalog,
    oldFactoryController: runtime,
    oldEditorWriteEndpoints: [],
    destinationId,
    persistenceKeys: [],
    migrationWorkPackage: null,
    focusedVerification: verification,
    legacyRemovalWorkPackage: null,
    ...extra,
  };
}

function idsFromConstObject(source, constName) {
  const marker = `export const ${constName}`;
  const start = source.indexOf(marker);
  if (start < 0) throw new Error(`Could not find ${marker}`);
  const bodyStart = source.indexOf('{', start);
  let depth = 0;
  let bodyEnd = -1;
  for (let index = bodyStart; index < source.length; index += 1) {
    if (source[index] === '{') depth += 1;
    else if (source[index] === '}') {
      depth -= 1;
      if (depth === 0) {
        bodyEnd = index;
        break;
      }
    }
  }
  if (bodyStart < 0 || bodyEnd < 0) throw new Error(`Could not parse ${constName}`);
  return [...source.slice(bodyStart + 1, bodyEnd).matchAll(/^\s{2}(?:'([^']+)'|([a-zA-Z0-9-]+)):\s*\{/gm)]
    .map((match) => match[1] ?? match[2]);
}

function idsFromReadonlyArray(source, constName) {
  const marker = `export const ${constName}`;
  const start = source.indexOf(marker);
  if (start < 0) throw new Error(`Could not find ${marker}`);
  const bodyStart = source.indexOf('[', start);
  const bodyEnd = source.indexOf('\n] as const', bodyStart);
  const fallbackEnd = source.indexOf('\n];', bodyStart);
  const end = bodyEnd >= 0 ? bodyEnd : fallbackEnd;
  if (bodyStart < 0 || end < 0) throw new Error(`Could not parse ${constName}`);
  return [...source.slice(bodyStart + 1, end).matchAll(/^\s{4}id:\s*'([^']+)'/gm)].map((match) => match[1]);
}

function discoverWriterEndpoints(repositoryRoot) {
  const sources = [
    'vite.config.ts',
    'src/game/content/animations/animationContentModulesPlugin.ts',
    'src/game/content/characters/characterContentModulesPlugin.ts',
    'src/game/content/gameConstantsContentPlugin.ts',
  ];
  const endpoints = new Map();
  for (const sourcePath of sources) {
    const source = readFileSync(absolute(repositoryRoot, sourcePath), 'utf8');
    for (const match of source.matchAll(/server\.middlewares\.use\(\s*['"]([^'"]+)['"]/g)) {
      endpoints.set(match[1], { endpoint: match[1], sourcePath });
    }
    const constantMatch = source.match(/const ENDPOINT = ['"]([^'"]+)['"]/);
    if (constantMatch) endpoints.set(constantMatch[1], { endpoint: constantMatch[1], sourcePath });
  }
  return [...endpoints.values()].sort((left, right) => left.endpoint.localeCompare(right.endpoint));
}

function discoverRoutes(repositoryRoot) {
  const sourcePath = 'src/game/config.ts';
  const source = readFileSync(absolute(repositoryRoot, sourcePath), 'utf8');
  const values = new Set([...source.matchAll(/\.get\(['"](studio|editor)['"]\)/g)].map((match) => match[1]));
  return [...values].sort().map((queryKey) => ({ queryKey, sourcePath }));
}

export function discoverInventory(repositoryRoot = REPOSITORY_ROOT) {
  const rows = [];

  for (const sourcePath of walk(repositoryRoot, 'src/game/content/characters', 'character.json')) {
    const document = json(repositoryRoot, sourcePath);
    rows.push(row('character', document.characterId, sourcePath, {
      migrationWorkPackage: ['enemy', 'boss'].includes(document.kind) ? 9 : 10,
    }));
  }
  for (const sourcePath of [
    ...walk(repositoryRoot, 'src/game/content/characters', 'visual-set.json'),
    ...walk(repositoryRoot, 'src/game/content/visuals', 'visual-set.json'),
  ]) {
    const document = json(repositoryRoot, sourcePath);
    rows.push(row('visual', document.visualSetId, sourcePath));
  }
  for (const sourcePath of walk(repositoryRoot, 'src/game/content/animations', 'animation.json')) {
    const document = json(repositoryRoot, sourcePath);
    rows.push(row('animation', document.animationId, sourcePath));
  }
  for (const sourcePath of walk(repositoryRoot, 'src/game/content/weapons', 'weapon.json')) {
    const document = json(repositoryRoot, sourcePath);
    rows.push(row('weapon', document.weaponId, sourcePath));
  }
  for (const sourcePath of walk(repositoryRoot, 'src/game/content/projectiles', 'projectile.json')) {
    const document = json(repositoryRoot, sourcePath);
    rows.push(row('projectile', document.projectileId, sourcePath));
  }
  for (const sourcePath of walk(repositoryRoot, 'src/game/content/effects', 'effect.json')) {
    const document = json(repositoryRoot, sourcePath);
    rows.push(row('effect', document.effectId, sourcePath));
  }
  const objectFiles = [];
  const visitObjects = (directory) => {
    for (const entry of readdirSync(absolute(repositoryRoot, directory), { withFileTypes: true })) {
      const candidate = posix(path.join(directory, entry.name));
      if (entry.isDirectory()) visitObjects(candidate);
      else if (entry.isFile() && entry.name.endsWith('.json') && entry.name !== 'objects.schema.json') objectFiles.push(candidate);
    }
  };
  visitObjects('src/game/content/objects');
  for (const sourcePath of objectFiles.sort()) {
    const document = json(repositoryRoot, sourcePath);
    rows.push(row('object', document.objectId, sourcePath));
  }

  const enemiesPath = 'src/game/content/enemies/enemy-types.json';
  for (const id of Object.keys(json(repositoryRoot, enemiesPath).types).sort()) rows.push(row('enemy', id, enemiesPath));
  for (const sourcePath of readdirSync(absolute(repositoryRoot, 'src/game/content/bosses'))
    .filter((name) => name.endsWith('.json') && name !== 'boss.schema.json').sort()
    .map((name) => `src/game/content/bosses/${name}`)) {
    const document = json(repositoryRoot, sourcePath);
    rows.push(row('boss', document.id, sourcePath));
  }

  const npcPath = 'src/game/content/npcs/NpcDefinitions.ts';
  const npcSource = readFileSync(absolute(repositoryRoot, npcPath), 'utf8');
  for (const id of idsFromReadonlyArray(npcSource, 'NPC_DEFINITIONS')) rows.push(row('npc', id, npcPath));

  const terrainPath = 'src/game/content/terrain/TileCatalog.ts';
  const terrainSource = readFileSync(absolute(repositoryRoot, terrainPath), 'utf8');
  for (const id of idsFromConstObject(terrainSource, 'TILE_CATALOG')) rows.push(row('terrain', id, terrainPath));

  for (const name of readdirSync(absolute(repositoryRoot, 'src/game/content/maps')).filter((entry) => entry.endsWith('.map.json')).sort()) {
    const sourcePath = `src/game/content/maps/${name}`;
    const document = json(repositoryRoot, sourcePath);
    const persistenceKeys = (document.objects ?? []).map((entry) => entry.instanceId).filter(Boolean).sort();
    const encounterIds = [
      ...(document.enemySpawnAreas ?? []).map((entry) => entry.id),
      ...(document.npcWanderAreas ?? []).map((entry) => entry.id),
      ...(document.bossCamps ?? []).map((entry) => entry.id),
    ].filter(Boolean).sort();
    rows.push(row('map', document.mapId, sourcePath, {
      environment: PRODUCTION_MAPS.has(document.mapId) ? 'production' : 'development',
      persistenceKeys,
      embeddedEncounterIds: encounterIds,
    }));
  }

  for (const sourcePath of UI_MODULES) {
    if (!existsSync(absolute(repositoryRoot, sourcePath))) continue;
    const id = path.basename(sourcePath, '.ts').replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase();
    rows.push(row('ui', id, sourcePath));
  }

  const manifestPath = 'asset/assets.json';
  const manifest = json(repositoryRoot, manifestPath);
  for (const id of Object.keys(manifest.assets).sort()) rows.push(row('asset', id, manifestPath));

  const itemsPath = 'src/game/content/items/items.json';
  for (const id of Object.keys(json(repositoryRoot, itemsPath)).filter((id) => id !== '$schema').sort()) {
    rows.push(retainedRow('item', id, itemsPath, `project-data://items/${id}`, ['ItemCatalog'], ['Inventory', 'GameSaveData'], ['assets:check', 'test:progression']));
  }

  const recipePath = 'src/game/content/recipes/RecipeCatalog.ts';
  const recipeSource = readFileSync(absolute(repositoryRoot, recipePath), 'utf8');
  for (const id of [...recipeSource.matchAll(/^\s{4}id:\s*'([^']+)'/gm)].map((match) => match[1])) {
    rows.push(retainedRow('recipe', id, recipePath, `project-data://recipes/${id}`, ['RecipeCatalog'], ['CraftingService'], ['test:ui']));
  }

  const questDirectory = 'src/game/content/quests/quests';
  for (const name of readdirSync(absolute(repositoryRoot, questDirectory)).filter((entry) => entry.endsWith('.ts')).sort()) {
    const sourcePath = `${questDirectory}/${name}`;
    const source = readFileSync(absolute(repositoryRoot, sourcePath), 'utf8');
    const match = source.match(/^\s{2}id:\s*'([^']+)'/m);
    if (match) rows.push(retainedRow('quest', match[1], sourcePath, `project-data://quests/${match[1]}`, ['QuestCatalog', 'validateQuestCatalog'], ['QuestService', 'QuestTracker'], ['quests:check', 'test:quests']));
  }

  const areaPath = 'src/game/world/Area.ts';
  const areaSource = readFileSync(absolute(repositoryRoot, areaPath), 'utf8');
  for (const id of idsFromConstObject(areaSource, 'AREAS')) {
    rows.push(retainedRow('area', id, areaPath, `project-data://areas/${id}`, ['Area'], ['AreaNavigation'], ['maps:check', 'test:scene-conversion']));
  }
  rows.push(retainedRow('game-constants', 'global', 'src/game/content/game-constants.json', 'project-data://game-constants/global', ['GameConstantsValidation', 'game-constants.schema.json'], ['GameState', 'PlayerProgression'], ['constants:check', 'test:game-constants'], {
    oldEditorWriteEndpoints: ['/__game-constants'],
  }));

  const keyOwners = new Map();
  for (const entry of rows) {
    if (keyOwners.has(entry.key)) throw new Error(`Duplicate inventory key '${entry.key}' in '${keyOwners.get(entry.key)}' and '${entry.oldSourcePath}'`);
    keyOwners.set(entry.key, entry.oldSourcePath);
    entry.sourceHash = sha256File(repositoryRoot, entry.oldSourcePath);
    entry.converterVersion = 1;
    entry.oldToNewIdMap = { sourceId: entry.stableId, targetId: entry.destinationId };
    entry.outputs = [];
    entry.consumedFieldPaths = [];
    entry.intentionallyRetainedFields = entry.classification === 'retain'
      ? [{ path: '$', owner: entry.destinationId }]
      : [];
    entry.writerState = 'legacy';
  }

  return {
    version: 1,
    rows: rows.sort((left, right) => left.key.localeCompare(right.key)),
    writerEndpoints: discoverWriterEndpoints(repositoryRoot),
    editorRoutes: discoverRoutes(repositoryRoot),
  };
}

export function sha256File(repositoryRoot, relativePath) {
  return createHash('sha256').update(readFileSync(absolute(repositoryRoot, relativePath))).digest('hex');
}

function renderMarkdown(ledger, repositoryRoot) {
  const counts = new Map();
  for (const entry of ledger.rows) counts.set(entry.family, (counts.get(entry.family) ?? 0) + 1);
  const mapRows = ledger.rows.filter((entry) => entry.family === 'map');
  const stablePersistenceKeyCount = mapRows.reduce((total, entry) => total + entry.persistenceKeys.length, 0);
  const lines = [
    '# Universal Scene Conversion Ledger',
    '',
    'This file summarizes the checked-in machine ledger. Regenerate both with `node scripts/inventory-scene-conversion.mjs --write`.',
    '',
    '## Coverage',
    '',
    '| Family | Rows |',
    '| --- | ---: |',
    ...[...counts].sort(([left], [right]) => left.localeCompare(right)).map(([family, count]) => `| ${family} | ${count} |`),
    `| **Total** | **${ledger.rows.length}** |`,
    '',
    `Authored maps: ${mapRows.length} (${mapRows.filter((entry) => entry.environment === 'production').length} production, ${mapRows.filter((entry) => entry.environment === 'development').length} development/test).`,
    '',
    `Stable authored map instance persistence keys: ${stablePersistenceKeyCount}.`,
    '',
    '## Legacy writer endpoints',
    '',
    ...ledger.writerEndpoints.map((entry) => `- \`${entry.endpoint}\` — \`${entry.sourcePath}\``),
    '',
    '## Category routes',
    '',
    ...ledger.editorRoutes.map((entry) => `- \`?${entry.queryKey}=\` — \`${entry.sourcePath}\``),
    '',
    '## Baseline hashes',
    '',
    `- \`asset/assets.json\`: \`${sha256File(repositoryRoot, 'asset/assets.json')}\``,
    ...mapRows.map((entry) => `- \`${entry.oldSourcePath}\`: \`${sha256File(repositoryRoot, entry.oldSourcePath)}\``),
    '',
    'Every row records its current validator/catalog, construction owner, writable endpoint, destination ID, persistence keys, migration package, focused checks, and removal package in the JSON ledger.',
    '',
  ];
  return lines.join('\n');
}

export function writeInventory(repositoryRoot = REPOSITORY_ROOT) {
  const ledger = discoverInventory(repositoryRoot);
  writeFileSync(absolute(repositoryRoot, LEDGER_PATH), `${JSON.stringify(ledger, null, 2)}\n`, 'utf8');
  writeFileSync(absolute(repositoryRoot, EVIDENCE_PATH), renderMarkdown(ledger, repositoryRoot), 'utf8');
  return ledger;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const ledger = process.argv.includes('--write') ? writeInventory() : discoverInventory();
  console.log(`Universal scene inventory: ${ledger.rows.length} row(s), ${ledger.writerEndpoints.length} writer endpoint(s), ${ledger.editorRoutes.length} category route(s).`);
}
