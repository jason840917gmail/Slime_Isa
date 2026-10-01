import type { QuestDefinition } from '../types';

/**
 * Chapter 2 — Gloop Forest (roadmap 8.10; outline in
 * docs/superpowers/specs/2026-09-30-chapter-2-outline.md). The main line:
 * orb-weavers at the forest camp → weaver fangs and the Reinforced Pickaxe →
 * iron ore → rekindle Slimeshire's Forge → iron gear → the Matron's nest.
 *
 * Mossy waits at the forest camp (the walled clearing with the hut); Pip and
 * Elder Plop stay in Slimeshire. Every input has a renewable source: orb-weavers
 * respawn, iron nodes and trees regrow, and the Forge turns wood into charcoal.
 * Quest text never names keys: the HUD shows the controls.
 */

const ELDER = 'village-elder-plop';
const MOSSY = 'level-1-spider-giver';
const PIP = 'red-slime-boy';
const SUNNY = 'yellow-blond-slime-girl';

const CHAPTER = 'Chapter 2 — Gloop Forest';
const retry = { kind: 'forbidden' } as const;

export const beyondTheVerdantGate: QuestDefinition = {
  id: 'beyond-the-verdant-gate',
  // v2 (playtest 2026-10-01): the weaver hunt and its fangs are one step, not two quests apart.
  definitionVersion: 2,
  chapter: CHAPTER,
  title: 'Beyond the Verdant Gate',
  description: 'Mossy has set up camp in Gloop Forest. Orb-weavers spin their webs all around it, and their fangs are hard as iron.',
  category: 'mandatory',
  prerequisites: [{ kind: 'quest-status', questId: 'the-one-eyed-guardian', status: 'completed' }],
  acquisition: { kind: 'npc', npcIds: [MOSSY] },
  stages: [
    {
      id: 'thin-the-weavers',
      title: 'Thin out the weavers',
      description: 'Orb-weavers nest in the thickets around the camp. They spit webs from afar: get close and keep moving. A fallen weaver often leaves a fang on the ground.',
      objectives: [
        { id: 'defeat-orb-weavers', kind: 'kill', label: 'Defeat orb-weavers', target: 5, enemyKinds: ['orb-weaver'] },
        { id: 'collect-fangs', kind: 'collect', label: 'Pick up weaver fangs', target: 3, itemIds: ['weaver-fang'] },
      ],
    },
  ],
  completion: { kind: 'npc-turn-in', npcIds: [MOSSY] },
  failurePolicy: { kind: 'permanent' },
  abandonmentPolicy: retry,
  rewards: {
    coins: 30,
    abilityIds: ['stretch-lash'],
    recipeIds: ['craft-reinforced-pickaxe'],
  },
  dialogue: {
    offer: [
      'You made it through the Verdant Gate! Welcome to Gloop Forest.',
      'I set up camp here, behind these old walls. The hut is ours to use: sleep in its bed and you will wake here, not back home.',
      'The trouble is the orb-weavers. They spin webs all over the forest and spit them at anything that moves. Help me thin them out?',
      'And bring me three of their fangs. They are hard as iron, and I have a use for them.',
    ],
    progress: ['They hang back and spit. Close the gap fast, and dodge when you see them wind up. Their fangs drop where they fall: just walk over them.'],
    complete: [
      'Not bad at all! And three fangs, hard as iron.',
      'Bind them to a stone pick at the workbench and it will bite through iron ore. There is iron in this forest, south-east of the camp.',
      'One more thing. Watch: stretch out a strand of goo, catch something, and pull! Light things come to you. Heavy things pull you to them.',
    ],
  },
};

