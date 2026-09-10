import type { FacingDirection } from '../../infrastructure/persistence/SaveSchema';
import type { WorldDimensions } from '../../world/WorldDimensions';
import type { WorldDropPoint } from './WorldDropMotion';

const FACING_VECTOR: Readonly<Record<FacingDirection, readonly [number, number]>> = {
  up: [0, -1],
  down: [0, 1],
  left: [-1, 0],
  right: [1, 0],
};

export function findInventoryDropDestination(
  source: WorldDropPoint,
  facing: FacingDirection,
  dimensions: WorldDimensions,
  isCellBlocked: (cellX: number, cellY: number) => boolean,
): WorldDropPoint | undefined {
  const sourceCellX = Math.floor(source.x / dimensions.tileSize);
  const sourceCellY = Math.floor(source.y / dimensions.tileSize) - 1;
  const [forwardX, forwardY] = FACING_VECTOR[facing];
  const leftX = forwardY;
  const leftY = -forwardX;
  // Keep the landing outside the player's pickup body so a successful drop
  // remains on the ground instead of being collected as soon as it settles.
  const landingDistance = 2;
  const offsets: ReadonlyArray<readonly [number, number]> = [
    [forwardX * landingDistance, forwardY * landingDistance],
    [leftX * landingDistance, leftY * landingDistance],
    [-leftX * landingDistance, -leftY * landingDistance],
    [-forwardX * landingDistance, -forwardY * landingDistance],
    [(forwardX + leftX) * landingDistance, (forwardY + leftY) * landingDistance],
    [(forwardX - leftX) * landingDistance, (forwardY - leftY) * landingDistance],
    [(-forwardX + leftX) * landingDistance, (-forwardY + leftY) * landingDistance],
    [(-forwardX - leftX) * landingDistance, (-forwardY - leftY) * landingDistance],
  ];
  for (const [offsetX, offsetY] of offsets) {
    const cellX = sourceCellX + offsetX;
    const cellY = sourceCellY + offsetY;
    if (isCellBlocked(cellX, cellY)) continue;
    return {
      x: cellX * dimensions.tileSize + dimensions.tileSize / 2,
      y: (cellY + 1) * dimensions.tileSize,
    };
  }
  return undefined;
}
