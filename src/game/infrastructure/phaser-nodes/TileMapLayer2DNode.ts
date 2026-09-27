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
import { collisionBits } from '../../content/physics/CollisionLayers';
import type { PresentationParticipant } from './PresentationSync';

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
  readonly collidable: boolean;
  /** Authored tile-set collision rectangle, relative to the cell's top-left corner. */
  readonly bodyRect?: TileBodyRect;
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
  private readonly groundSelections = new Map<string, GroundSheetSelection>();
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
  get collisionBodyCount(): number { return this.mountedTiles.filter((tile) => tile.collidable).length; }
  get collisionEnabled(): boolean { return this.collisionEnabledValue; }

  /** World-space Arcade rectangles of the collidable tiles, for inspection and tests. */
  collisionBodyBounds(): readonly TileBodyRect[] {
    return this.mountedTiles.flatMap((tile) => {
      const body = tile.collidable ? tile.image.body as Phaser.Physics.Arcade.StaticBody | null : null;
      return body ? [{ x: body.position.x, y: body.position.y, width: body.width, height: body.height }] : [];
    });
  }

  setCollisionEnabled(enabled: boolean): void {
    this.collisionEnabledValue = enabled;
    for (const tile of this.mountedTiles) {
      if (!tile.collidable || !tile.image.body) continue;
      (tile.image.body as Phaser.Physics.Arcade.StaticBody).enable = enabled;
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
    const unregister = this.tileOptions.context.registerPresentation(this);
    this.entryDisposables.add(() => unregister());
    this.entryDisposables.add(() => {
      for (const tile of this.mountedTiles) tile.image.destroy();
      this.mountedTiles.length = 0;
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
      const localX = (tile.x + (tile.collidable ? 0.5 : 0)) * this.tileSize * transform.scale.x;
      const localY = (tile.y + (tile.collidable ? 0.5 : 0)) * this.tileSize * transform.scale.y;
      tile.image
        .setPosition(
          transform.position.x + localX * cosine - localY * sine,
          transform.position.y + localX * sine + localY * cosine,
        )
        .setRotation(transform.rotation)
        .setScale(transform.scale.x, transform.scale.y)
        .setVisible(this.visible)
        .setDepth(this.depth);
      if (tile.bodyRect) this.placeTileBody(tile, tile.bodyRect, transform.position);
    }
  }

  /**
   * Places a static tile body at its authored tile-set collision rectangle.
   * `updateFromGameObject`/`refreshBody` would reset the body to the image's
   * display size and discard the authored inset, so the body is positioned
   * directly (collidable layers are unrotated and unscaled).
   */
  private placeTileBody(tile: MountedTile, rect: TileBodyRect, layerPosition: Readonly<{ x: number; y: number }>): void {
    const body = tile.image.body as TileStaticBody | null;
    if (!body) return;
    const x = layerPosition.x + tile.x * this.tileSize + rect.x;
    const y = layerPosition.y + tile.y * this.tileSize + rect.y;
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
    if (!tile.physics) {
      const image = this.tileOptions.context.scene.add.image(0, 0, textureKey, visual.frame)
        .setOrigin(0)
        .setFlip(visual.flipX, visual.flipY);
      this.mountedTiles.push({ x, y, image, collidable: false });
      return;
    }
    const image = this.tileOptions.context.scene.physics.add.staticImage(0, 0, textureKey, visual.frame)
      .setFlip(visual.flipX, visual.flipY);
    const inset = { left: 6, right: 6, top: 8, bottom: 8, ...tile.physics.inset };
    const bodyWidth = this.tileSize - inset.left - inset.right;
    const bodyHeight = this.tileSize - inset.top - inset.bottom;
    if (bodyWidth <= 0 || bodyHeight <= 0) {
      image.destroy();
      throw new Error(`Tile collision inset at '${x},${y}' consumes its entire ${this.tileSize}px cell`);
    }
    const body = image.body as Phaser.Physics.Arcade.StaticBody;
    body.enable = this.collisionEnabledValue;
    this.mountedTiles.push({ x, y, image, collidable: true, bodyRect: { x: inset.left, y: inset.top, width: bodyWidth, height: bodyHeight } });
    const node = this;
    const participant: PhaserBlockingParticipant = {
      runtimeId: `${this.runtimeId}/tile-${x}-${y}` as RuntimeNodeId,
      node: this,
      physicsObject: image,
      isStaticBody: true,
      collisionLayer: this.collisionLayer,
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
