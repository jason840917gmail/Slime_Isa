export const MAX_VISIBLE_COUNT = 6;
export const ROW_GAP = 6;
export const LIST_INSET = 16;
export const MIN_ROW_HEIGHT = 40;
export const MAX_ROW_HEIGHT = 46;

export interface CraftingLayoutMetrics {
  readonly capacityCount: number;
  readonly windowCount: number;
  readonly rowHeight: number;
  readonly listHeight: number;
  readonly maxOffset: number;
}

function nonNegativeInteger(value: number, fallback = 0): number {
  if (!Number.isFinite(value)) return fallback;
  return Math.max(0, Math.trunc(value));
}

function safeCameraHeight(cameraHeight: number): number {
  return Number.isFinite(cameraHeight) ? Math.max(1, cameraHeight) : 1;
}

export function visibleCapacity(cameraHeight: number): number {
  const availableHeight = Math.max(1, safeCameraHeight(cameraHeight) - 2 * LIST_INSET);
  return Math.min(
    MAX_VISIBLE_COUNT,
    Math.max(1, Math.floor((availableHeight + ROW_GAP) / (MIN_ROW_HEIGHT + ROW_GAP))),
  );
}

export function rowHeightFor(cameraHeight: number, capacityCount = visibleCapacity(cameraHeight)): number {
  const availableHeight = Math.max(1, safeCameraHeight(cameraHeight) - 2 * LIST_INSET);
  const safeCapacity = Math.min(MAX_VISIBLE_COUNT, Math.max(1, nonNegativeInteger(capacityCount, 1)));
  const naturalHeight = Math.floor((availableHeight - (safeCapacity - 1) * ROW_GAP) / safeCapacity);
  return Math.max(MIN_ROW_HEIGHT, Math.min(MAX_ROW_HEIGHT, naturalHeight));
}

export function clampOffset(offset: number, recipeCount: number, capacityCount: number): number {
  const count = nonNegativeInteger(recipeCount);
  const capacity = Math.min(MAX_VISIBLE_COUNT, Math.max(1, nonNegativeInteger(capacityCount, 1)));
  const maxOffset = Math.max(0, count - capacity);
  const safeOffset = Number.isFinite(offset) ? Math.trunc(offset) : 0;
  return Math.max(0, Math.min(maxOffset, safeOffset));
}

export function getCraftingLayout(recipeCount: number, cameraHeight: number): CraftingLayoutMetrics {
  const count = nonNegativeInteger(recipeCount);
  const capacityCount = visibleCapacity(cameraHeight);
  const windowCount = Math.min(count, capacityCount);
  const rowHeight = rowHeightFor(cameraHeight, capacityCount);
  const listHeight = windowCount > 0
    ? windowCount * rowHeight + (windowCount - 1) * ROW_GAP
    : 0;

  return {
    capacityCount,
    windowCount,
    rowHeight,
    listHeight,
    maxOffset: Math.max(0, count - capacityCount),
  };
}

export function ensureVisible(
  index: number,
  offset: number,
  capacityCount: number,
  recipeCount: number,
): number {
  const count = nonNegativeInteger(recipeCount);
  if (count === 0) return 0;

  const selected = Math.max(0, Math.min(count - 1, nonNegativeInteger(index)));
  const capacity = Math.min(MAX_VISIBLE_COUNT, Math.max(1, nonNegativeInteger(capacityCount, 1)));
  const currentOffset = clampOffset(offset, count, capacity);
  const nextOffset = selected < currentOffset
    ? selected
    : selected >= currentOffset + capacity
      ? selected - capacity + 1
      : currentOffset;
  return clampOffset(nextOffset, count, capacity);
}

export function moveSelection(index: number, delta: number, recipeCount: number): number {
  const count = nonNegativeInteger(recipeCount);
  if (count === 0) return 0;

  const current = Math.max(0, Math.min(count - 1, nonNegativeInteger(index)));
  const step = Number.isFinite(delta) ? Math.trunc(delta) : 0;
  return ((current + step) % count + count) % count;
}

export function visibleRange(
  recipeCount: number,
  offset: number,
  capacityCount: number,
): { readonly start: number; readonly end: number } {
  const count = nonNegativeInteger(recipeCount);
  const safeCapacity = Math.min(MAX_VISIBLE_COUNT, Math.max(1, nonNegativeInteger(capacityCount, 1)));
  const start = clampOffset(offset, count, safeCapacity);
  return { start, end: Math.min(count, start + safeCapacity) };
}
