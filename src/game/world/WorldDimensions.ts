/** Immutable geometry shared by every system operating in one loaded map. */
export interface WorldDimensions {
  readonly tileSize: number;
  readonly columns: number;
  readonly rows: number;
  readonly width: number;
  readonly height: number;
}

export function createWorldDimensions(
  tileSize: number,
  columns: number,
  rows: number,
): WorldDimensions {
  if (!Number.isInteger(tileSize) || tileSize <= 0
      || !Number.isInteger(columns) || columns <= 0
      || !Number.isInteger(rows) || rows <= 0) {
    throw new Error('World dimensions require positive integer tileSize, columns, and rows');
  }

  return Object.freeze({
    tileSize,
    columns,
    rows,
    width: columns * tileSize,
    height: rows * tileSize,
  });
}

export function dimensionsFromMap(
  map: {
    readonly tileSize: number;
    readonly size: { readonly columns: number; readonly rows: number };
  },
): WorldDimensions {
  return createWorldDimensions(map.tileSize, map.size.columns, map.size.rows);
}
