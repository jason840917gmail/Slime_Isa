export type GroundRegionShape = 'square' | 'rectangle';

export interface GroundSheetRegion {
  readonly startColumn: number;
  readonly startRow: number;
  readonly width: number;
  readonly height: number;
  readonly shape: GroundRegionShape;
}

export interface GroundSheetRegionOptions {
  readonly columns: number;
  readonly rows: number;
  readonly seed: number;
  readonly minWidth?: number;
  readonly maxWidth?: number;
  readonly minHeight?: number;
  readonly maxHeight?: number;
}

function clampInteger(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, Math.floor(value)));
}

function createSeededRandom(seed: number): () => number {
  let state = (seed ^ 0x9e3779b9) >>> 0;

  return (): number => {
    state = (state + 0x6d2b79f5) >>> 0;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

function randomInteger(random: () => number, minimum: number, maximum: number): number {
  return minimum + Math.floor(random() * (maximum - minimum + 1));
}

function reflectedIndex(index: number, length: number): number {
  if (length <= 1) return 0;

  const period = (length - 1) * 2;
  const position = ((index % period) + period) % period;
  return position < length ? position : period - position;
}

/**
 * Picks a deterministic contiguous square or rectangle inside a uniform sheet.
 * The same seed always produces the same region, making map generation debuggable.
 */
export function selectGroundSheetRegion(options: GroundSheetRegionOptions): GroundSheetRegion {
  const columns = Math.max(1, Math.floor(options.columns));
  const rows = Math.max(1, Math.floor(options.rows));
  const minWidth = clampInteger(options.minWidth ?? 6, 1, columns);
  const maxWidth = clampInteger(options.maxWidth ?? 12, minWidth, columns);
  const minHeight = clampInteger(options.minHeight ?? 6, 1, rows);
  const maxHeight = clampInteger(options.maxHeight ?? 12, minHeight, rows);
  const random = createSeededRandom(options.seed);

  const squareMinimum = Math.max(minWidth, minHeight);
  const squareMaximum = Math.min(maxWidth, maxHeight);
  const canSelectSquare = squareMinimum <= squareMaximum;
  const shape: GroundRegionShape = canSelectSquare && random() < 0.5 ? 'square' : 'rectangle';

  let width: number;
  let height: number;

  if (shape === 'square') {
    width = randomInteger(random, squareMinimum, squareMaximum);
    height = width;
  } else {
    width = randomInteger(random, minWidth, maxWidth);
    height = randomInteger(random, minHeight, maxHeight);

    if (width === height && (width < maxWidth || height < maxHeight)) {
      if (width < maxWidth) width += 1;
      else height += 1;
    }
  }

  return {
    startColumn: randomInteger(random, 0, columns - width),
    startRow: randomInteger(random, 0, rows - height),
    width,
    height,
    shape,
  };
}

/**
 * Resolves a world tile to a sheet frame while walking adjacent source cells.
 * Reflection at region edges avoids a hard last-column-to-first-column seam.
 */
export function resolveGroundSheetFrame(
  region: GroundSheetRegion,
  sheetColumns: number,
  tileX: number,
  tileY: number,
): number {
  const column = region.startColumn + reflectedIndex(tileX, region.width);
  const row = region.startRow + reflectedIndex(tileY, region.height);
  return row * sheetColumns + column;
}

// ── sheet-order strategy ─────────────────────────────────────────────────────

export interface OrderedGroundFrame {
  readonly frame: number;
  readonly flipX: boolean;
  readonly flipY: boolean;
}

/**
 * Maps each full-sheet block in natural row/column order. Repeated blocks are
 * true mirrored copies: both frame order and sprite pixels flip. This is the
 * important difference from reflected frame indices alone — without flipping
 * the sprite, the opposite frame edges touch and still create a visible cut.
 *
 * A 19x19 authored sheet therefore appears unchanged in the first block. The
 * next horizontal block is the entire sheet mirrored horizontally, and the
 * next vertical block is mirrored vertically, so pixels meet continuously at
 * every repeat boundary without shrinking the source into a repetitive patch.
 */
export function resolveSheetOrderFrame(
  sheetColumns: number,
  sheetRows: number,
  tileX: number,
  tileY: number,
): OrderedGroundFrame {
  const blockX = Math.floor(tileX / sheetColumns);
  const blockY = Math.floor(tileY / sheetRows);
  const flipX = Math.abs(blockX) % 2 === 1;
  const flipY = Math.abs(blockY) % 2 === 1;
  const localColumn = ((tileX % sheetColumns) + sheetColumns) % sheetColumns;
  const localRow = ((tileY % sheetRows) + sheetRows) % sheetRows;
  const column = flipX ? sheetColumns - 1 - localColumn : localColumn;
  const row = flipY ? sheetRows - 1 - localRow : localRow;

  return {
    frame: row * sheetColumns + column,
    flipX,
    flipY,
  };
}
