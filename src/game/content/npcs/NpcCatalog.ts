export interface NpcDefinition {
  readonly id: string;
  readonly displayName: string;
  readonly visualId?: string;
  readonly description?: string;
}

export const NPC_DEFINITIONS: readonly NpcDefinition[] = [
  {
    id: 'village-elder-plop',
    displayName: 'Village Elder Plop',
    description: 'A patient elder who watches over the village path.',
  },
  {
    id: 'level-1-spider-giver',
    displayName: 'Mossy Scout',
    description: 'A scout who has seen trouble in Gloop Forest.',
  },
] as const;

const NPC_BY_ID = new Map(NPC_DEFINITIONS.map((npc) => [npc.id, npc]));

export function getNpcDefinition(npcId: string): NpcDefinition | undefined {
  return NPC_BY_ID.get(npcId);
}

export function getNpcIds(): readonly string[] {
  return NPC_DEFINITIONS.map((npc) => npc.id);
}
