import Phaser from 'phaser';

import {
  getTileDefinition,
  type TileDefinition,
  type WorldTileId,
} from '../../content/terrain/TileCatalog';
import type { WorldDimensions } from '../../world/WorldDimensions';
import { TileFactory } from './TileFactory';

type Edge = 'north' | 'east' | 'south' | 'west';

interface TerrainTransitionRendererContext {
  readonly scene: Phaser.Scene;
  readonly tileFactory: TileFactory;
  readonly dimensions: WorldDimensions;
  readonly seed: number;
}

interface BoundaryChoice {
  readonly winnerId: WorldTileId;
  readonly targetX: number;
  readonly targetY: number;
  readonly targetEdge: Edge;
  readonly edgeWidth: number;
}

const EDGE_SALT: Readonly<Record<Edge, number>> = {
  north: 0x12a43,
  east: 0x295c7,
  south: 0x3dd13,
  west: 0x4f891,
};

const FEATHER_BANDS = [
  { width: 1.4, alpha: 0.16, jitter: 3.5 },
  { width: 0.9, alpha: 0.28, jitter: 2.5 },
  { width: 0.45, alpha: 0.72, jitter: 1.5 },
] as const;

/** Owns generated overlays and their geometry masks. */
export class TerrainTransitionLayer {
  constructor(
    private readonly images: Phaser.GameObjects.Image[],
    private readonly masks: Phaser.Display.Masks.GeometryMask[],
    private readonly maskGraphics: Phaser.GameObjects.Graphics[],
  ) {}

  destroy(): void {
    for (const image of this.images) {
      image.clearMask(false);
      image.destroy();
    }
    for (const mask of this.masks) mask.destroy();
    for (const graphics of this.maskGraphics) graphics.destroy();
    this.images.length = 0;
    this.masks.length = 0;
    this.maskGraphics.length = 0;
  }
}

/**
 * Visual-only second pass for authored terrain. Each differing cardinal
 * boundary is rendered once: the higher-priority material feathers into the
 * lower-priority cell using three deterministic jagged alpha bands.
 */
export class TerrainTransitionRenderer {
  constructor(private readonly ctx: TerrainTransitionRendererContext) {}

  render(terrainGrid: readonly (readonly WorldTileId[])[]): TerrainTransitionLayer {
    const images: Phaser.GameObjects.Image[] = [];
    const masks: Phaser.Display.Masks.GeometryMask[] = [];
    const maskGraphics: Phaser.GameObjects.Graphics[] = [];

    for (let tileY = 0; tileY < terrainGrid.length; tileY += 1) {
      const row = terrainGrid[tileY];
      for (let tileX = 0; tileX < row.length; tileX += 1) {
        const tileId = row[tileX];
        const eastId = row[tileX + 1];
        if (eastId) {
          const choice = this.chooseBoundary(tileId, eastId, tileX, tileY, 'east');
          if (choice) this.renderBoundary(choice, images, masks, maskGraphics);
        }

        const southId = terrainGrid[tileY + 1]?.[tileX];
        if (southId) {
          const choice = this.chooseBoundary(tileId, southId, tileX, tileY, 'south');
          if (choice) this.renderBoundary(choice, images, masks, maskGraphics);
        }
      }
    }

    return new TerrainTransitionLayer(images, masks, maskGraphics);
  }

  private chooseBoundary(
    currentId: WorldTileId,
    neighborId: WorldTileId,
    currentX: number,
    currentY: number,
    direction: 'east' | 'south',
  ): BoundaryChoice | undefined {
    if (currentId === neighborId) return undefined;
    const current = getTileDefinition(currentId).transition;
    const neighbor = getTileDefinition(neighborId).transition;
    if (!current || !neighbor || current.group !== neighbor.group || current.material === neighbor.material) {
      return undefined;
    }

    const currentWins = this.compareTransition(currentId, current, neighborId, neighbor) >= 0;
    const edgeWidth = Math.min(current.edgeWidth, neighbor.edgeWidth);

    if (direction === 'east') {
      return currentWins
        ? { winnerId: currentId, targetX: currentX + 1, targetY: currentY, targetEdge: 'west', edgeWidth }
        : { winnerId: neighborId, targetX: currentX, targetY: currentY, targetEdge: 'east', edgeWidth };
    }

    return currentWins
      ? { winnerId: currentId, targetX: currentX, targetY: currentY + 1, targetEdge: 'north', edgeWidth }
      : { winnerId: neighborId, targetX: currentX, targetY: currentY, targetEdge: 'south', edgeWidth };
  }

