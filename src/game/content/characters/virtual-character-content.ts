import playerCharacter from './player-slime/character.json';
import playerVisual from './player-slime/visual-set.json';
import archerCharacter from './worm-archer/character.json';
import archerVisual from './worm-archer/visual-set.json';
import brawlerCharacter from './worm-brawler/character.json';
import brawlerVisual from './worm-brawler/visual-set.json';
import swordsmanCharacter from './worm-swordsman/character.json';
import swordsmanVisual from './worm-swordsman/visual-set.json';
import brawlerHitVisual from '../visuals/enemy-worm-brawler-hit/visual-set.json';
import elderCharacter from './village-elder-plop/character.json';
import elderVisual from './village-elder-plop/visual-set.json';
import mossyCharacter from './mossy-scout/character.json';
import mossyVisual from './mossy-scout/visual-set.json';
import liliCharacter from './lili/character.json';
import liliVisual from './lili/visual-set.json';
import redSlimeBoyCharacter from './red-slime-boy/character.json';
import redSlimeBoyVisual from './red-slime-boy/visual-set.json';
import yellowBlondSlimeGirlCharacter from './yellow-blond-slime-girl/character.json';
import yellowBlondSlimeGirlVisual from './yellow-blond-slime-girl/visual-set.json';
import fishermanSlimeCharacter from './fisherman-slime/character.json';
import fishermanSlimeVisual from './fisherman-slime/visual-set.json';
import fattyOneEyeCharacter from './fatty-one-eye/character.json';
import fattyOneEyeVisual from './fatty-one-eye/visual-set.json';

export const characterPackages = [
  { characterId: 'player-slime', character: playerCharacter, visualSet: playerVisual },
  { characterId: 'worm-archer', character: archerCharacter, visualSet: archerVisual },
  { characterId: 'worm-brawler', character: brawlerCharacter, visualSet: brawlerVisual },
  { characterId: 'worm-swordsman', character: swordsmanCharacter, visualSet: swordsmanVisual },
  { characterId: 'village-elder-plop', character: elderCharacter, visualSet: elderVisual },
  { characterId: 'mossy-scout', character: mossyCharacter, visualSet: mossyVisual },
  { characterId: 'lili', character: liliCharacter, visualSet: liliVisual },
  { characterId: 'red-slime-boy', character: redSlimeBoyCharacter, visualSet: redSlimeBoyVisual },
  { characterId: 'yellow-blond-slime-girl', character: yellowBlondSlimeGirlCharacter, visualSet: yellowBlondSlimeGirlVisual },
  { characterId: 'fisherman-slime', character: fishermanSlimeCharacter, visualSet: fishermanSlimeVisual },
  { characterId: 'fatty-one-eye', character: fattyOneEyeCharacter, visualSet: fattyOneEyeVisual },
];

export const visualSets = [...characterPackages.map((entry) => entry.visualSet), brawlerHitVisual];
