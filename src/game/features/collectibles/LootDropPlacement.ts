/** Consecutive pieces turn by the golden angle, so any number of them spread evenly around the corpse. */
const GOLDEN_ANGLE = Math.PI * (3 - Math.sqrt(5));
/** Loot lands this far from the enemy, in tiles (first, second and third ring). */
const LOOT_RINGS = [0.45, 0.6, 0.75] as const;
/** The ground is seen at three-quarter view: offsets are squashed vertically. */
const LOOT_VERTICAL_SCALE = 0.7;
/** Tries per piece before it falls on the corpse itself. */
const LOOT_TURNS = 8;

/**
 * Where each piece of an enemy's loot lands: a deterministic scatter around
 * the enemy (no random trajectories), skipping points `isBlocked` refuses
 * (walls, trees, water); a piece with nowhere free lands on the enemy itself.
 */
export function scatterLootDestinations(
  source: Readonly<{ x: number; y: number }>,
  count: number,
  tileSize: number,
  isBlocked: (x: number, y: number) => boolean,
): { x: number; y: number }[] {
  return Array.from({ length: Math.max(0, count) }, (_, index) => {
    const radius = tileSize * LOOT_RINGS[index % LOOT_RINGS.length]!;
    for (let turn = 0; turn < LOOT_TURNS; turn += 1) {
      const angle = index * GOLDEN_ANGLE + (turn * Math.PI * 2) / LOOT_TURNS;
      const point = {
        x: Math.round(source.x + Math.cos(angle) * radius),
        y: Math.round(source.y + Math.sin(angle) * radius * LOOT_VERTICAL_SCALE),
      };
      if (!isBlocked(point.x, point.y)) return point;
    }
    return { x: Math.round(source.x), y: Math.round(source.y) };
  });
}
