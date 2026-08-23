export interface PresentationPoint {
  readonly x: number;
  readonly y: number;
}

export interface DeadzoneSize {
  readonly width: number;
  readonly height: number;
}

export const CAMERA_DAMPING_RATE = 12;

/** Phaser keeps camera scroll relative to the unzoomed viewport midpoint. */
export function cameraCenterFromScroll(
  scrollX: number,
  scrollY: number,
  viewportWidth: number,
  viewportHeight: number,
): PresentationPoint {
  return {
    x: scrollX + viewportWidth / 2,
    y: scrollY + viewportHeight / 2,
  };
}

export function responsiveDeadzoneSize(viewportWidth: number, viewportHeight: number): DeadzoneSize {
  return {
    width: Math.max(128, Math.min(224, viewportWidth * 0.18)),
    height: Math.max(96, Math.min(160, viewportHeight * 0.14)),
  };
}

export function resolveDeadzoneCenter(
  current: PresentationPoint,
  target: PresentationPoint,
  halfWidth: number,
  halfHeight: number,
): PresentationPoint {
  let x = current.x;
  let y = current.y;

  if (target.x < current.x - halfWidth) x = target.x + halfWidth;
  else if (target.x > current.x + halfWidth) x = target.x - halfWidth;

  if (target.y < current.y - halfHeight) y = target.y + halfHeight;
  else if (target.y > current.y + halfHeight) y = target.y - halfHeight;

  return { x, y };
}

export function exponentialDampingFactor(
  deltaMs: number,
  dampingRate = CAMERA_DAMPING_RATE,
): number {
  if (!Number.isFinite(deltaMs) || deltaMs <= 0) return 0;
  if (!Number.isFinite(dampingRate) || dampingRate <= 0) return 1;
  return 1 - Math.exp(-dampingRate * Math.min(deltaMs, 100) / 1000);
}

export function interpolatePhysicsPosition(
  current: PresentationPoint,
  lastStepDelta: PresentationPoint,
  alpha: number,
): PresentationPoint {
  const resolvedAlpha = Math.max(0, Math.min(1, Number.isFinite(alpha) ? alpha : 1));
  return {
    x: current.x - lastStepDelta.x * (1 - resolvedAlpha),
    y: current.y - lastStepDelta.y * (1 - resolvedAlpha),
  };
}
