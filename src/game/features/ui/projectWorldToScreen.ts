import type Phaser from 'phaser';

/** Invert the camera's public screen-to-world mapping for DOM overlay placement. */
export function projectWorldToScreen(
  camera: Phaser.Cameras.Scene2D.Camera,
  x: number,
  y: number,
): Readonly<{ x: number; y: number }> {
  const origin = camera.getWorldPoint(0, 0);
  const horizontal = camera.getWorldPoint(1, 0);
  const vertical = camera.getWorldPoint(0, 1);
  const ax = horizontal.x - origin.x;
  const ay = horizontal.y - origin.y;
  const bx = vertical.x - origin.x;
  const by = vertical.y - origin.y;
  const determinant = ax * by - ay * bx;
  if (!Number.isFinite(determinant) || Math.abs(determinant) < 1e-9) return { x: 0, y: 0 };
  const dx = x - origin.x;
  const dy = y - origin.y;
  return { x: (dx * by - dy * bx) / determinant, y: (dy * ax - dx * ay) / determinant };
}