  private compareTransition(
    leftId: WorldTileId,
    left: NonNullable<TileDefinition['transition']>,
    rightId: WorldTileId,
    right: NonNullable<TileDefinition['transition']>,
  ): number {
    if (left.priority !== right.priority) return left.priority - right.priority;
    return leftId.localeCompare(rightId);
  }

  private renderBoundary(
    choice: BoundaryChoice,
    images: Phaser.GameObjects.Image[],
    masks: Phaser.Display.Masks.GeometryMask[],
    maskGraphics: Phaser.GameObjects.Graphics[],
  ): void {
    FEATHER_BANDS.forEach((band, bandIndex) => {
      const image = this.ctx.tileFactory.createOverlay(
        choice.winnerId,
        choice.targetX,
        choice.targetY,
        0.2 + bandIndex * 0.01,
      ).setAlpha(band.alpha);
      const graphics = this.ctx.scene.make.graphics({}, false);
      graphics.fillStyle(0xffffff, 1);
      graphics.fillPoints(this.edgePolygon(
        choice.targetX,
        choice.targetY,
        choice.targetEdge,
        choice.edgeWidth * band.width,
        band.jitter,
        bandIndex,
      ), true);
      const mask = graphics.createGeometryMask();
      image.setMask(mask);

      images.push(image);
      masks.push(mask);
      maskGraphics.push(graphics);
    });
  }

  private edgePolygon(
    tileX: number,
    tileY: number,
    edge: Edge,
    width: number,
    jitter: number,
    bandIndex: number,
  ): Phaser.Math.Vector2[] {
    const tileSize = this.ctx.dimensions.tileSize;
    const worldX = tileX * tileSize;
    const worldY = tileY * tileSize;
    const sampleCount = Math.max(4, Math.ceil(tileSize / 8));
    const boundary: Phaser.Math.Vector2[] = [];

    for (let sample = 0; sample <= sampleCount; sample += 1) {
      const along = (sample / sampleCount) * tileSize;
      const noise = this.noise(tileX, tileY, edge, bandIndex, sample) * jitter;
      const inset = Phaser.Math.Clamp(width + noise, 1, tileSize - 1);

      if (edge === 'north') boundary.push(new Phaser.Math.Vector2(worldX + along, worldY + inset));
      else if (edge === 'south') boundary.push(new Phaser.Math.Vector2(worldX + along, worldY + tileSize - inset));
      else if (edge === 'west') boundary.push(new Phaser.Math.Vector2(worldX + inset, worldY + along));
      else boundary.push(new Phaser.Math.Vector2(worldX + tileSize - inset, worldY + along));
    }

    if (edge === 'north') {
      return [
        new Phaser.Math.Vector2(worldX, worldY),
        new Phaser.Math.Vector2(worldX + tileSize, worldY),
        ...boundary.reverse(),
      ];
    }
    if (edge === 'south') {
      return [
        new Phaser.Math.Vector2(worldX, worldY + tileSize),
        new Phaser.Math.Vector2(worldX + tileSize, worldY + tileSize),
        ...boundary.reverse(),
      ];
    }
    if (edge === 'west') {
      return [
        new Phaser.Math.Vector2(worldX, worldY),
        new Phaser.Math.Vector2(worldX, worldY + tileSize),
        ...boundary.reverse(),
      ];
    }
    return [
      new Phaser.Math.Vector2(worldX + tileSize, worldY),
      new Phaser.Math.Vector2(worldX + tileSize, worldY + tileSize),
      ...boundary.reverse(),
    ];
  }

  private noise(tileX: number, tileY: number, edge: Edge, bandIndex: number, sample: number): number {
    let hash = Math.imul(tileX + this.ctx.seed * 17, 0x45d9f3b);
    hash ^= Math.imul(tileY - this.ctx.seed * 31, 0x119de1f3);
    hash ^= EDGE_SALT[edge];
    hash ^= Math.imul(bandIndex + 1, 0x27d4eb2d);
    hash ^= Math.imul(sample + 1, 0x165667b1);
    hash = Math.imul(hash ^ (hash >>> 16), 0x45d9f3b);
    const normalized = ((hash ^ (hash >>> 16)) >>> 0) / 4294967295;
    return normalized * 2 - 1;
  }
}
