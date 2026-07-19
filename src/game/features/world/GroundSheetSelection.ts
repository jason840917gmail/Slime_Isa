import type { AssetId } from '../../infrastructure/assets/manifest';
import { getAsset } from '../../infrastructure/assets/manifest';
import {
  resolveGroundSheetFrame,
  selectGroundSheetRegion,
  type GroundSheetRegion,
} from './GroundSheetRegion';

export interface GroundSheetSelection {
  readonly region: GroundSheetRegion;
  frameAt(tileX: number, tileY: number): number;
}

function assetSalt(assetId: AssetId): number {
  let hash = 2166136261;
  for (let index = 0; index < assetId.length; index += 1) {
    hash ^= assetId.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

/** Creates deterministic contiguous-frame ground selection for any uniform sheet. */
export function createGroundSheetSelection(assetId: AssetId, seed: number): GroundSheetSelection {
  const asset = getAsset(assetId);
  if (asset.source.kind !== 'spritesheet' || !('frame' in asset.source)) {
    throw new Error(`Ground region asset '${assetId}' must be a spritesheet`);
  }
  const frame = asset.source.frame;
  const region = selectGroundSheetRegion({
    columns: frame.cols,
    rows: frame.rows,
    seed: seed ^ assetSalt(assetId),
  });

  return {
    region,
    frameAt: (tileX, tileY) => resolveGroundSheetFrame(region, frame.cols, tileX, tileY),
  };
}
