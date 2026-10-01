import type Phaser from 'phaser';

import { parseTileMapDataResource } from '../../content/scenes/resources/TileMapDataResource';
import { parseTileSetResource, type TileSetTile } from '../../content/scenes/resources/TileSetResource';
import type { ResourceId, RuntimeNodeId } from '../../content/scenes/identifiers';
import { ASSET_MANIFEST, getAsset, type AssetId } from '../assets/manifest';
import { DEPTH_BANDS } from '../../presentation/WorldDepth';
import { Node2D, type Node2DOptions } from '../../runtime/scene/Node2D';
import { createGroundSheetSelection, type GroundSheetSelection } from '../../features/world/GroundSheetSelection';
import type { PhaserBlockingParticipant } from '../scenes/PhaserNodeContext';
import type { PhaserNodeContext } from '../scenes/PhaserNodeContext';
import type { BlockingContact } from '../../runtime/scene/physics/PhysicsContact';
import { collisionBits, collisionLayerValue } from '../../content/physics/CollisionLayers';
import type { PresentationParticipant } from './PresentationSync';
import { renderTerrainBlend, terrainBlendLookup, type TerrainTransitionLayer } from '../../features/world/TerrainTransitionRenderer';
import { WaterSurfaceLayer, type WaterKind } from '../../features/world/WaterSurfaceLayer';

const WATER_ASSETS: Readonly<Record<string, WaterKind>> = { 'sheet.grounds.19x19.water': 'shallow', 'sheet.grounds.19x19.deep-water': 'deep' };

export interface TileMapLayer2DNodeOptions extends Node2DOptions {
  readonly context: PhaserNodeContext;
  readonly tileData: ResourceId;
  readonly tileSize?: number;
  readonly seed?: number;
  readonly depth?: number;
  readonly collisionLayer?: number;
  readonly collisionMask?: number;
  readonly collisionEnabled?: boolean;
  readonly editorLocked?: boolean;
}

interface TileBodyRect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

interface MountedTile {
  readonly x: number;
  readonly y: number;
  readonly image: Phaser.GameObjects.Image;
}

/**
 * One static body covering a rectangle of same-tile solid cells. Neighbouring
 * solid cells merge (rows first, then equal-span rows stack), and the tile's
 * authored inset applies only to the rectangle's outer edges, so a lake is a
 * handful of bodies instead of one per cell, with no seams inside it.
 */
interface MountedBody {
  readonly zone: Phaser.GameObjects.Zone;
  /** Body rectangle relative to the layer origin, in world pixels. */
  readonly rect: TileBodyRect;
}

export interface CellRectangle {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

/**
 * Deterministic greedy rectangle cover of a cell set: horizontal runs per row,
 * then runs with the same span on consecutive rows stack into one rectangle.
 */
export function mergeCellRectangles(cells: Iterable<{ readonly x: number; readonly y: number }>): CellRectangle[] {
  const byRow = new Map<number, number[]>();
  for (const { x, y } of cells) {
    const row = byRow.get(y) ?? [];
    row.push(x);
    byRow.set(y, row);
  }
  let open = new Map<string, { x: number; y: number; width: number; height: number }>();
  const done: CellRectangle[] = [];
  for (const y of [...byRow.keys()].sort((a, b) => a - b)) {
    const runs: { x: number; width: number }[] = [];
    for (const x of byRow.get(y)!.sort((a, b) => a - b)) {
      const last = runs.at(-1);
      if (last && last.x + last.width === x) last.width += 1;
      else if (!last || last.x + last.width - 1 !== x) runs.push({ x, width: 1 });
    }
    const next = new Map<string, { x: number; y: number; width: number; height: number }>();
    for (const run of runs) {
      const key = `${run.x}:${run.width}`;
      const rect = open.get(key);
      if (rect && rect.y + rect.height === y) {
        rect.height += 1;
        open.delete(key);
        next.set(key, rect);
      } else {
        next.set(key, { x: run.x, y, width: run.width, height: 1 });
      }
    }
    done.push(...open.values());
    open = next;
  }
  done.push(...open.values());
  return done.sort((a, b) => a.y - b.y || a.x - b.x);
}

type TileStaticBody = Phaser.Physics.Arcade.StaticBody & {
  readonly world: { readonly staticTree: { remove(body: unknown): void; insert(body: unknown): void } };
};

function tileHash(tileX: number, tileY: number, seed: number): number {
  return (
    Math.imul(tileX + seed * 17, 374761393)
    ^ Math.imul(tileY - seed * 31, 668265263)
  ) >>> 0;
}

export class TileMapLayer2DNode extends Node2D implements PresentationParticipant {
  readonly tileData: ResourceId;
  readonly tileSize: number;
  readonly seed: number;
  readonly depth: number;
  readonly collisionLayer: number;
  readonly collisionMask: number;
  readonly editorLocked: boolean;
  private collisionEnabledValue: boolean;
  private readonly mountedTiles: MountedTile[] = [];
  private readonly mountedBodies: MountedBody[] = [];
  private readonly groundSelections = new Map<string, GroundSheetSelection>();
  /** Blended material borders derived from the tiles (visual only). */
  private terrainBlend?: TerrainTransitionLayer;
  /** Animated water surface over water tiles (visual only). */
  private waterSurface?: WaterSurfaceLayer;
  private syncedTransformRevision?: number;
  private syncedVisible?: boolean;

