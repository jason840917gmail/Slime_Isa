import type { QuestDefinition } from '../types';

/**
 * Chapter 1 — The Clearing. One main line from an empty clearing to Fatty One Eye:
 * workbench → stone tools → wooden spear → worm camp → stone spear → Fatty → Gloop Forest.
 * Every step ends with a recipe or a new place, and each quest opens the next one.
 *
 * Level 1 holds a fixed material budget (40 loose wood, 40 wood in trees, ~200 stone)
 * and nothing regrows. The wood rewards below bridge the workbench cost so the chain
 * can never softlock; keep them in step with recipe costs.
 */

const ELDER = 'village-elder-plop';
const MOSSY = 'level-1-spider-giver';

const retry = { kind: 'forbidden' } as const;

export const aPlaceToWork: QuestDefinition = {
  id: 'a-place-to-work',
  definitionVersion: 1,
  chapter: 'Chapter 1 — The Clearing',
  title: 'A Place to Work',
  description: 'Every good slime needs a workbench. Build one and set it up in the clearing.',
  category: 'mandatory',
  prerequisites: [{ kind: 'area-entered', areaIds: ['level-1'] }],
  acquisition: { kind: 'npc', npcIds: [ELDER] },
  stages: [
    {
      id: 'build-workbench',
      title: 'Build a workbench',
      description: 'Pick up the wood lying around the clearing and craft a Workbench (C).',
      objectives: [
        { id: 'craft-workbench', kind: 'craft-item', label: 'Craft a Workbench (40 wood)', target: 1, itemIds: ['workbench'] },
      ],
    },
    {
      id: 'place-workbench',
      title: 'Set it up',
      description: 'Open your inventory (Tab), choose the Workbench, and place it somewhere handy.',
      objectives: [
        { id: 'place-workbench', kind: 'place-item', label: 'Place the Workbench', target: 1, itemIds: ['workbench'] },
      ],
    },
  ],
  completion: { kind: 'npc-turn-in', npcIds: [ELDER] },
  failurePolicy: { kind: 'permanent' },
  abandonmentPolicy: retry,
  rewards: {
    xp: 30,
    items: [{ itemId: 'wood', count: 20 }],
    recipeIds: ['craft-stone-axe', 'craft-stone-pickaxe'],
  },
  dialogue: {
    offer: [
      'Ah, a new slime in the clearing! Welcome, little one.',
      'The forest beyond is no place for bare goo. Before anything else, you need a place to make things.',
      'Gather the wood lying around here and build yourself a workbench. Then set it up somewhere you like.',
    ],
    progress: ['A workbench is the heart of every camp. Wood is scattered all over the clearing.'],
    complete: [
      'A fine bench! You have a knack for this.',
      'Here, take this bundle of wood, and let me show you how to shape stone into tools.',
    ],
  },
};

export const stoneTools: QuestDefinition = {
  id: 'stone-tools',
  definitionVersion: 1,
  title: 'Stone Tools',
  description: 'Craft a stone axe and pickaxe at your workbench, then put them to work on trees and rocks.',
  category: 'mandatory',
  prerequisites: [{ kind: 'quest-status', questId: 'a-place-to-work', status: 'completed' }],
  acquisition: { kind: 'npc', npcIds: [ELDER] },
  stages: [
    {
      id: 'craft-tools',
      title: 'Make your tools',
      description: 'Use the Workbench (F) to craft both stone tools.',
      objectives: [
        { id: 'craft-axe', kind: 'craft-item', label: 'Craft a Stone Axe', target: 1, itemIds: ['stone-axe'] },
        { id: 'craft-pickaxe', kind: 'craft-item', label: 'Craft a Stone Pickaxe', target: 1, itemIds: ['stone-pickaxe'] },
      ],
    },
    {
      id: 'use-tools',
      title: 'Put them to work',
      description: 'Chop trees with the axe and break rocks with the pickaxe.',
      objectives: [
        { id: 'chop-wood', kind: 'collect', label: 'Chop wood from trees', target: 20, itemIds: ['wood'] },
        { id: 'mine-stone', kind: 'collect', label: 'Mine stone from rocks', target: 20, itemIds: ['stone'] },
      ],
    },
  ],
  completion: { kind: 'npc-turn-in', npcIds: [ELDER] },
  failurePolicy: { kind: 'permanent' },
  abandonmentPolicy: retry,
  rewards: {
    xp: 60,
    coins: 20,
    items: [{ itemId: 'wood', count: 10 }],
    recipeIds: ['craft-wooden-spear'],
  },
  dialogue: {
    offer: [
      'With a bench you can make proper tools. An axe for the trees, a pickaxe for the rocks.',
      'Craft both, then show me you can use them.',
    ],
    progress: ['Trees need an axe, rocks need a pickaxe. No amount of bouncing will do it, trust me.'],
    complete: [
      'Now you are a real gatherer!',
      'Worms have been creeping close to the clearing. It is time you learned to make a spear.',
    ],
  },
};

