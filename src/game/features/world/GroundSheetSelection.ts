import type { AssetId } from '../../infrastructure/assets/manifest';
import { getAsset } from '../../infrastructure/assets/manifest';
import {
  resolveGroundSheetFrame,
  resolveSheetOrderFrame,
  selectGroundSheetRegion,
} from './GroundSheetRegion';

/**
 * Frame selection strategies for uniform ground sheets:
 * - 'ground-sheet-region': seeded small rectangle + reflected traversal
 *   (legacy; visible repetition/mirroring on smooth sheets).
 * - 'sheet-order': full-sheet row-major order with true mirrored repeats;
 *   matches how the ground sheets are authored and joins repeat edges.
 */
export type GroundFrameStrategy = 'ground-sheet-region' | 'sheet-order';

export interface GroundSheetSelection {
  resolveAt(tileX: number, tileY: number): {
    readonly frame: number;
    readonly flipX: boolean;
    readonly flipY: boolean;
  };
}

function assetSalt(assetId: AssetId): number {
  let hash = 2166136261;
  for (let index = 0; index < assetId.length; index += 1) {
    hash ^= assetId.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

/** Creates deterministic per-area ground frame selection for any uniform sheet. */
export function createGroundSheetSelection(
  assetId: AssetId,
  seed: number,
  strategy: GroundFrameStrategy = 'ground-sheet-region',
): GroundSheetSelection {
  const asset = getAsset(assetId);
  if (asset.source.kind !== 'spritesheet' || !('frame' in asset.source)) {
    throw new Error(`Ground region asset '${assetId}' must be a spritesheet`);
  }
  const frame = asset.source.frame;
  const saltedSeed = seed ^ assetSalt(assetId);

  if (strategy === 'sheet-order') {
    return {
      resolveAt: (tileX, tileY) => resolveSheetOrderFrame(frame.cols, frame.rows, tileX, tileY),
    };
  }

  const region = selectGroundSheetRegion({ columns: frame.cols, rows: frame.rows, seed: saltedSeed });
  return {
    resolveAt: (tileX, tileY) => ({
      frame: resolveGroundSheetFrame(region, frame.cols, tileX, tileY),
      flipX: false,
      flipY: false,
    }),
  };
}
