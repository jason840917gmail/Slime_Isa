/**
 * Which images load at boot and which wait for their world (roadmap 10.1).
 *
 * `worldAssetSets.generated.json` (scripts/assets/build-world-asset-sets.mjs)
 * lists the images each world needs on its own. Boot loads every other image
 * in the `boot` and `interiors` bundles; MapLoadScene loads the entered
 * world's list. An image the generated file does not know about is therefore
 * always loaded at boot.
 */
import worldAssetSets from '../../content/worldAssetSets.generated.json';
import { ASSET_MANIFEST, getBundleAssetIds, type AssetId } from './manifest';

const WORLD_SETS = worldAssetSets.worlds as Readonly<Record<string, readonly string[]>>;
const DEFERRED = new Set(Object.values(WORLD_SETS).flat());

function isAssetId(value: string): value is AssetId {
  return value in ASSET_MANIFEST.assets;
}

/** Every `boot` and `interiors` image that no world claims for itself. */
export function bootImageAssetIds(): readonly AssetId[] {
  return [...getBundleAssetIds('boot'), ...getBundleAssetIds('interiors')].filter((assetId) => !DEFERRED.has(assetId));
}

/** The images the world `mapId` needs on its own (none for an unknown world). */
export function worldImageAssetIds(mapId: string): readonly AssetId[] {
  return (WORLD_SETS[mapId] ?? []).filter(isAssetId);
}