export const aHarderPick: QuestDefinition = {
  id: 'a-harder-pick',
  // v2 (playtest 2026-10-01): the fangs come with the weaver hunt in Beyond the Verdant Gate.
  definitionVersion: 2,
  title: 'A Harder Pick',
  description: 'Stone tools cannot break iron. Bind the weaver fangs into a Reinforced Pickaxe and mine iron ore.',
  category: 'mandatory',
  prerequisites: [{ kind: 'quest-status', questId: 'beyond-the-verdant-gate', status: 'completed' }],
  acquisition: { kind: 'npc', npcIds: [MOSSY] },
  stages: [
    {
      id: 'craft-pickaxe',
      title: 'A pick that bites',
      description: 'Craft a Reinforced Pickaxe at a workbench. There is one in the camp.',
      objectives: [
        { id: 'craft-reinforced-pickaxe', kind: 'craft-item', label: 'Craft a Reinforced Pickaxe (10 wood, 15 stone, 3 fangs)', target: 1, itemIds: ['reinforced-pickaxe'] },
      ],
    },
    {
      id: 'mine-iron',
      title: 'Iron ore',
      description: 'The iron lies in a walled hollow south-east of the camp. Its gate opens for something heavy on the plate: a stone slime, perhaps.',
      objectives: [
        { id: 'collect-iron-ore', kind: 'collect', label: 'Mine iron ore', target: 6, itemIds: ['iron-ore'] },
      ],
    },
  ],
  completion: { kind: 'npc-turn-in', npcIds: [MOSSY] },
  failurePolicy: { kind: 'permanent' },
  abandonmentPolicy: retry,
  rewards: {
    coins: 20,
  },
  dialogue: {
    offer: [
      'Stone tools just bounce off iron. You need something harder.',
      'You have the fangs: bind them to a pick at the workbench, then go and dig some iron.',
      'The ore sits in an old walled hollow south-east of here. Last I saw, its gate only opened for something heavy on the plate.',
    ],
    progress: ['A pick from the bench, iron from the hollow. You will get there.'],
    complete: [
      'Real iron! Now we are getting somewhere.',
      'Ore is no use without a fire hot enough to melt it, though. Slimeshire had a Forge, once.',
      "Pip, the smith's son, has talked of nothing else for years. Go and see him.",
    ],
  },
};

export const rekindleTheForge: QuestDefinition = {
  id: 'rekindle-the-forge',
  definitionVersion: 1,
  title: 'Rekindle the Forge',
  description: "Help Pip rebuild Slimeshire's Forge, then smelt the forest's iron into bars.",
  category: 'mandatory',
  prerequisites: [{ kind: 'quest-status', questId: 'a-harder-pick', status: 'completed' }],
  acquisition: { kind: 'npc', npcIds: [PIP] },
  stages: [
    {
      id: 'restore-forge',
      title: 'Rebuild the Forge',
      description: 'The cold Forge stands in the yard beside your house. Bring 40 stone, 20 wood and 6 iron ore to rebuild it.',
      objectives: [
        { id: 'restore-forge', kind: 'activate-object', label: 'Restore the Forge (40 stone, 20 wood, 6 iron ore)', target: 1, objectIds: ['forge'] },
      ],
    },
    {
      id: 'smelt',
      title: 'Light it up',
      description: 'Use the Forge: char wood into charcoal, then melt iron ore over it into bars.',
      objectives: [
        { id: 'smelt-charcoal', kind: 'craft-item', label: 'Smelt charcoal', target: 2, itemIds: ['charcoal'] },
        { id: 'smelt-iron-bars', kind: 'craft-item', label: 'Smelt iron bars', target: 3, itemIds: ['iron-bar'] },
      ],
    },
  ],
  completion: { kind: 'npc-turn-in', npcIds: [PIP] },
  failurePolicy: { kind: 'permanent' },
  abandonmentPolicy: retry,
  rewards: {
    coins: 40,
    recipeIds: ['craft-iron-spear'],
  },
  dialogue: {
    offer: [
      'You found iron? Real iron, from the forest?',
      "Then we can fix Dad's Forge! It is the cold furnace in the yard beside your house.",
      'It needs stone for the walls, wood for the roof, and iron for the grate. Will you help me?',
    ],
    progress: ['Forty stone, twenty wood, six iron ore. Then we light it!'],
    complete: [
      'Look at it glow! Dad would be so proud.',
      'Here, I remember how he forged a spear. Iron bars and good wood, that is all it takes.',
      'Elder Plop will want to see what you can make with it.',
    ],
  },
};

