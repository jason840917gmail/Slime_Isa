export interface CharacterClipUsage {
  readonly characterId?: string;
  readonly kind?: 'player' | 'enemy';
  readonly visualSetId?: string;
  readonly clipId: string;
  readonly owner: string;
}

const usages: CharacterClipUsage[] = [];

export function registerCharacterClipUsage(usage: CharacterClipUsage): () => void {
  usages.push({ ...usage });
  return () => {
    const index = usages.indexOf(usage);
    if (index >= 0) usages.splice(index, 1);
  };
}

export function getCharacterClipUsages(): readonly CharacterClipUsage[] {
  return usages.map((usage) => ({ ...usage }));
}

export function findCharacterClipUsages(clipId: string): readonly CharacterClipUsage[] {
  return usages.filter((usage) => usage.clipId === clipId).map((usage) => ({ ...usage }));
}
