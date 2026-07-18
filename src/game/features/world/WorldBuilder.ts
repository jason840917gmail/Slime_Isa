import Phaser from 'phaser';
import { biomeSample, TILE_SIZE, WORLD_HEIGHT, WORLD_TILES_X, WORLD_TILES_Y, WORLD_WIDTH } from '../../terrainNoise';
import {
  getTileBodyBounds,
  resolveWorldTile,
  resolveWorldTileTexture,
  WORLD_TILE_RULES,
  type WorldTileId,
} from '../../worldTiles';
import type { AreaDef } from '../../world/Area';

export interface WorldBuilderContext {
  scene: Phaser.Scene;
  area: AreaDef;
  collisionTiles: Phaser.Physics.Arcade.StaticGroup;
  spawnResource: (x: number, y: number) => void;
}

export class WorldBuilder {
  constructor(private readonly ctx: WorldBuilderContext) {}

  build(): WorldTileId[][] {
    const grid: WorldTileId[][] = [];

    for (let tileY = 0; tileY < WORLD_TILES_Y; tileY += 1) {
      const row: WorldTileId[] = [];
      for (let tileX = 0; tileX < WORLD_TILES_X; tileX += 1) {
        const tileId = resolveWorldTile(tileX, tileY, this.ctx.area.biome, this.ctx.area.seed);
        const worldX = tileX * TILE_SIZE;
        const worldY = tileY * TILE_SIZE;
        row.push(tileId);
        this.createTile(tileId, tileX, tileY, worldX, worldY);

        const resourceNoise = biomeSample(tileX, tileY, this.ctx.area.seed);
        if (
          this.ctx.area.biome === 'meadow'
          && WORLD_TILE_RULES[tileId].allowsDecorations
          && resourceNoise > 0.45
          && biomeSample(tileX + 5, tileY + 3, this.ctx.area.seed) > 0.86
        ) {
          this.ctx.spawnResource(
            worldX + Phaser.Math.Between(20, 44),
            worldY + Phaser.Math.Between(20, 44),
          );
        }
      }
      grid.push(row);
    }

    this.ctx.scene.physics.world.setBounds(0, 0, WORLD_WIDTH, WORLD_HEIGHT);
    return grid;
  }

  private createTile(tileId: WorldTileId, tileX: number, tileY: number, worldX: number, worldY: number): void {
    const textureKey = resolveWorldTileTexture(tileId, tileX, tileY, this.ctx.area.seed);
    const bodyBounds = getTileBodyBounds(tileId, TILE_SIZE);
    if (!bodyBounds) {
      this.ctx.scene.add.image(worldX, worldY, textureKey).setOrigin(0);
      return;
    }

    const tile = this.ctx.collisionTiles.create(
      worldX + TILE_SIZE / 2,
      worldY + TILE_SIZE / 2,
      textureKey,
    ) as Phaser.Physics.Arcade.Image;
    const body = tile.body as Phaser.Physics.Arcade.StaticBody;
    tile.setDepth(1);
    body.setSize(bodyBounds.width, bodyBounds.height);
    body.setOffset(bodyBounds.offsetX, bodyBounds.offsetY);
    tile.refreshBody();
  }
}
