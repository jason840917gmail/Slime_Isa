import Phaser from 'phaser';
import { getAsset, type AssetId } from '../infrastructure/assets/manifest';

export interface UiSkinBounds {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

const warnedMissingSkins = new Set<AssetId>();

/** Adds an illustrated UI surface and returns undefined so callers can keep a code-drawn fallback. */
export function addUiSkin(
  scene: Phaser.Scene,
  parent: Phaser.GameObjects.Container,
  assetId: AssetId,
  bounds: UiSkinBounds,
  alpha = 1,
): Phaser.GameObjects.Image | undefined {
  const image = createUiSkinImage(scene, assetId, bounds, alpha);
  if (image) parent.add(image);
  return image;
}

export function createUiSkinImage(
  scene: Phaser.Scene,
  assetId: AssetId,
  bounds: UiSkinBounds,
  alpha = 1,
): Phaser.GameObjects.Image | undefined {
  const textureKey = getAsset(assetId).runtime.textureKey;
  if (!scene.textures.exists(textureKey)) {
    if (!warnedMissingSkins.has(assetId)) {
      warnedMissingSkins.add(assetId);
      console.warn(`UI skin '${assetId}' is unavailable; using the code-drawn fallback.`);
    }
    return undefined;
  }

  const image = scene.add
    .image(bounds.x, bounds.y, textureKey)
    .setOrigin(0.5)
    .setDisplaySize(bounds.width, bounds.height)
    .setAlpha(alpha);
  return image;
}
