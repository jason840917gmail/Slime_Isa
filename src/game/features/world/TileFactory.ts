import Phaser from 'phaser';

import {
  getTileBodyBounds,
  getTileDefinition,
  type WorldTileId,
} from '../../content/terrain/TileCatalog';
import { getAsset } from '../../infrastructure/assets/manifest';
import type { AssetId } from '../../infrastructure/assets/manifest';
import { DEPTH_BANDS } from '../../presentation/WorldDepth';
import type { WorldDimensions } from '../../world/WorldDimensions';
import {
  createGroundSheetSelection,
  type GroundFrameStrategy,
  type GroundSheetSelection,
} from './GroundSheetSelection';

interface TileFactoryContext {
  readonly scene: Phaser.Scene;
  readonly collisionTiles: Phaser.Physics.Arcade.StaticGroup;
  readonly dimensions: WorldDimensions;
  readonly seed: number;
  readonly physicsEnabled?: boolean;
}

interface ResolvedTileVisual {
  readonly textureKey: string;
  readonly frame?: number;
  readonly flipX: boolean;
  readonly flipY: boolean;
}

function tileHash(tileX: number, tileY: number, seed: number): number {
  return (
    Math.imul(tileX + seed * 17, 374761393)
    ^ Math.imul(tileY - seed * 31, 668265263)
  ) >>> 0;
}

export class TileFactory {
  private readonly groundSelections = new Map<string, GroundSheetSelection>();

  constructor(private readonly ctx: TileFactoryContext) {}

  create(tileId: WorldTileId, tileX: number, tileY: number): Phaser.GameObjects.Image {
    const worldX = tileX * this.ctx.dimensions.tileSize;
    const worldY = tileY * this.ctx.dimensions.tileSize;
    const visual = this.resolveVisual(tileId, tileX, tileY);
    const bodyBounds = getTileBodyBounds(tileId, this.ctx.dimensions.tileSize);

    if (!bodyBounds || this.ctx.physicsEnabled === false) {
      return this.ctx.scene.add.image(worldX, worldY, visual.textureKey, visual.frame)
        .setOrigin(0)
        .setFlip(visual.flipX, visual.flipY);
    }

    const image = this.ctx.collisionTiles.create(
      worldX + this.ctx.dimensions.tileSize / 2,
      worldY + this.ctx.dimensions.tileSize / 2,
      visual.textureKey,
      visual.frame,
    ) as Phaser.Physics.Arcade.Image;
    const body = image.body as Phaser.Physics.Arcade.StaticBody;
    image.setDepth(DEPTH_BANDS['ground-terrain']);
    image.setFlip(visual.flipX, visual.flipY);
    body.setSize(bodyBounds.width, bodyBounds.height);
    body.setOffset(bodyBounds.offsetX, bodyBounds.offsetY);
    image.refreshBody();
    return image;
  }

  /** Creates a visual-only copy aligned to this world cell (used by edge transitions). */
  createOverlay(tileId: WorldTileId, tileX: number, tileY: number, depth: number): Phaser.GameObjects.Image {
    const visual = this.resolveVisual(tileId, tileX, tileY);
    return this.ctx.scene.add.image(
      tileX * this.ctx.dimensions.tileSize,
      tileY * this.ctx.dimensions.tileSize,
      visual.textureKey,
      visual.frame,
    ).setOrigin(0).setFlip(visual.flipX, visual.flipY).setDepth(depth + DEPTH_BANDS['ground-decals']);
  }

  private resolveVisual(tileId: WorldTileId, tileX: number, tileY: number): ResolvedTileVisual {
    const definition = getTileDefinition(tileId);
    const assetIndex = tileHash(tileX, tileY, this.ctx.seed) % definition.visual.assetIds.length;
    const assetId = definition.visual.assetIds[assetIndex];
    const asset = getAsset(assetId);
    const selection = definition.visual.selection;
    const groundFrame = selection === 'seeded-hash'
      ? undefined
      : this.groundSelection(assetId, selection).resolveAt(tileX, tileY);

    return {
      textureKey: asset.runtime.textureKey,
      frame: groundFrame?.frame,
      flipX: groundFrame?.flipX ?? false,
      flipY: groundFrame?.flipY ?? false,
    };
  }

  private groundSelection(assetId: AssetId, strategy: GroundFrameStrategy): GroundSheetSelection {
    const key = `${assetId}:${strategy}`;
    const existing = this.groundSelections.get(key);
    if (existing) return existing;
    const selection = createGroundSheetSelection(assetId, this.ctx.seed, strategy);
    this.groundSelections.set(key, selection);
    return selection;
  }
}