export const wormTrouble: QuestDefinition = {
  id: 'worm-trouble',
  definitionVersion: 1,
  title: 'Worm Trouble',
  description: 'Mossy spotted a worm camp near the clearing. Arm yourself with a spear and drive them out.',
  category: 'mandatory',
  prerequisites: [{ kind: 'quest-status', questId: 'stone-tools', status: 'completed' }],
  acquisition: { kind: 'npc', npcIds: [MOSSY] },
  stages: [
    {
      id: 'arm-yourself',
      title: 'Arm yourself',
      description: 'Craft a Wooden Spear at your workbench and equip it (1–6).',
      objectives: [
        { id: 'craft-wooden-spear', kind: 'craft-item', label: 'Craft a Wooden Spear', target: 1, itemIds: ['wooden-spear'] },
      ],
    },
    {
      id: 'clear-camp',
      title: 'Clear the worm camp',
      description: 'The worms gather south-east of the clearing.',
      objectives: [
        { id: 'defeat-worms', kind: 'kill', label: 'Defeat worm brawlers', target: 5, enemyKinds: ['worm-brawler'] },
      ],
    },
  ],
  completion: { kind: 'npc-turn-in', npcIds: [MOSSY] },
  failurePolicy: { kind: 'permanent' },
  abandonmentPolicy: retry,
  rewards: {
    xp: 80,
    coins: 30,
    recipeIds: ['craft-stone-spear'],
  },
  dialogue: {
    offer: [
      'Psst! Over here. Keep your voice down.',
      'There is a worm camp just past the clearing. They keep coming back, and they are getting bolder.',
      'You will want a spear for this. Make one, then thin their numbers.',
    ],
    progress: ['Keep your distance and let the spear do the work. Worms hate reach.'],
    complete: [
      'Ha! That will teach them.',
      'I have seen something much bigger in the east. A one-eyed blob guarding a chest. Wood will not be enough for that. Here is how to make a stone spear.',
    ],
  },
};

export const theOneEyedGuardian: QuestDefinition = {
  id: 'the-one-eyed-guardian',
  definitionVersion: 1,
  title: 'The One-Eyed Guardian',
  description: 'Fatty One Eye guards the key to the Verdant Gate. Forge a stone spear, defeat him, and step into Gloop Forest.',
  category: 'mandatory',
  prerequisites: [{ kind: 'quest-status', questId: 'worm-trouble', status: 'completed' }],
  acquisition: { kind: 'npc', npcIds: [ELDER] },
  stages: [
    {
      id: 'stone-spear',
      title: 'A sharper point',
      description: 'Craft a Stone Spear at your workbench.',
      objectives: [
        { id: 'craft-stone-spear', kind: 'craft-item', label: 'Craft a Stone Spear', target: 1, itemIds: ['stone-spear'] },
      ],
    },
    {
      id: 'defeat-fatty',
      title: 'Face the guardian',
      description: 'Only a spear can reach his eye. Watch for his leap and strike when he lands.',
      objectives: [
        { id: 'defeat-fatty', kind: 'defeat-boss', label: 'Defeat Fatty One Eye', target: 1, bossIds: ['fatty-one-eye'] },
      ],
    },
    {
      id: 'verdant-gate',
      title: 'Through the Verdant Gate',
      description: 'Take the green key from his chest and open the eastern gate.',
      objectives: [
        { id: 'enter-gloop-forest', kind: 'discover-area', label: 'Enter Gloop Forest', target: 1, areaIds: ['gloop-forest'] },
      ],
    },
  ],
  completion: { kind: 'automatic' },
  failurePolicy: { kind: 'permanent' },
  abandonmentPolicy: retry,
  rewards: {
    xp: 150,
    coins: 100,
    flags: ['chapter-1-complete'],
  },
  dialogue: {
    offer: [
      'So Mossy told you about the guardian. Fatty One Eye.',
      'He has sat on the key to the Verdant Gate for as long as I can remember. Beyond it lies Gloop Forest, and the rest of the world.',
      'Make a stone spear. Aim for the eye. And come back in one piece.',
    ],
    progress: ['Aim for the eye, and never stand where his shadow lands.'],
  },
};