  constructor(private readonly tileOptions: TileMapLayer2DNodeOptions) {
    super(tileOptions);
    this.tileData = tileOptions.tileData;
    this.tileSize = tileOptions.tileSize ?? 64;
    this.seed = tileOptions.seed ?? 0;
    this.depth = tileOptions.depth ?? DEPTH_BANDS['ground-terrain'];
    this.collisionLayer = tileOptions.collisionLayer ?? collisionBits('world');
    // Tile bodies are static; a static body's mask never participates in blocking.
    this.collisionMask = tileOptions.collisionMask ?? 0;
    this.collisionEnabledValue = tileOptions.collisionEnabled ?? true;
    this.editorLocked = tileOptions.editorLocked ?? false;
    if (!Number.isFinite(this.tileSize) || this.tileSize <= 0) throw new Error('TileMapLayer2D tileSize must be positive');
    if (!Number.isSafeInteger(this.seed)) throw new Error('TileMapLayer2D seed must be an integer');
    if (![this.depth, this.collisionLayer, this.collisionMask].every(Number.isFinite)) throw new Error('TileMapLayer2D numeric properties must be finite');
  }

  get tileCount(): number { return this.mountedTiles.length; }
  get blendChunkCount(): number { return this.terrainBlend?.chunkCount ?? 0; }
  get collisionBodyCount(): number { return this.mountedBodies.length; }
  get collisionEnabled(): boolean { return this.collisionEnabledValue; }

  /** World-space Arcade rectangles of the merged tile bodies, for inspection and tests. */
  collisionBodyBounds(): readonly TileBodyRect[] {
    return this.mountedBodies.flatMap(({ zone }) => {
      const body = zone.body as Phaser.Physics.Arcade.StaticBody | null;
      return body ? [{ x: body.position.x, y: body.position.y, width: body.width, height: body.height }] : [];
    });
  }

  setCollisionEnabled(enabled: boolean): void {
    this.collisionEnabledValue = enabled;
    for (const { zone } of this.mountedBodies) {
      if (zone.body) (zone.body as Phaser.Physics.Arcade.StaticBody).enable = enabled;
    }
  }

  override _enter_tree(): void {
    const dataDocument = this.tileOptions.context.resource(this.tileData);
    if (dataDocument.kind !== 'tile-data') throw new Error(`TileMapLayer2D requires tile-data resource '${this.tileData}'`);
    const data = parseTileMapDataResource(dataDocument);
    const setDocument = this.tileOptions.context.resource(data.tileSet);
    if (setDocument.kind !== 'tile-set') throw new Error(`Tile data '${data.resourceId}' requires tile-set resource '${data.tileSet}'`);
    const tileSet = parseTileSetResource(setDocument);
    const transform = this.get_global_transform();
    const hasCollision = data.cells.some((cell) => tileSet.tiles[cell.tileId]?.physics !== null);
    if (hasCollision && (transform.rotation !== 0 || transform.scale.x !== 1 || transform.scale.y !== 1)) {
      throw new Error('Collidable TileMapLayer2D nodes require zero rotation and unit scale');
    }

    for (const cell of data.cells) {
      const tile = tileSet.tiles[cell.tileId];
      if (!tile) throw new Error(`Tile data '${data.resourceId}' references unknown tile '${cell.tileId}'`);
      this.mountCell(cell.x, cell.y, tile);
    }
    this.mountCollision(data.cells, tileSet.tiles);
    this.mountTerrainPresentation(data.columns, data.rows, data.cells, tileSet.tiles, transform);
    const unregister = this.tileOptions.context.registerPresentation(this);
    this.entryDisposables.add(() => unregister());
    this.entryDisposables.add(() => {
      this.terrainBlend?.destroy();
      this.terrainBlend = undefined;
      this.waterSurface?.destroy();
      this.waterSurface = undefined;
      for (const tile of this.mountedTiles) tile.image.destroy();
      this.mountedTiles.length = 0;
      for (const { zone } of this.mountedBodies) zone.destroy();
      this.mountedBodies.length = 0;
      this.groundSelections.clear();
      this.syncedTransformRevision = undefined;
      this.syncedVisible = undefined;
    });
    this.syncPresentation(1);
  }

