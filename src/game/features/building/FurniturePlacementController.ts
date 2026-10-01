import Phaser from 'phaser';

import { DEPTH_BANDS } from '../../presentation/WorldDepth';
import { controlLabel } from '../player/ControlLabels';

/** How an object scene is drawn and how much floor it blocks, relative to its root. */
export interface PlaceableVisual {
  readonly textureKey: string;
  readonly frame: number;
  readonly scaleX: number;
  readonly scaleY: number;
  readonly originX: number;
  readonly originY: number;
  readonly rotation: number;
  /** Blocking collider centre and size relative to the root; absent for walk-over art. */
  readonly footprint?: { readonly x: number; readonly y: number; readonly width: number; readonly height: number };
}

export interface FootprintRect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

export interface PlacementRequest {
  readonly itemId: string;
  readonly sceneId: string;
  readonly x: number;
  readonly y: number;
}

export interface FurniturePlacementContext {
  readonly scene: Phaser.Scene;
  describe(sceneId: string): PlaceableVisual | undefined;
  playerPosition(): { readonly x: number; readonly y: number };
  /** True when nothing solid (terrain, objects, actors) overlaps the rectangle and it lies inside the world. */
  isAreaFree(rect: FootprintRect): boolean;
  /** Commits the placement (inventory, save, world); returns false when it could not be placed. */
  place(request: PlacementRequest): boolean;
  /** Placement mode started or ended (e.g. to hide interaction prompts). */
  onActiveChange(active: boolean): void;
  showHint(message: string): void;
}

/** Placement snaps to a half-tile grid so furniture lines up with floors and walls. */
const SNAP_PX = 32;
/** How far from the player furniture may be placed. */
const REACH_PX = 220;
const VALID_TINT = 0x9dffc8;
const INVALID_TINT = 0xff7a7a;

/**
 * Mouse-aimed furniture placement: a translucent preview follows the pointer,
 * snapped to the grid, green where the footprint is free and within reach, red
 * otherwise. The scene feeds it the player's controls: the attack button
 * places, the weapon wheel switches variants, and interact or Escape cancels.
 */
export class FurniturePlacementController {
  private itemId?: string;
  private sceneIds: readonly string[] = [];
  private variantIndex = 0;
  private visual?: PlaceableVisual;
  private ghost?: Phaser.GameObjects.Image;
  private outline?: Phaser.GameObjects.Graphics;
  private target?: { readonly x: number; readonly y: number; readonly valid: boolean };
  constructor(private readonly ctx: FurniturePlacementContext) {}

  get active(): boolean {
    return this.itemId !== undefined;
  }

  start(itemId: string, sceneIds: readonly string[]): boolean {
    if (sceneIds.length === 0) return false;
    this.cancel();
    this.itemId = itemId;
    this.sceneIds = sceneIds;
    this.variantIndex = 0;
    if (!this.showVariant()) {
      this.cancel();
      return false;
    }
    this.ctx.onActiveChange(true);
    const place = controlLabel('attack');
    const cancel = `${controlLabel('interact')} or ${controlLabel('pause')}`;
    this.ctx.showHint(sceneIds.length > 1
      ? `${place} to place · ${controlLabel('weapon-next')} to switch · ${cancel} to cancel`
      : `${place} to place · ${cancel} to cancel`);
    return true;
  }

  cancel(): void {
    const wasActive = this.active;
    this.itemId = undefined;
    this.visual = undefined;
    this.target = undefined;
    this.ghost?.destroy();
    this.ghost = undefined;
    this.outline?.destroy();
    this.outline = undefined;
    if (wasActive) this.ctx.onActiveChange(false);
  }

  /** Called every frame while the world runs. */
  update(): void {
    if (!this.active || !this.visual || !this.ghost) return;
    const camera = this.ctx.scene.cameras.main;
    const pointer = this.ctx.scene.input.activePointer;
    const world = camera.getWorldPoint(pointer.x, pointer.y);
    const x = Math.round(world.x / SNAP_PX) * SNAP_PX;
    const y = Math.round(world.y / SNAP_PX) * SNAP_PX;
    const player = this.ctx.playerPosition();
    const inReach = Phaser.Math.Distance.Between(player.x, player.y, x, y) <= REACH_PX;
    const footprint = this.footprintAt(x, y);
    const valid = inReach && (!footprint || this.ctx.isAreaFree(footprint));
    this.target = { x, y, valid };

    this.ghost.setPosition(x, y).setTint(valid ? VALID_TINT : INVALID_TINT);
    this.outline?.clear();
    if (footprint && this.outline) {
      this.outline.lineStyle(2, valid ? VALID_TINT : INVALID_TINT, 0.9);
      this.outline.strokeRect(footprint.x, footprint.y, footprint.width, footprint.height);
    }
  }

  /** Shows the next (`step` 1) or previous (-1) variant of the item, if it has several. */
  cycleVariant(step: 1 | -1): void {
    if (!this.active || this.sceneIds.length < 2) return;
    const count = this.sceneIds.length;
    this.variantIndex = (this.variantIndex + step + count) % count;
    this.showVariant();
  }

  /** The place button; returns true when placement consumed it. */
  handlePointerDown(): boolean {
    if (!this.active) return false;
    const target = this.target;
    if (!target || !target.valid || !this.itemId) {
      this.ctx.showHint(target && !target.valid ? "Can't place it there" : 'Aim at a free spot');
      return true;
    }
    const placed = this.ctx.place({ itemId: this.itemId, sceneId: this.sceneIds[this.variantIndex]!, x: target.x, y: target.y });
    if (placed) this.cancel();
    return true;
  }

  destroy(): void {
    this.cancel();
  }

  private showVariant(): boolean {
    const visual = this.ctx.describe(this.sceneIds[this.variantIndex]!);
    if (!visual) return false;
    this.visual = visual;
    this.ghost?.destroy();
    this.ghost = this.ctx.scene.add.image(0, 0, visual.textureKey, visual.frame)
      .setOrigin(visual.originX, visual.originY)
      .setScale(visual.scaleX, visual.scaleY)
      .setRotation(visual.rotation)
      .setAlpha(0.65)
      .setDepth(DEPTH_BANDS['overhead-artwork']);
    this.outline ??= this.ctx.scene.add.graphics().setDepth(DEPTH_BANDS['overhead-artwork'] + 1);
    return true;
  }

  private footprintAt(x: number, y: number): FootprintRect | undefined {
    const footprint = this.visual?.footprint;
    if (!footprint) return undefined;
    return {
      x: x + footprint.x - footprint.width / 2,
      y: y + footprint.y - footprint.height / 2,
      width: footprint.width,
      height: footprint.height,
    };
  }
}
