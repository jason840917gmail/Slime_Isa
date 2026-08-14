export const PREVIEW_ZOOM_MIN = 0.5;
export const PREVIEW_ZOOM_MAX = 3;
export const PREVIEW_ZOOM_STEP = 0.1;

function roundZoom(value: number): number {
  return Math.round(value * 100) / 100;
}

export function clampPreviewZoom(value: number): number {
  if (!Number.isFinite(value)) return 1;
  return roundZoom(Math.max(PREVIEW_ZOOM_MIN, Math.min(PREVIEW_ZOOM_MAX, value)));
}

export function adjustPreviewZoom(current: number, deltaY: number): number {
  if (!Number.isFinite(deltaY) || deltaY === 0) return clampPreviewZoom(current);
  const direction = deltaY < 0 ? 1 : -1;
  return clampPreviewZoom(current + direction * PREVIEW_ZOOM_STEP);
}