  /**
   * Tiles only move when the layer's global transform (or visibility)
   * changes, so tile images and static tile bodies are left untouched on
   * every other frame: re-inserting static bodies into Arcade's static tree
   * is the expensive part.
   */
  syncPresentation(_alpha: number): void {
    const revision = this.get_global_transform_revision();
    if (revision === this.syncedTransformRevision && this.visible === this.syncedVisible) return;
    this.syncedTransformRevision = revision;
    this.syncedVisible = this.visible;
    const transform = this.get_global_transform();
    const cosine = Math.cos(transform.rotation);
    const sine = Math.sin(transform.rotation);
    for (const tile of this.mountedTiles) {
      const localX = tile.x * this.tileSize * transform.scale.x;
      const localY = tile.y * this.tileSize * transform.scale.y;
      tile.image
        .setPosition(
          transform.position.x + localX * cosine - localY * sine,
          transform.position.y + localX * sine + localY * cosine,
        )
        .setRotation(transform.rotation)
        .setScale(transform.scale.x, transform.scale.y)
        .setVisible(this.visible)
        .setDepth(this.depth);
    }
    for (const body of this.mountedBodies) this.placeTileBody(body, transform.position);
    this.terrainBlend?.setOrigin(transform.position.x, transform.position.y);
    this.terrainBlend?.setVisible(this.visible);
    this.waterSurface?.setOrigin(transform.position.x, transform.position.y);
    this.waterSurface?.setVisible(this.visible);
  }

  /**
   * Visual-only terrain derived from the tiles, shared by the game and Scene
   * Studio: material borders blend into organic regions. Walls, trees and
   * crystals are placed objects, not tiles. Only for unrotated, unscaled
   * layers, like collision.
   */
  private mountTerrainPresentation(
    columns: number,
    rows: number,
    cells: readonly { readonly x: number; readonly y: number; readonly tileId: string }[],
    tiles: Readonly<Record<string, TileSetTile>>,
    transform: Readonly<{ rotation: number; scale: Readonly<{ x: number; y: number }> }>,
  ): void {
    if (transform.rotation !== 0 || transform.scale.x !== 1 || transform.scale.y !== 1) return;
    const grid: (string | undefined)[][] = Array.from({ length: rows }, () => Array<string | undefined>(columns).fill(undefined));
    for (const cell of cells) if (cell.y >= 0 && cell.y < rows && cell.x >= 0 && cell.x < columns) grid[cell.y][cell.x] = cell.tileId;
    const scene = this.tileOptions.context.scene;
    this.terrainBlend = renderTerrainBlend({
      scene,
      grid,
      lookup: terrainBlendLookup(tiles),
      resolveVisual: (tileId, x, y) => {
        const visual = this.resolveVisual(tiles[tileId], x, y);
        return { ...visual, textureKey: this.tileOptions.context.assetKey(visual.assetId) };
      },
      dimensions: { width: columns * this.tileSize, height: rows * this.tileSize, tileSize: this.tileSize, columns, rows },
      seed: this.seed,
    });
    const waterKind = (tileId: string): WaterKind | undefined => {
      for (const assetId of tiles[tileId]?.assetIds ?? []) if (WATER_ASSETS[assetId]) return WATER_ASSETS[assetId];
      return undefined;
    };
    this.waterSurface = WaterSurfaceLayer.create({
      scene,
      grid,
      waterKind,
      tileSize: this.tileSize,
      textures: {
        shallow: this.tileOptions.context.assetKey('sheet.grounds.19x19.water'),
        deep: this.tileOptions.context.assetKey('sheet.grounds.19x19.deep-water'),
      },
    });
  }

  /**
   * Places a merged static body at its rectangle. `updateFromGameObject` /
   * `refreshBody` would reset the body to its game object's size, so the body
   * is positioned directly (collidable layers are unrotated and unscaled).
   */
  private placeTileBody({ zone, rect }: MountedBody, layerPosition: Readonly<{ x: number; y: number }>): void {
    const body = zone.body as TileStaticBody | null;
    if (!body) return;
    const x = layerPosition.x + rect.x;
    const y = layerPosition.y + rect.y;
    body.world.staticTree.remove(body);
    body.width = rect.width;
    body.height = rect.height;
    body.halfWidth = Math.abs(rect.width / 2);
    body.halfHeight = Math.abs(rect.height / 2);
    body.position.set(x, y);
    body.updateCenter();
    body.world.staticTree.insert(body);
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): TileMapLayer2DNode {
    return new TileMapLayer2DNode({
      ...this.tileOptions,
      runtimeId,
      name: this.name,
      position: this.position,
      rotation: this.rotation,
      scale: this.scale,
      visible: this.visible,
      collisionEnabled: this.collisionEnabled,
    });
  }

