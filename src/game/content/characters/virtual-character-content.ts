import playerCharacter from './player-slime/character.json';
import playerVisual from './player-slime/visual-set.json';
import archerCharacter from './worm-archer/character.json';
import archerVisual from './worm-archer/visual-set.json';
import brawlerCharacter from './worm-brawler/character.json';
import brawlerVisual from './worm-brawler/visual-set.json';
import swordsmanCharacter from './worm-swordsman/character.json';
import swordsmanVisual from './worm-swordsman/visual-set.json';
import brawlerHitVisual from '../visuals/enemy-worm-brawler-hit/visual-set.json';
import treeVisual from '../visuals/tree-world/visual-set.json';

export const characterPackages = [
  { characterId: 'player-slime', character: playerCharacter, visualSet: playerVisual },
  { characterId: 'worm-archer', character: archerCharacter, visualSet: archerVisual },
  { characterId: 'worm-brawler', character: brawlerCharacter, visualSet: brawlerVisual },
  { characterId: 'worm-swordsman', character: swordsmanCharacter, visualSet: swordsmanVisual },
];

export const visualSets = [...characterPackages.map((entry) => entry.visualSet), brawlerHitVisual, treeVisual];
