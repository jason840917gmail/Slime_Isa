import Phaser from 'phaser';

import {
  getTileBodyBounds,
  getTileDefinition,
  type WorldTileId,
} from '../../content/terrain/TileCatalog';
import { getAsset } from '../../infrastructure/assets/manifest';
import type { AssetId } from '../../infrastructure/assets/manifest';
import type { WorldDimensions } from '../../world/WorldDimensions';
import { createGroundSheetSelection, type GroundSheetSelection } from './GroundSheetSelection';

interface TileFactoryContext {
  readonly scene: Phaser.Scene;
  readonly collisionTiles: Phaser.Physics.Arcade.StaticGroup;
  readonly dimensions: WorldDimensions;
  readonly seed: number;
  readonly physicsEnabled?: boolean;
}

function tileHash(tileX: number, tileY: number, seed: number): number {
  return (
    Math.imul(tileX + seed * 17, 374761393)
    ^ Math.imul(tileY - seed * 31, 668265263)
  ) >>> 0;
}

export class TileFactory {
  private readonly groundSelections = new Map<AssetId, GroundSheetSelection>();

  constructor(private readonly ctx: TileFactoryContext) {}

  create(tileId: WorldTileId, tileX: number, tileY: number): Phaser.GameObjects.Image {
    const definition = getTileDefinition(tileId);
    const worldX = tileX * this.ctx.dimensions.tileSize;
    const worldY = tileY * this.ctx.dimensions.tileSize;
    const assetIndex = tileHash(tileX, tileY, this.ctx.seed) % definition.visual.assetIds.length;
    const asset = getAsset(definition.visual.assetIds[assetIndex]);
    const frame = definition.visual.selection === 'ground-sheet-region'
      ? this.groundSelection(definition.visual.assetIds[assetIndex]).frameAt(tileX, tileY)
      : undefined;
    const bodyBounds = getTileBodyBounds(tileId, this.ctx.dimensions.tileSize);

    if (!bodyBounds || this.ctx.physicsEnabled === false) {
      return this.ctx.scene.add.image(worldX, worldY, asset.runtime.textureKey, frame).setOrigin(0);
    }

    const image = this.ctx.collisionTiles.create(
      worldX + this.ctx.dimensions.tileSize / 2,
      worldY + this.ctx.dimensions.tileSize / 2,
      asset.runtime.textureKey,
      frame,
    ) as Phaser.Physics.Arcade.Image;
    const body = image.body as Phaser.Physics.Arcade.StaticBody;
    image.setDepth(1);
    body.setSize(bodyBounds.width, bodyBounds.height);
    body.setOffset(bodyBounds.offsetX, bodyBounds.offsetY);
    image.refreshBody();
    return image;
  }

  private groundSelection(assetId: AssetId): GroundSheetSelection {
    const existing = this.groundSelections.get(assetId);
    if (existing) return existing;
    const selection = createGroundSheetSelection(assetId, this.ctx.seed);
    this.groundSelections.set(assetId, selection);
    return selection;
  }
}