export const aTonicForLili: QuestDefinition = {
  id: 'a-tonic-for-lili',
  definitionVersion: 1,
  title: 'A Tonic for Lili',
  description: 'Lili wants to learn how berries become a healing tonic. Brew one to show her.',
  category: 'optional',
  prerequisites: [{ kind: 'quest-status', questId: 'a-place-to-work', status: 'completed' }],
  acquisition: { kind: 'npc', npcIds: ['lili'] },
  stages: [
    {
      id: 'brew-tonic',
      title: 'Brew a tonic',
      description: 'Find purple berries in the clearing and brew a Slime Tonic (C).',
      objectives: [
        { id: 'brew-tonic', kind: 'craft-item', label: 'Brew a Slime Tonic (3 purple berries)', target: 1, itemIds: ['hp-potion'] },
      ],
    },
  ],
  completion: { kind: 'npc-turn-in', npcIds: ['lili'] },
  failurePolicy: { kind: 'permanent' },
  abandonmentPolicy: { kind: 'retryable', reset: 'quest' },
  rewards: {
    xp: 40,
    items: [{ itemId: 'purple-berry-mat', count: 2 }],
  },
  dialogue: {
    offer: [
      'Hi again! Everyone says purple berries can be brewed into a tonic that heals you.',
      'Could you make one and show me? I would love to see how it works!',
    ],
    progress: ['Purple berries grow in little clumps around the clearing. You need three!'],
    complete: [
      'It glows! That is amazing!',
      'Here, take the berries left over from my basket. Maybe someone else could use them.',
    ],
  },
};

export const snackForTheRoad: QuestDefinition = {
  id: 'snack-for-the-road',
  definitionVersion: 1,
  title: 'Snack for the Road',
  description: 'Lily has been fishing all day without a bite, or a bite to eat. Pack her a berry basket.',
  category: 'optional',
  prerequisites: [{ kind: 'quest-status', questId: 'a-tonic-for-lili', status: 'completed' }],
  acquisition: { kind: 'npc', npcIds: ['fisherman-slime'] },
  stages: [
    {
      id: 'cook-snack',
      title: 'Pack a snack',
      description: 'Weave a small basket of berries (C).',
      objectives: [
        { id: 'cook-berry-basket', kind: 'craft-item', label: 'Make a Berry Basket', target: 1, itemIds: ['berry-basket'] },
      ],
    },
  ],
  completion: { kind: 'npc-turn-in', npcIds: ['fisherman-slime'] },
  failurePolicy: { kind: 'permanent' },
  abandonmentPolicy: { kind: 'retryable', reset: 'quest' },
  rewards: {
    xp: 50,
    coins: 25,
    items: [{ itemId: 'hp-potion', count: 1 }],
  },
  dialogue: {
    offer: [
      'Shh... you will scare the fish. Not that there are any.',
      'I have been out here since sunrise and forgot to pack lunch. Could you put together a little berry basket for me?',
    ],
    progress: ['A couple of berries and a bit of wood for the basket. That is all I need.'],
    complete: [
      'Mmm, just what I needed. Food makes the waiting easier.',
      'Take this tonic. My grandmother brewed it. I never get hurt out here anyway.',
    ],
  },
};

export const CHAPTER_ONE_QUESTS: readonly QuestDefinition[] = [
  aPlaceToWork,
  stoneTools,
  wormTrouble,
  theOneEyedGuardian,
  aTonicForLili,
  snackForTheRoad,
];
