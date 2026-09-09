import { NPC_DEFINITIONS, type NpcDefinition } from './NpcDefinitions';

export { NPC_DEFINITIONS } from './NpcDefinitions';
export type { NpcDefinition } from './NpcDefinitions';

const NPC_BY_ID = new Map(NPC_DEFINITIONS.map((npc) => [npc.id, npc]));

export interface NpcCharacterReference {
  readonly characterId: string;
  readonly kind: string;
}

/** Validates catalog-to-character links without importing browser/Vite content. */
export function validateNpcCatalogReferences(
  resolveCharacter: (characterId: string) => NpcCharacterReference | undefined,
): void {
  const issues: string[] = [];
  const owners = new Map<string, string>();
  for (const npc of NPC_DEFINITIONS) {
    const character = resolveCharacter(npc.characterId);
    if (!character) {
      issues.push(`${npc.id}.characterId: unknown character '${npc.characterId}'`);
      continue;
    }
    if (character.kind !== 'npc') issues.push(`${npc.id}.characterId: '${npc.characterId}' must reference an NPC character package`);
    const previous = owners.get(npc.characterId);
    if (previous) issues.push(`${npc.id}.characterId: character '${npc.characterId}' is already owned by '${previous}'`);
    else owners.set(npc.characterId, npc.id);
  }
  if (issues.length > 0) throw new Error(`Invalid NPC catalog references:\n  - ${issues.join('\n  - ')}`);
}

export function getNpcDefinition(npcId: string): NpcDefinition | undefined {
  return NPC_BY_ID.get(npcId);
}

export function getNpcIds(): readonly string[] {
  return NPC_DEFINITIONS.map((npc) => npc.id);
}
