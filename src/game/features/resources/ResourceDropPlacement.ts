export interface ResourceDropCell {
  readonly cellX: number;
  readonly cellY: number;
}

export interface ResourceDropPlacement extends ResourceDropCell {
  readonly offsetX: number;
  readonly offsetY: number;
}

function stableOffset(tileSize: number, occurrence: number): { x: number; y: number } {
  if (occurrence === 0) return { x: 0, y: 0 };
  const angle = occurrence * 2.399963229728653;
  const radius = Math.min(tileSize * 0.42, tileSize * 0.1 * Math.sqrt(occurrence));
  return {
    x: Math.round(Math.cos(angle) * radius),
    y: Math.round(Math.sin(angle) * radius),
  };
}

/** Completes a drop request deterministically without exact-position overlap. */
export function completeDropPlacements(
  availableCells: readonly ResourceDropCell[],
  fallbackCell: ResourceDropCell,
  pieces: number,
  tileSize: number,
): readonly ResourceDropPlacement[] {
  const cells = availableCells.slice(0, pieces);
  while (cells.length < pieces) cells.push(fallbackCell);
  const occurrences = new Map<string, number>();
  return cells.map((cell) => {
    const key = `${cell.cellX}:${cell.cellY}`;
    const occurrence = occurrences.get(key) ?? 0;
    occurrences.set(key, occurrence + 1);
    const offset = stableOffset(tileSize, occurrence);
    return { ...cell, offsetX: offset.x, offsetY: offset.y };
  });
}
