/** Catalog-neutral NPC identity data shared by browser and Node tooling. */
export interface NpcDefinition {
  readonly id: string;
  readonly characterId: string;
  readonly displayName: string;
  readonly description?: string;
  /** Pages shown in the conversation box when talking (falls back to `description`). */
  readonly dialogue?: readonly string[];
}

export const NPC_DEFINITIONS: readonly NpcDefinition[] = [
  {
    id: 'village-elder-plop',
    characterId: 'village-elder-plop',
    displayName: 'Village Elder Plop',
    description: 'A patient elder who watches over the village path.',
    dialogue: [
      'Ah, a young slime on the move. Welcome, welcome.',
      'I have watched over this village path for more seasons than I can count.',
      'Keep your goo bright and your eyes open. The forest has grown restless lately.',
    ],
  },
  {
    id: 'level-1-spider-giver',
    characterId: 'mossy-scout',
    displayName: 'Mossy',
    description: 'A purple scout who has seen trouble in Gloop Forest.',
    dialogue: [
      'Psst! Over here. Keep your voice down.',
      "I've been scouting Gloop Forest. Something with too many legs is spinning webs out there.",
      "If you're heading in, stay light on your feet.",
    ],
  },
  {
    id: 'lili',
    characterId: 'lili',
    displayName: 'Lili',
    description: "Hi, I'm Lili! There is always room for one more friend in our clearing.",
    dialogue: [
      "Hi, I'm Lili!",
      'There is always room for one more friend in our clearing.',
      'Come back and visit anytime, okay?',
    ],
  },
  {
    id: 'red-slime-boy',
    characterId: 'red-slime-boy',
    displayName: 'Pip',
    description: "The smith's son. He has wanted to light the Forge again since the worms came.",
    dialogue: [
      "I'm Pip! My dad was Slimeshire's smith, before the worms chased him off.",
      'The Forge in the yard by your house has been cold ever since.',
      'One day I am going to light it again. You will see!',
    ],
  },
  {
    id: 'yellow-blond-slime-girl',
    characterId: 'yellow-blond-slime-girl',
    displayName: 'Sunny',
    description: 'A little sunshine makes every adventure brighter!',
    dialogue: [
      'A little sunshine makes every adventure brighter!',
      'When I feel gloomy, I just bounce in the sun until it goes away.',
    ],
  },
  {
    id: 'fisherman-slime',
    characterId: 'fisherman-slime',
    displayName: 'Lily the Fishergirl',
    description: 'Patience, friend. The big one always bites right after you give up.',
    dialogue: [
      "Shh... you'll scare the fish.",
      'Patience, friend. The big one always bites right after you give up.',
    ],
  },
] as const;
