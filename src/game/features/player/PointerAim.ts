/** A pointer closer than this to the slime does not give a direction. */
export const POINTER_DEAD_ZONE_PX = 16;

export interface PointerAim {
  /** Unit vector from the slime toward the pointer. */
  readonly x: number;
  readonly y: number;
  /** How far the pointer is, in world pixels. */
  readonly distance: number;
}

/** Where the pointer is from `from`, or undefined when it sits on the slime. */
export function aimToward(
  from: Readonly<{ x: number; y: number }>,
  to: Readonly<{ x: number; y: number }>,
  deadZonePx = POINTER_DEAD_ZONE_PX,
): PointerAim | undefined {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const distance = Math.hypot(dx, dy);
  if (!Number.isFinite(distance) || distance < deadZonePx) return undefined;
  return { x: dx / distance, y: dy / distance, distance };
}

/**
 * Up, down, left or right: the larger of the horizontal and vertical parts
 * wins, ties going sideways (the same rule as weapon swing directions).
 */
export function snapToCardinal(direction: Readonly<{ x: number; y: number }>): { x: number; y: number } {
  if (Math.abs(direction.x) >= Math.abs(direction.y)) return { x: direction.x < 0 ? -1 : 1, y: 0 };
  return { x: 0, y: direction.y < 0 ? -1 : 1 };
}
