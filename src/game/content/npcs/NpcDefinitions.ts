/** Catalog-neutral NPC identity data shared by browser and Node tooling. */
export interface NpcDefinition {
  readonly id: string;
  readonly characterId: string;
  readonly displayName: string;
  readonly description?: string;
}

export const NPC_DEFINITIONS: readonly NpcDefinition[] = [
  {
    id: 'village-elder-plop',
    characterId: 'village-elder-plop',
    displayName: 'Village Elder Plop',
    description: 'A patient elder who watches over the village path.',
  },
  {
    id: 'level-1-spider-giver',
    characterId: 'mossy-scout',
    displayName: 'Mossy',
    description: 'A purple scout who has seen trouble in Gloop Forest.',
  },
  {
    id: 'lili',
    characterId: 'lili',
    displayName: 'Lili',
    description: "Hi, I'm Lili! There is always room for one more friend in our clearing.",
  },
  {
    id: 'red-slime-boy',
    characterId: 'red-slime-boy',
    displayName: 'Red Slime Boy',
    description: 'Race you to the next patch of grass! Ready, steady... squish!',
  },
  {
    id: 'yellow-blond-slime-girl',
    characterId: 'yellow-blond-slime-girl',
    displayName: 'Yellow Blond Slime Girl',
    description: 'A little sunshine makes every adventure brighter!',
  },
] as const;
