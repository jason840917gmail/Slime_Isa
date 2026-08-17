import Phaser from 'phaser';
import { getWeaponDefinition } from '../content/weapons/WeaponCatalog';
import { getAsset, type AssetId } from '../infrastructure/assets/manifest';

export interface WeaponThumbnailOptions {
  readonly x: number;
  readonly y: number;
  readonly size: number;
}

/** Creates a small preview from the first authored right-facing weapon tile. */
export function createWeaponThumbnail(
  scene: Phaser.Scene,
  weaponId: string,
  options: WeaponThumbnailOptions,
): Phaser.GameObjects.Image | undefined {
  try {
    const definition = getWeaponDefinition(weaponId);
    const layer = definition.directionalAttacks.right.animation.layers.find((candidate) => candidate.blocks.length > 0);
    const block = layer?.blocks[0];
    if (!layer || !block) return undefined;

    const asset = getAsset(layer.assetId as AssetId);
    if (asset.source.kind !== 'spritesheet' || !scene.textures.exists(asset.runtime.textureKey)) return undefined;

    return scene.add.image(options.x, options.y, asset.runtime.textureKey, block.sourceFrame)
      .setDisplaySize(options.size, options.size)
      .setRotation(Phaser.Math.DegToRad(block.transform.rotationDeg));
  } catch {
    return undefined;
  }
}
