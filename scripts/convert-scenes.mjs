#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { ConversionRunner } from './lib/scene-conversion/ConversionRunner.mjs';
import { visualSceneAdapter } from './lib/scene-conversion/animations.mjs';
import { bossCampSceneAdapter } from './lib/scene-conversion/boss-camps.mjs';
import { characterSceneAdapter, enemySceneAdapter } from './lib/scene-conversion/characters.mjs';
import { objectSceneAdapter } from './lib/scene-conversion/objects.mjs';
import { effectSceneAdapter, projectileSceneAdapter, weaponSceneAdapter } from './lib/scene-conversion/combat-entities.mjs';
import { validateSceneWriteSet } from './lib/scene-conversion/validate-scene-write-set.mjs';

const repositoryRoot = fileURLToPath(new URL('..', import.meta.url));
const args = process.argv.slice(2);
const familyIndex = args.indexOf('--family');
const family = familyIndex >= 0 ? args[familyIndex + 1] : 'all';
const mode = args.includes('--apply') ? 'apply' : args.includes('--check') ? 'check' : 'dry-run';
const explicitUnitKeys = args.flatMap((argument, index) => argument === '--unit' ? [args[index + 1]] : []).filter(Boolean);
const sliceUnitKeys = [
  'visual:character.player.slime',
  'visual:character.npc.lili',
  'visual:character.npc.mossy-scout',
  'visual:character.npc.red-slime-boy',
  'visual:character.npc.village-elder-plop',
  'visual:character.npc.yellow-blond-slime-girl',
  'visual:enemy.worm.brawler',
  'visual:enemy.worm.archer',
  'visual:enemy.worm.swordsman',
  'visual:enemy.slime.spider',
  'visual:boss.fatty-one-eye',
  'character:worm-brawler',
  'character:player-slime',
  'character:lili',
  'character:mossy-scout',
  'character:red-slime-boy',
  'character:village-elder-plop',
  'character:yellow-blond-slime-girl',
  'character:worm-archer',
  'character:worm-swordsman',
  'character:slime-spider',
  'character:fatty-one-eye',
  'enemy:worm-brawler',
  'enemy:worm-archer',
  'enemy:worm-swordsman',
  'boss:fatty-one-eye',
  'object:chest.wooden',
  'object:resource.stone-node',
  'object:tree.world.solid',
  'object:collectible.charcoal-pile',
  'object:collectible.crystal-shard',
  'object:collectible.energy-potion',
  'object:collectible.green-key',
  'object:collectible.hp-potion',
  'object:collectible.iron-ore-pile',
  'object:collectible.purple-berry',
  'object:collectible.silk-clump',
  'object:collectible.small-stone-pile',
  'object:collectible.small-wood-pile',
  'object:collectible.stone-pile',
  'object:collectible.wood-pile',
  'object:decoration.world.floor',
  'object:decoration.world.solid',
  'object:house.world.solid',
  'object:rock.world-wall.decorative',
  'object:rock.world-wall.solid',
  'object:wall.stone.solid',
  'weapon:basic-spear',
  'weapon:basic-sword',
  'weapon:goo-gauntlet',
  'weapon:pickaxe',
  'weapon:slam-hammer',
  'weapon:stone-axe',
  'weapon:stone-pickaxe',
  'weapon:stone-spear',
  'weapon:wooden-axe',
  'weapon:wooden-spear',
  'projectile:worm-arrow',
  'effect:basic-spear-impact',
  'effect:basic-sword-impact',
  'effect:slam-hammer-impact',
  'effect:stone-impact',
  'effect:wood-impact',
];
const unitKeys = explicitUnitKeys.length > 0 ? explicitUnitKeys : sliceUnitKeys;
const ledger = JSON.parse(await readFile(path.join(repositoryRoot, 'scripts/migrations/universal-scene-conversion-ledger.json'), 'utf8'));
const manifest = JSON.parse(await readFile(path.join(repositoryRoot, 'asset/assets.json'), 'utf8'));
const runner = new ConversionRunner({
  repositoryRoot,
  ledger,
  adapters: {
    visual: visualSceneAdapter,
    character: characterSceneAdapter,
    enemy: enemySceneAdapter,
    boss: bossCampSceneAdapter,
    object: objectSceneAdapter,
    weapon: weaponSceneAdapter,
    projectile: projectileSceneAdapter,
    effect: effectSceneAdapter,
  },
  outputRoot: path.join(repositoryRoot, 'src/game/content/scenes/authored'),
  validateWriteSet: (outputs) => validateSceneWriteSet(outputs, { hasAsset: (assetId) => Object.hasOwn(manifest.assets, assetId) }),
});

try {
  const report = await runner.run({ family, mode, unitKeys });
  console.log(JSON.stringify(report, null, 2));
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
