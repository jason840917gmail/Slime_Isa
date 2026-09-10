import type { FacingDirection } from '../../infrastructure/persistence/SaveSchema';
import type { WorldDimensions } from '../../world/WorldDimensions';
import type { WorldDropPoint } from './WorldDropMotion';

export type InventoryDropCellInspection =
  | { readonly kind: 'open' }
  | { readonly kind: 'blocked' }
  | { readonly kind: 'compatible-stack'; readonly destination: WorldDropPoint };

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
  inspectCell: (cellX: number, cellY: number) => InventoryDropCellInspection,
): WorldDropPoint | undefined {
  const sourceCellX = Math.floor(source.x / dimensions.tileSize);
  const sourceCellY = Math.floor(source.y / dimensions.tileSize) - 1;
  const [forwardX, forwardY] = FACING_VECTOR[facing];
  const leftX = forwardY;
  const leftY = -forwardX;
  const maxRadius = Math.max(dimensions.columns, dimensions.rows);
  // Radius one is intentionally skipped so the pickup body cannot immediately
  // recollect a drop when it becomes active after landing.
  for (let radius = 2; radius <= maxRadius; radius += 1) {
    const candidates: Array<{ cellX: number; cellY: number; forward: number; side: number }> = [];
    for (let offsetY = -radius; offsetY <= radius; offsetY += 1) {
      for (let offsetX = -radius; offsetX <= radius; offsetX += 1) {
        if (Math.max(Math.abs(offsetX), Math.abs(offsetY)) !== radius) continue;
        const cellX = sourceCellX + offsetX;
        const cellY = sourceCellY + offsetY;
        if (cellX < 0 || cellY < 0 || cellX >= dimensions.columns || cellY >= dimensions.rows) continue;
        candidates.push({
          cellX,
          cellY,
          forward: offsetX * forwardX + offsetY * forwardY,
          side: offsetX * leftX + offsetY * leftY,
        });
      }
    }
    candidates.sort((a, b) => b.forward - a.forward
      || Math.abs(a.side) - Math.abs(b.side)
      || b.side - a.side
      || a.cellY - b.cellY
      || a.cellX - b.cellX);
    let firstOpen: { cellX: number; cellY: number } | undefined;
    for (const candidate of candidates) {
      const inspection = inspectCell(candidate.cellX, candidate.cellY);
      if (inspection.kind === 'blocked') continue;
      if (inspection.kind === 'compatible-stack') return inspection.destination;
      firstOpen ??= candidate;
    }
    if (firstOpen) {
      return {
        x: firstOpen.cellX * dimensions.tileSize + dimensions.tileSize / 2,
        y: (firstOpen.cellY + 1) * dimensions.tileSize,
      };
    }
  }
  return undefined;
}
