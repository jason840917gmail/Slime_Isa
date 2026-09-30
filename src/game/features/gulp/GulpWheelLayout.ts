/** Hold W this long (ms) to open the quick wheel; a shorter press is a tap. */
export const GULP_WHEEL_HOLD_MS = 250;

/**
 * Where slot `index` of `count` sits on the quick wheel, in degrees
 * (0 = right, 90 = down, screen coordinates): the first slot is at the top and
 * the rest follow clockwise, evenly spaced.
 */
export function gulpWheelSlotAngle(index: number, count: number): number {
  return -90 + (index * 360) / Math.max(1, count);
}

/**
 * The slot a direction points at (arrow keys or the mouse, relative to the
 * slime), or undefined when there is no direction. Picks the nearest slot
 * angle, so any direction always chooses something.
 */
export function pickGulpWheelSlot(direction: Readonly<{ x: number; y: number }>, count: number): number | undefined {
  if (count < 1 || Math.hypot(direction.x, direction.y) < 1e-6) return undefined;
  const angle = (Math.atan2(direction.y, direction.x) * 180) / Math.PI;
  let best = 0;
  let bestDistance = Number.POSITIVE_INFINITY;
  for (let index = 0; index < count; index += 1) {
    const raw = Math.abs(angle - gulpWheelSlotAngle(index, count)) % 360;
    const distance = Math.min(raw, 360 - raw);
    if (distance < bestDistance) {
      best = index;
      bestDistance = distance;
    }
  }
  return best;
}
