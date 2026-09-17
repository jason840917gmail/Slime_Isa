import type { TileDataResourceDocument } from './types';

export interface TileMapCell {
  readonly x: number;
  readonly y: number;
  readonly tileId: string;
}

export interface ResolvedTileMapDataResource {
  readonly resourceId: TileDataResourceDocument['resourceId'];
  readonly tileSet: TileDataResourceDocument['tileSet'];
  readonly cells: readonly TileMapCell[];
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function parseTileMapDataResource(document: TileDataResourceDocument): ResolvedTileMapDataResource {
  const occupied = new Set<string>();
  const cells = document.cells.map((value, index): TileMapCell => {
    if (!isRecord(value)) throw new Error(`Tile data '${document.resourceId}' cell ${index} must be an object`);
    if (!Number.isSafeInteger(value.x) || (value.x as number) < 0
      || !Number.isSafeInteger(value.y) || (value.y as number) < 0) {
      throw new Error(`Tile data '${document.resourceId}' cell ${index} requires non-negative integer coordinates`);
    }
    if (typeof value.tileId !== 'string' || value.tileId.length === 0) {
      throw new Error(`Tile data '${document.resourceId}' cell ${index} requires a stable tileId`);
    }
    const key = `${value.x},${value.y}`;
    if (occupied.has(key)) throw new Error(`Tile data '${document.resourceId}' duplicates cell '${key}'`);
    occupied.add(key);
    return { x: value.x as number, y: value.y as number, tileId: value.tileId };
  });
  return { resourceId: document.resourceId, tileSet: document.tileSet, cells };
}
