import type { ResourceId } from '../../content/scenes/identifiers';
import type { TileDataResourceDocument } from '../../content/scenes/resources/types';

export interface TileCoordinate {
  readonly x: number;
  readonly y: number;
}

export interface TilePaintCommand {
  readonly label: string;
  apply(document: TileDataResourceDocument): TileDataResourceDocument;
}

type MutableTileData = {
  version: 1;
  resourceId: ResourceId;
  kind: 'tile-data';
  tileSet: ResourceId;
  columns: number;
  rows: number;
  cells: Array<{ x: number; y: number; tileId: string }>;
};

function key(x: number, y: number): string { return `${x},${y}`; }

function assertCoordinate(document: TileDataResourceDocument, coordinate: TileCoordinate): void {
  if (!Number.isSafeInteger(coordinate.x) || !Number.isSafeInteger(coordinate.y)
    || coordinate.x < 0 || coordinate.y < 0
    || coordinate.x >= document.columns || coordinate.y >= document.rows) {
    throw new Error(`Tile coordinate '${coordinate.x},${coordinate.y}' is outside ${document.columns}x${document.rows}`);
  }
}

function mutate(
  label: string,
  mutation: (draft: MutableTileData) => void,
): TilePaintCommand {
  return {
    label,
    apply(document) {
      const draft = structuredClone(document) as MutableTileData;
      mutation(draft);
      draft.cells.sort((left, right) => left.y - right.y || left.x - right.x);
      return draft;
    },
  };
}

function replaceCells(
  draft: MutableTileData,
  coordinates: readonly TileCoordinate[],
  tileId?: string,
): void {
  const replacements = new Set<string>();
  for (const coordinate of coordinates) {
    assertCoordinate(draft, coordinate);
    replacements.add(key(coordinate.x, coordinate.y));
  }
  draft.cells = draft.cells.filter((cell) => !replacements.has(key(cell.x, cell.y)));
  if (tileId) {
    for (const coordinate of coordinates) draft.cells.push({ x: coordinate.x, y: coordinate.y, tileId });
  }
}

export function brushCoordinates(
  center: TileCoordinate,
  size: number,
  bounds: Readonly<{ columns: number; rows: number }>,
): readonly TileCoordinate[] {
  if (!Number.isSafeInteger(size) || size < 1 || size > 9 || size % 2 === 0) {
    throw new Error('Tile brush size must be an odd integer from 1 through 9');
  }
  const radius = Math.floor(size / 2);
  const cells: TileCoordinate[] = [];
  for (let y = center.y - radius; y <= center.y + radius; y += 1) {
    for (let x = center.x - radius; x <= center.x + radius; x += 1) {
      if (x >= 0 && y >= 0 && x < bounds.columns && y < bounds.rows) cells.push({ x, y });
    }
  }
  return cells;
}

export const tilePaintCommands = {
  paint(coordinates: readonly TileCoordinate[], tileId: string): TilePaintCommand {
    if (!tileId.trim()) throw new Error('Tile paint requires a stable tile ID');
    return mutate(`Paint ${tileId}`, (draft) => replaceCells(draft, coordinates, tileId));
  },

  erase(coordinates: readonly TileCoordinate[]): TilePaintCommand {
    return mutate('Erase tiles', (draft) => replaceCells(draft, coordinates));
  },

  fill(origin: TileCoordinate, tileId: string): TilePaintCommand {
    if (!tileId.trim()) throw new Error('Tile fill requires a stable tile ID');
    return mutate(`Fill ${tileId}`, (draft) => {
      assertCoordinate(draft, origin);
      const cells = new Map(draft.cells.map((cell) => [key(cell.x, cell.y), cell.tileId]));
      const source = cells.get(key(origin.x, origin.y));
      if (source === tileId) return;
      const visited = new Set<string>();
      const queue: TileCoordinate[] = [origin];
      const region: TileCoordinate[] = [];
      while (queue.length > 0) {
        const coordinate = queue.shift()!;
        const coordinateKey = key(coordinate.x, coordinate.y);
        if (visited.has(coordinateKey)) continue;
        visited.add(coordinateKey);
        if (cells.get(coordinateKey) !== source) continue;
        region.push(coordinate);
        if (coordinate.x > 0) queue.push({ x: coordinate.x - 1, y: coordinate.y });
        if (coordinate.x + 1 < draft.columns) queue.push({ x: coordinate.x + 1, y: coordinate.y });
        if (coordinate.y > 0) queue.push({ x: coordinate.x, y: coordinate.y - 1 });
        if (coordinate.y + 1 < draft.rows) queue.push({ x: coordinate.x, y: coordinate.y + 1 });
      }
      replaceCells(draft, region, tileId);
    });
  },

  selectTileSet(tileSet: ResourceId): TilePaintCommand {
    return mutate(`Select ${tileSet}`, (draft) => { draft.tileSet = tileSet; });
  },
};
