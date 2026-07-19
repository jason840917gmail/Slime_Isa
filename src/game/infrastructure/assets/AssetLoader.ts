/**
 * Bundle-driven asset loading.
 *
 * Reads the manifest (`asset/assets.json`) and queues the right Phaser
 * loader call per asset source kind. `derived` and `procedural` sources
 * need no file load — they are created post-load by the derived/procedural
 * pipeline steps.
 */
import type Phaser from 'phaser';

import { getBundleAssetIds, getAsset, type BundleName } from './manifest';
import { resolveAssetUrl } from './assetUrls';

type LoadableSource =
  | { readonly kind: 'image'; readonly path: string }
  | {
    readonly kind: 'spritesheet';
    readonly path: string;
    readonly frame: { readonly w: number; readonly h: number };
  }
  | { readonly kind: 'procedural' | 'derived' };

/** Queues Phaser loads for every file-based asset in the bundle. Call in preload(). */
export function loadAssetBundle(scene: Phaser.Scene, bundleName: BundleName): void {
  for (const assetId of getBundleAssetIds(bundleName)) {
    const asset = getAsset(assetId);
    const source = asset.source as LoadableSource;
    const { runtime } = asset;

    switch (source.kind) {
      case 'image':
        scene.load.image(runtime.textureKey, resolveAssetUrl(source.path));
        break;
      case 'spritesheet':
        scene.load.spritesheet(runtime.textureKey, resolveAssetUrl(source.path), {
          frameWidth: source.frame.w,
          frameHeight: source.frame.h,
        });
        break;
      default:
        // derived / procedural: no file to load.
        break;
    }
  }
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
  const missing: string[] = [];

  for (const assetId of getBundleAssetIds(bundleName)) {
    const asset = getAsset(assetId);

    if (asset.source.kind === 'derived') {
      continue;
    }

    if (!scene.textures.exists(asset.runtime.textureKey)) {
      missing.push(`${assetId} (textureKey '${asset.runtime.textureKey}')`);
    }
  }

  if (missing.length > 0) {
    throw new Error(`Asset bundle '${bundleName}' failed to load: ${missing.join(', ')}`);
  }
}
