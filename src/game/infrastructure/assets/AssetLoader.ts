/**
 * Bundle-driven asset loading.
 *
 * Reads the manifest (`asset/assets.json`) and queues the right Phaser
 * loader call per asset source kind. `derived` and `procedural` sources
 * need no file load — they are created post-load by the derived/procedural
 * pipeline steps.
 */
import type Phaser from 'phaser';

import { getBundleAssetIds, getAsset, type AssetId, type BundleName } from './manifest';
import { resolveAssetUrl, tryResolveAudioUrl } from './assetUrls';

type LoadableSource =
  | { readonly kind: 'image'; readonly path: string }
  | {
    readonly kind: 'spritesheet';
    readonly path: string;
    readonly frame: { readonly w: number; readonly h: number };
  }
  | { readonly kind: 'audio'; readonly path: string }
  | { readonly kind: 'procedural' | 'derived' };


/** Queues Phaser loads for every file-based asset in the bundle. Call in preload(). */
export function loadAssetBundle(scene: Phaser.Scene, bundleName: BundleName): void {
  queueAssets(scene, getBundleAssetIds(bundleName));
}

/**
 * Queues Phaser loads for the given assets, skipping any already loaded.
 * In preload() the loader starts by itself; elsewhere call `scene.load.start()`.
 * Returns how many files were queued.
 */
export function queueAssets(scene: Phaser.Scene, assetIds: readonly AssetId[]): number {
  let queued = 0;
  for (const assetId of assetIds) {
    const asset = getAsset(assetId);
    const source = asset.source as LoadableSource;
    const { runtime } = asset;

    switch (source.kind) {
      case 'image':
        if (scene.textures.exists(runtime.textureKey)) break;
        scene.load.image(runtime.textureKey, resolveAssetUrl(source.path));
        queued += 1;
        break;
      case 'spritesheet':
        if (scene.textures.exists(runtime.textureKey)) break;
        scene.load.spritesheet(runtime.textureKey, resolveAssetUrl(source.path), {
          frameWidth: source.frame.w,
          frameHeight: source.frame.h,
        });
        queued += 1;
        break;
      case 'audio': {
        if (scene.cache.audio.exists(runtime.textureKey)) break;
        const path = source.path;
        const url = tryResolveAudioUrl(path);
        if (url) {
          scene.load.audio(runtime.textureKey, url);
          queued += 1;
        } else {
          console.warn(`No bundled URL for audio asset '${assetId}' at '${path}'; the cue stays silent.`);
        }
        break;
      }
      default:
        // derived / procedural: no file to load.
        break;
    }
  }
  return queued;
}

/**
 * Verifies every file-based texture in the bundle exists. Call in create()
 * after the loader finished and post-load processors ran. Throws naming the
 * asset IDs and texture keys on failure so a bad manifest fails at boot.
 */
export function assertAssetBundleTextures(
  scene: Phaser.Scene,
  bundleName: BundleName,
): void {
  assertAssetsLoaded(scene, getBundleAssetIds(bundleName), `Asset bundle '${bundleName}'`);
}

/** Like `assertAssetBundleTextures`, for any list of assets (`what` names them in the error). */
export function assertAssetsLoaded(scene: Phaser.Scene, assetIds: readonly AssetId[], what: string): void {
  const missing: string[] = [];

  for (const assetId of assetIds) {
    const asset = getAsset(assetId);

    if (asset.source.kind === 'derived') {
      continue;
    }

    if (asset.source.kind === 'audio') {
      // Audio never blocks boot: browsers without Web Audio skip sound loads, and nodes stay silent.
      if (!scene.cache.audio.exists(asset.runtime.textureKey)) console.warn(`Audio asset '${assetId}' did not load; its cues stay silent.`);
      continue;
    }

    if (!scene.textures.exists(asset.runtime.textureKey)) {
      missing.push(`${assetId} (textureKey '${asset.runtime.textureKey}')`);
    }
  }

  if (missing.length > 0) {
    throw new Error(`${what} failed to load: ${missing.join(', ')}`);
  }
}
