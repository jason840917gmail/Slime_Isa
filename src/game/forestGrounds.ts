export const FOREST_GROUNDS_SHEET_KEY = 'forest-grounds-sheet';
export const NORMALIZED_GROUND_TILE_SIZE = 64;

export type ForestGroundFrameId = keyof typeof FOREST_GROUND_FRAME_COORDS;

type ForestGroundFrameCoord = {
  column: number;
  row: number;
};

export type ForestGroundTextureDef = {
  key: string;
  frame: ForestGroundFrameId;
};

const SHEET_COLUMN_LINES = [2, 120, 234, 346, 458, 570, 682, 793, 904, 1017, 1134, 1251] as const;
const SHEET_ROW_LINES = [1, 111, 216, 319, 420, 520, 619, 716, 808, 901, 993, 1083, 1163, 1252] as const;

export const FOREST_GROUND_FRAME_COORDS = {
  singleGround: { column: 2, row: 0 },
  lushGrass: { column: 0, row: 0 },
  fineGrass: { column: 1, row: 0 },
  flowerGrass: { column: 2, row: 0 },
  leafyGrass: { column: 4, row: 0 },
  mossGrass: { column: 5, row: 0 },
  vineGrass: { column: 6, row: 0 },
  meadowWater: { column: 0, row: 7 },
  tealWater: { column: 1, row: 7 },
  deepWater: { column: 3, row: 7 },
  mossStone: { column: 10, row: 5 },
  cobbleStone: { column: 9, row: 6 },
  grassStoneEdge: { column: 10, row: 0 },
} as const satisfies Record<string, ForestGroundFrameCoord>;

export const FIRST_SCENE_GROUND_TEXTURES = [
  { key: 'grass-a', frame: 'singleGround' },
  { key: 'grass-a-1', frame: 'singleGround' },
  { key: 'grass-a-2', frame: 'singleGround' },
  { key: 'grass-b', frame: 'singleGround' },
  { key: 'grass-b-1', frame: 'singleGround' },
  { key: 'grass-b-2', frame: 'singleGround' },
  { key: 'water', frame: 'singleGround' },
  { key: 'water-1', frame: 'singleGround' },
  { key: 'water-2', frame: 'singleGround' },
  { key: 'rock-wall', frame: 'singleGround' },
  { key: 'rock-wall-1', frame: 'singleGround' },
  { key: 'rock-wall-2', frame: 'singleGround' },
] as const satisfies readonly ForestGroundTextureDef[];

export function getForestGroundFrameRect(frameId: ForestGroundFrameId): {
  x: number;
  y: number;
  width: number;
  height: number;
} {
  const frame = FOREST_GROUND_FRAME_COORDS[frameId];
  const leftLine = SHEET_COLUMN_LINES[frame.column];
  const rightLine = SHEET_COLUMN_LINES[frame.column + 1];
  const topLine = SHEET_ROW_LINES[frame.row];
  const bottomLine = SHEET_ROW_LINES[frame.row + 1];

  return {
    x: leftLine + 1,
    y: topLine + 1,
    width: rightLine - leftLine - 2,
    height: bottomLine - topLine - 2,
  };
}