export const ironGear: QuestDefinition = {
  id: 'iron-gear',
  definitionVersion: 1,
  title: 'Iron Gear',
  description: 'Elder Plop wants to see real iron gear. Forge an Iron Spear.',
  category: 'mandatory',
  prerequisites: [{ kind: 'quest-status', questId: 'rekindle-the-forge', status: 'completed' }],
  acquisition: { kind: 'npc', npcIds: [ELDER] },
  stages: [
    {
      id: 'iron-spear',
      title: 'An iron point',
      description: 'Craft an Iron Spear at a workbench from wood and iron bars.',
      objectives: [
        { id: 'craft-iron-spear', kind: 'craft-item', label: 'Craft an Iron Spear (10 wood, 4 iron bars)', target: 1, itemIds: ['iron-spear'] },
      ],
    },
  ],
  completion: { kind: 'npc-turn-in', npcIds: [ELDER] },
  failurePolicy: { kind: 'permanent' },
  abandonmentPolicy: retry,
  rewards: {
    coins: 40,
    recipeIds: ['craft-iron-axe'],
  },
  dialogue: {
    offer: [
      'The Forge burns again! I could smell it from the plaza.',
      'Stone served us well, but whatever spins those webs in the forest will need iron.',
      'Make yourself an Iron Spear, and show me.',
    ],
    progress: ['Four bars of iron and a good shaft of wood. The workbench will do the rest.'],
    complete: [
      'Now that is a proper weapon.',
      'Take this too: the way to shape an iron axe. Trees fall in a stroke or two, and it bites in a fight.',
      'Mossy sent word from the forest. Something big is nesting in the north-east. Find Mossy when you are ready.',
    ],
  },
};

export const sunnysBasket: QuestDefinition = {
  id: 'sunnys-basket',
  definitionVersion: 1,
  title: "Sunny's Basket",
  description: 'Sunny lost her berry basket across a stream at the northern edge of the forest.',
  category: 'optional',
  prerequisites: [{ kind: 'quest-status', questId: 'beyond-the-verdant-gate', status: 'completed' }],
  acquisition: { kind: 'npc', npcIds: [SUNNY] },
  stages: [
    {
      id: 'fetch-basket',
      title: 'Across the water',
      description: 'The basket sits on the far bank of a stream at the forest\'s northern edge, north of the camp. Too far to wade, close enough to pull.',
      objectives: [
        { id: 'collect-basket', kind: 'collect', label: "Get Sunny's berry basket", target: 1, itemIds: ['berry-basket'] },
      ],
    },
  ],
  completion: { kind: 'npc-turn-in', npcIds: [SUNNY] },
  failurePolicy: { kind: 'permanent' },
  abandonmentPolicy: { kind: 'retryable', reset: 'quest' },
  rewards: {
    coins: 20,
    items: [{ itemId: 'purple-berry-mat', count: 2 }],
  },
  dialogue: {
    offer: [
      'Oh, hello! I came along with Mossy to pick forest berries.',
      'But I set my basket down by the stream at the northern edge, and now it is on the wrong side!',
      'I cannot swim. Could you get it back for me?',
    ],
    progress: ['It is just across the water. If only something could reach over and grab it...'],
    complete: [
      'My basket! And hardly a berry spilled!',
      'Here, have some. Sunshine and berries, the best way to start a day.',
    ],
  },
};

export const theMatronsNest: QuestDefinition = {
  id: 'the-matrons-nest',
  definitionVersion: 1,
  title: "The Matron's Nest",
  description: 'The mother of every orb-weaver nests in the north-east of Gloop Forest. Break her hold on the forest.',
  category: 'mandatory',
  prerequisites: [{ kind: 'quest-status', questId: 'iron-gear', status: 'completed' }],
  acquisition: { kind: 'npc', npcIds: [MOSSY] },
  stages: [
    {
      id: 'defeat-matron',
      title: 'Into the nest',
      description: 'The Matron nests east of the north-eastern thicket. Her volleys mark the ground first: get out of the circles. Webs on the ground catch you, unless you are something sticky.',
      objectives: [
        { id: 'defeat-matron', kind: 'defeat-boss', label: 'Defeat the Orb-Weaver Matron', target: 1, bossIds: ['orb-weaver-matron'] },
      ],
    },
  ],
  completion: { kind: 'automatic' },
  failurePolicy: { kind: 'permanent' },
  abandonmentPolicy: retry,
  rewards: {
    coins: 100,
    abilityIds: ['squash-slam'],
    flags: ['chapter-2-complete'],
  },
  dialogue: {
    offer: [
      'An iron spear! Now you look ready for her.',
      'The Matron. Every weaver in this forest hatched from her nest, north-east of here, past the thicket.',
      'She throws webs that stick to the ground. A sticky slime walks right over them: there is a silk cocoon at the edge of her nest.',
    ],
    progress: ['Watch the ground. When the circles show, move. And keep some silk in you.'],
  },
};

export const CHAPTER_TWO_QUESTS: readonly QuestDefinition[] = [
  beyondTheVerdantGate,
  aHarderPick,
  rekindleTheForge,
  ironGear,
  sunnysBasket,
  theMatronsNest,
];
