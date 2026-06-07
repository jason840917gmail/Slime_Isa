const TILE_SIZE = 64;
const WORLD_TILES_X = 54;
const WORLD_TILES_Y = 54;

export const WORLD_WIDTH = WORLD_TILES_X * TILE_SIZE;
export const WORLD_HEIGHT = WORLD_TILES_Y * TILE_SIZE;

export const CELL_SIZE = 64;

export function sample(tileX: number, tileY: number): number {
  const value = Math.sin(tileX * 12.9898 + tileY * 78.233) * 43758.5453;
  const fraction = value - Math.floor(value);
  const wave = (Math.sin(tileX * 0.25) + Math.cos(tileY * 0.32) + 2) / 4;

  return Phaser.Math.Clamp(fraction * 0.45 + wave * 0.55, 0, 1);
}

export { TILE_SIZE, WORLD_TILES_X, WORLD_TILES_Y };