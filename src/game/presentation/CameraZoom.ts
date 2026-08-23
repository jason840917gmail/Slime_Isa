export const DEFAULT_CAMERA_ZOOM = 1;

/**
 * Wheel zoom keeps the existing overview range while making integer 1x the
 * normal gameplay presentation.
 */
export const CAMERA_ZOOM_LEVELS = [0.5, 0.625, 0.75, 0.875, 1, 1.125, 1.25] as const;

const ZOOM_EPSILON = 0.000_001;

export type CameraRenderingMode = 'gameplay' | 'overview';

export function isIntegerCameraZoom(zoom: number): boolean {
  return Number.isFinite(zoom) && Math.abs(zoom - Math.round(zoom)) < ZOOM_EPSILON;
}

export function cameraRenderingMode(zoom: number): CameraRenderingMode {
  return isIntegerCameraZoom(zoom) ? 'gameplay' : 'overview';
}

export function closestCameraZoomIndex(value: number): number {
  return CAMERA_ZOOM_LEVELS.reduce(
    (closestIndex, zoom, index, levels) =>
      Math.abs(levels[closestIndex] - value) <= Math.abs(zoom - value)
        ? closestIndex
        : index,
    0,
  );
}

export function nextCameraZoom(currentZoom: number, deltaY: number): number {
  if (deltaY === 0) return currentZoom;

  const currentIndex = closestCameraZoomIndex(currentZoom);
  const direction = deltaY < 0 ? 1 : -1;
  const nextIndex = Math.max(
    0,
    Math.min(CAMERA_ZOOM_LEVELS.length - 1, currentIndex + direction),
  );
  return CAMERA_ZOOM_LEVELS[nextIndex];
}
