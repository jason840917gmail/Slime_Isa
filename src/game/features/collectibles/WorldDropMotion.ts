export interface WorldDropPoint {
  readonly x: number;
  readonly y: number;
}

export const WORLD_DROP_FLIGHT_MS = 280;
export const WORLD_DROP_REBOUND_MS = 40;
export const WORLD_DROP_SETTLE_MS = 60;
export const WORLD_DROP_STAGGER_MS = 60;
export const WORLD_DROP_REBOUND_HEIGHT = 4;
export const WORLD_DROP_MIN_ARC_HEIGHT = 28;
export const WORLD_DROP_MAX_ARC_HEIGHT = 56;
export const WORLD_DROP_ARC_DISTANCE_MULTIPLIER = 0.45;

export function resolveWorldDropArcHeight(source: WorldDropPoint, destination: WorldDropPoint): number {
  const distance = Math.hypot(destination.x - source.x, destination.y - source.y);
  return Math.max(
    WORLD_DROP_MIN_ARC_HEIGHT,
    Math.min(WORLD_DROP_MAX_ARC_HEIGHT, distance * WORLD_DROP_ARC_DISTANCE_MULTIPLIER),
  );
}

export function resolveWorldDropTrajectory(
  source: WorldDropPoint,
  destination: WorldDropPoint,
  progress: number,
): WorldDropPoint {
  const t = Math.max(0, Math.min(1, Number.isFinite(progress) ? progress : 0));
  const height = resolveWorldDropArcHeight(source, destination);
  const lift = 4 * height * t * (1 - t);
  return {
    x: source.x + (destination.x - source.x) * t,
    y: source.y + (destination.y - source.y) * t - lift,
  };
}
