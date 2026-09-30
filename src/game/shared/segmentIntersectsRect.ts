export interface SegmentPoint {
  readonly x: number;
  readonly y: number;
}

/**
 * Whether the segment from `from` to `to` crosses the axis-aligned box at
 * (`x`, `y`) of `width` × `height` (Liang–Barsky clipping). A segment that
 * starts or ends inside the box crosses it.
 */
export function segmentIntersectsRect(from: SegmentPoint, to: SegmentPoint, x: number, y: number, width: number, height: number): boolean {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  let enter = 0;
  let exit = 1;
  const edges: readonly (readonly [number, number])[] = [
    [-dx, from.x - x],
    [dx, x + width - from.x],
    [-dy, from.y - y],
    [dy, y + height - from.y],
  ];
  for (const [p, q] of edges) {
    if (p === 0) {
      if (q < 0) return false;
      continue;
    }
    const t = q / p;
    if (p < 0) {
      if (t > exit) return false;
      if (t > enter) enter = t;
    } else {
      if (t < enter) return false;
      if (t < exit) exit = t;
    }
  }
  return enter <= exit;
}