  private mountCell(x: number, y: number, tile: TileSetTile): void {
    const visual = this.resolveVisual(tile, x, y);
    const textureKey = this.tileOptions.context.assetKey(visual.assetId);
    const image = this.tileOptions.context.scene.add.image(0, 0, textureKey, visual.frame)
      .setOrigin(0)
      .setFlip(visual.flipX, visual.flipY);
    this.mountedTiles.push({ x, y, image });
  }

  /** Merges solid cells of the same tile into rectangles and mounts one static body per rectangle. */
  private mountCollision(
    cells: readonly { readonly x: number; readonly y: number; readonly tileId: string }[],
    tiles: Readonly<Record<string, TileSetTile>>,
  ): void {
    const solidByTile = new Map<string, { x: number; y: number }[]>();
    for (const cell of cells) {
      if (!tiles[cell.tileId]?.physics) continue;
      const list = solidByTile.get(cell.tileId) ?? [];
      list.push(cell);
      solidByTile.set(cell.tileId, list);
    }
    for (const [tileId, solid] of solidByTile) {
      const inset = { left: 6, right: 6, top: 8, bottom: 8, ...tiles[tileId].physics!.inset };
      // A tile may name its own layer: water blocks walkers but not projectiles.
      const tileLayer = tiles[tileId].physics!.layer;
      const layer = tileLayer === undefined ? this.collisionLayer : collisionLayerValue(tileLayer);
      if (this.tileSize - inset.left - inset.right <= 0 || this.tileSize - inset.top - inset.bottom <= 0) {
        throw new Error(`Tile '${tileId}' collision inset consumes its entire ${this.tileSize}px cell`);
      }
      for (const cellRect of mergeCellRectangles(solid)) {
        this.mountBody({
          x: cellRect.x * this.tileSize + inset.left,
          y: cellRect.y * this.tileSize + inset.top,
          width: cellRect.width * this.tileSize - inset.left - inset.right,
          height: cellRect.height * this.tileSize - inset.top - inset.bottom,
        }, `${tileId}-${cellRect.x}-${cellRect.y}`, layer);
      }
    }
  }

  private mountBody(rect: TileBodyRect, key: string, collisionLayer: number): void {
    const scene = this.tileOptions.context.scene;
    const zone = scene.add.zone(rect.x, rect.y, rect.width, rect.height).setOrigin(0);
    scene.physics.add.existing(zone, true);
    const body = zone.body as Phaser.Physics.Arcade.StaticBody;
    body.enable = this.collisionEnabledValue;
    this.mountedBodies.push({ zone, rect });
    const node = this;
    const participant: PhaserBlockingParticipant = {
      runtimeId: `${this.runtimeId}/tile-body-${key}` as RuntimeNodeId,
      node: this,
      physicsObject: zone,
      isStaticBody: true,
      collisionLayer,
      collisionMask: this.collisionMask,
      get blockingActive() { return node.collisionEnabled && node.visible && body.enable; },
      beginBlockingStep() {},
      recordBlockingContact(_contact: BlockingContact) {},
    };
    const unregister = this.tileOptions.context.registerBlockingParticipant(participant);
    this.entryDisposables.add(() => unregister());
  }

  private resolveVisual(tile: TileSetTile, x: number, y: number): {
    readonly assetId: string;
    readonly frame?: number;
    readonly flipX: boolean;
    readonly flipY: boolean;
  } {
    const assetId = tile.assetIds[tileHash(x, y, this.seed) % tile.assetIds.length];
    if (!Object.hasOwn(ASSET_MANIFEST.assets, assetId)) throw new Error(`TileMapLayer2D references unknown asset '${assetId}'`);
    if (tile.selection === 'seeded-hash') return { assetId, flipX: false, flipY: false };
    const asset = getAsset(assetId as AssetId);
    if (asset.source.kind !== 'spritesheet') throw new Error(`Tile '${assetId}' requires a spritesheet for '${tile.selection}' selection`);
    const key = `${assetId}:${tile.selection}`;
    let selection = this.groundSelections.get(key);
    if (!selection) {
      selection = createGroundSheetSelection(assetId as AssetId, this.seed, tile.selection);
      this.groundSelections.set(key, selection);
    }
    return { assetId, ...selection.resolveAt(x, y) };
  }
}
