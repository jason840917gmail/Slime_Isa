import Phaser from 'phaser';
import { getWeaponDefinition } from '../content/weapons/WeaponCatalog';
import { resolveWeaponIcon } from '../content/weapons/WeaponIcon';

export interface WeaponThumbnailOptions {
  readonly x: number;
  readonly y: number;
  readonly size: number;
}

/** Creates a small preview from the weapon's authored UI icon pair. */
export function createWeaponThumbnail(
  scene: Phaser.Scene,
  weaponId: string,
  options: WeaponThumbnailOptions,
): Phaser.GameObjects.Image | undefined {
  try {
    const icon = resolveWeaponIcon(getWeaponDefinition(weaponId));
    if (!icon || !scene.textures.exists(icon.iconKey)) return undefined;
    const texture = scene.textures.get(icon.iconKey);
    const frameName = String(icon.iconFrame);
    const usesBaseFrame = icon.iconFrame === 0 && texture.firstFrame === '__BASE' && !texture.has(frameName);
    if (!usesBaseFrame && !texture.has(frameName)) return undefined;
    const image = usesBaseFrame
      ? scene.add.image(options.x, options.y, icon.iconKey)
      : scene.add.image(options.x, options.y, icon.iconKey, icon.iconFrame);
    return image.setDisplaySize(options.size, options.size);
  } catch {
    return undefined;
  }
}
