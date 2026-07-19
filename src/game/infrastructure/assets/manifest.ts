/**
 * Typed access to the asset manifest (`asset/assets.json`).
 *
 * The manifest is the single source of truth for media loading: paths,
 * frame geometry, texture keys, and bundle membership. Gameplay semantics
 * (collision, AI, stats, drops) belong to content archetypes and systems.
 */
import manifestJson from '../../../../asset/assets.json';

export const ASSET_MANIFEST = manifestJson;

/** Stable dotted asset IDs, inferred literally from the manifest. */
export type AssetId = keyof typeof ASSET_MANIFEST.assets;

export type AssetEntry = (typeof ASSET_MANIFEST.assets)[AssetId];

export type BundleName = keyof typeof ASSET_MANIFEST.bundles;

export function getAsset(assetId: AssetId): AssetEntry {
  return ASSET_MANIFEST.assets[assetId];
}

export function getBundleAssetIds(bundleName: BundleName): readonly AssetId[] {
  return ASSET_MANIFEST.bundles[bundleName] as readonly AssetId[];
}
