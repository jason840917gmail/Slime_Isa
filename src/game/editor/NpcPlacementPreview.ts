import Phaser from 'phaser';

import { getCharacterPackage } from '../content/characters/CharacterCatalog';
import type { NpcCharacterPlacementChoice } from '../content/objects/ObjectCatalog';
import { getAsset, type AssetId } from '../infrastructure/assets/manifest';
import { setObjectAnchor } from '../features/objects/ObjectFactory';

export interface NpcPlacementPreviewOptions {
  readonly x: number;
  readonly y: number;
  readonly sortId?: string;
  readonly depth?: number;
}

/** Render-only adapter for NPC placement choices used by the Map Editor. */
export class NpcPlacementPreview {
  private readonly previews = new Set<Phaser.GameObjects.Image>();

  constructor(private readonly scene: Phaser.Scene) {}

  create(
    choice: NpcCharacterPlacementChoice,
    options: NpcPlacementPreviewOptions,
  ): Phaser.GameObjects.Image {
    const character = getCharacterPackage(choice.characterId);
    const asset = getAsset(character.visualSet.assetId as AssetId);
    if (asset.source.kind !== 'spritesheet' || !('frame' in asset.source)) {
      throw new Error(`NPC '${choice.characterId}' requires a spritesheet placement visual`);
    }
    const clip = character.visualSet.clips.idle;
    const frame = clip?.frames[0] ?? 0;
    const frameVisual = character.visualSet.frameVisuals?.[String(frame)];
    const origin = frameVisual?.origin ?? character.visualSet.defaults.origin;
    const scale = frameVisual?.scale ?? character.visualSet.defaults.scale;
    const sourceOffset = frameVisual?.sourceOffset
      ?? clip?.sourceOffset
      ?? character.visualSet.defaults.sourceOffset;
    const image = this.scene.add.image(options.x, options.y, asset.runtime.textureKey, frame)
      .setOrigin(origin[0], origin[1])
      .setScale(scale[0], scale[1]);
    image.setData('objectId', choice.objectId);
    image.setData('sortId', options.sortId ?? choice.key);
    image.setData('depthMode', options.depth === undefined ? 'world-sorted' : 'explicit');
    image.setData('visualOffset', { x: sourceOffset[0], y: sourceOffset[1] });
    image.setData('sourceFrame', { width: asset.source.frame.w, height: asset.source.frame.h });
    setObjectAnchor(image, options.x, options.y);
    if (options.depth !== undefined) image.setDepth(options.depth);
    this.previews.add(image);
    image.once(Phaser.GameObjects.Events.DESTROY, () => this.previews.delete(image));
    return image;
  }

  destroy(): void {
    for (const preview of this.previews) preview.destroy();
    this.previews.clear();
  }
}
