import type { WorldTileId } from '../../content/terrain/TileCatalog';
import type { WorldRectangle } from '../../presentation/WorldOcclusion';
import type { WorldDimensions } from '../../world/WorldDimensions';

// World pixels, independent of authored tile size. Gutters hold neighboring
// artwork so linear filtering at fractional zoom cannot sample empty seams.
export const TERRAIN_CHUNK_SIZE = 512;
export const TERRAIN_CHUNK_GUTTER = 2;

export interface TerrainTransitionCommand {
  readonly tileId: WorldTileId;
  readonly tileX: number;
  readonly tileY: number;
  readonly alpha: number;
  readonly polygon: readonly { readonly x: number; readonly y: number }[];
}

export interface TerrainTransitionChunk extends WorldRectangle {
  readonly commands: TerrainTransitionCommand[];
}

/** Input is already in global render order; partitioning must preserve it. */
export function planTerrainTransitionChunks(
  commands: readonly TerrainTransitionCommand[],
  dimensions: WorldDimensions,
): TerrainTransitionChunk[] {
  const chunks = new Map<string, TerrainTransitionChunk>();
  const lastColumn = Math.ceil(dimensions.width / TERRAIN_CHUNK_SIZE) - 1;
  const lastRow = Math.ceil(dimensions.height / TERRAIN_CHUNK_SIZE) - 1;

  for (const command of commands) {
    const xs = command.polygon.map((point) => point.x);
    const ys = command.polygon.map((point) => point.y);
    const minColumn = Math.max(0, Math.floor((Math.min(...xs) - TERRAIN_CHUNK_GUTTER) / TERRAIN_CHUNK_SIZE));
    const maxColumn = Math.min(lastColumn, Math.floor((Math.max(...xs) + TERRAIN_CHUNK_GUTTER) / TERRAIN_CHUNK_SIZE));
    const minRow = Math.max(0, Math.floor((Math.min(...ys) - TERRAIN_CHUNK_GUTTER) / TERRAIN_CHUNK_SIZE));
    const maxRow = Math.min(lastRow, Math.floor((Math.max(...ys) + TERRAIN_CHUNK_GUTTER) / TERRAIN_CHUNK_SIZE));

    for (let row = minRow; row <= maxRow; row += 1) {
      for (let column = minColumn; column <= maxColumn; column += 1) {
        const key = `${column},${row}`;
        let chunk = chunks.get(key);
        if (!chunk) {
          const x = column * TERRAIN_CHUNK_SIZE;
          const y = row * TERRAIN_CHUNK_SIZE;
          chunk = {
            x, y,
            width: Math.min(TERRAIN_CHUNK_SIZE, dimensions.width - x),
            height: Math.min(TERRAIN_CHUNK_SIZE, dimensions.height - y),
            commands: [],
          };
          chunks.set(key, chunk);
        }
        chunk.commands.push(command);
      }
    }
  }
  return [...chunks.values()];
}
