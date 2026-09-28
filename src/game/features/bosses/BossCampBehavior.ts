import type { MapEnemyAreaPerimeter } from '../../content/maps/mapFormat';
import type { SensorShape } from '../../runtime/scene/physics/SensorGeometry';

/** Converts an authored Area2D circle/rectangle shape (world space) into a boss perimeter. */
export function bossPerimeterFromSensorShape(shape: SensorShape): MapEnemyAreaPerimeter | undefined {
  if (shape.shape === 'circle') return { shape: 'circle', x: shape.centerX, y: shape.centerY, radius: shape.radius };
  if (shape.shape === 'rectangle') return { shape: 'rectangle', x: shape.x, y: shape.y, w: shape.width, h: shape.height };
  return undefined;
}

export function bossArenaCenter(perimeter: MapEnemyAreaPerimeter): Readonly<{ x: number; y: number }> {
  return perimeter.shape === 'circle'
    ? { x: perimeter.x, y: perimeter.y }
    : { x: perimeter.x + perimeter.w / 2, y: perimeter.y + perimeter.h / 2 };
}

export function clampToBossArena(
  perimeter: MapEnemyAreaPerimeter,
  point: Readonly<{ x: number; y: number }>,
): { x: number; y: number } {
  if (perimeter.shape === 'rectangle') {
    return {
      x: Math.min(perimeter.x + perimeter.w, Math.max(perimeter.x, point.x)),
      y: Math.min(perimeter.y + perimeter.h, Math.max(perimeter.y, point.y)),
    };
  }
  const dx = point.x - perimeter.x;
  const dy = point.y - perimeter.y;
  const length = Math.hypot(dx, dy);
  if (length <= perimeter.radius) return { x: point.x, y: point.y };
  return { x: perimeter.x + (dx / length) * perimeter.radius, y: perimeter.y + (dy / length) * perimeter.radius };
}

export function bossPerimeterContains(perimeter: MapEnemyAreaPerimeter, x: number, y: number): boolean {
  if (![x, y, perimeter.x, perimeter.y].every(Number.isFinite)) return false;
  if (perimeter.shape === 'rectangle') {
    return x >= perimeter.x && x <= perimeter.x + perimeter.w
      && y >= perimeter.y && y <= perimeter.y + perimeter.h;
  }
  const dx = x - perimeter.x;
  const dy = y - perimeter.y;
  return dx * dx + dy * dy <= perimeter.radius * perimeter.radius;
}

export function bossCampSpawnEligible(input: {
  readonly hasLiveBoss: boolean;
  readonly insideActivation: boolean;
  readonly respawnReadyAtEpochMs?: number;
  readonly observedOutsideAfterDefeat: boolean;
  readonly epochNow: number;
}): boolean {
  if (input.hasLiveBoss || !input.insideActivation) return false;
  if (input.respawnReadyAtEpochMs === undefined) return true;
  return input.observedOutsideAfterDefeat && input.epochNow >= input.respawnReadyAtEpochMs;
}

export interface BossCampSpawnSuppressionState {
  readonly suppressSpawnUntilOutside: boolean;
  readonly blocksSpawnThisUpdate: boolean;
}

export function resolveBossCampSpawnSuppression(
  suppressSpawnUntilOutside: boolean,
  insideActivation: boolean,
): BossCampSpawnSuppressionState {
  if (!suppressSpawnUntilOutside) {
    return { suppressSpawnUntilOutside: false, blocksSpawnThisUpdate: false };
  }
  return {
    suppressSpawnUntilOutside: insideActivation,
    blocksSpawnThisUpdate: true,
  };
}
