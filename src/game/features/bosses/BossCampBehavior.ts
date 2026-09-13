import type { MapEnemyAreaPerimeter } from '../../content/maps/mapFormat';

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
