import type Phaser from 'phaser';

import type { ResourceId, RuntimeNodeId } from '../../content/scenes/identifiers';
import { Node2D, type Node2DOptions, type Vector2 } from '../../runtime/scene/Node2D';
import { defaultWorldDepthResolver, resolveObjectDepthAnchorY, type WorldDepthBand, type WorldDepthResolver } from '../../presentation/WorldDepth';
import type { PhaserNodeContext } from '../scenes/PhaserNodeContext';
import type { PresentationParticipant } from './PresentationSync';
import type {
  WorldVisual,
  WorldVisualEffects,
  WorldVisualRenderState,
} from '../../presentation/WorldVisual';
import {
  resolveWorldOcclusionRectangle,
  type RenderSpriteGeometry,
  type SourceFrameDimensions,
  type SourceOcclusionBounds,
  type WorldRectangle,
} from '../../presentation/WorldOcclusion';

/**
 * World-space occlusion and depth-bounds geometry exactly as the runtime
 * resolves it. Occlusion bounds sit on the rendered frame (visual offset
 * included); depth bounds sit on the frame at the node's own position, and
 * their bottom edge is the sort line (see `resolveObjectDepthAnchorY`).
 */
export interface SpriteBoundsGeometry {
  readonly sourceFrame: SourceFrameDimensions;
  readonly occlusionSprite: RenderSpriteGeometry;
  readonly depthSprite: RenderSpriteGeometry;
  readonly occlusion?: WorldRectangle;
  readonly depth?: WorldRectangle;
  /** Ground point the sprite sorts by: node X and the resolved sort Y. */
  readonly anchor: { readonly x: number; readonly y: number };
}

export interface Sprite2DNodeOptions extends Node2DOptions {
  readonly context: PhaserNodeContext;
  readonly texture: ResourceId;
  readonly frame?: number;
  readonly origin?: Vector2;
  readonly visualOffset?: Vector2;
  readonly alpha?: number;
  readonly tint?: string;
  readonly flipX?: boolean;
  readonly flipY?: boolean;
  /**
   * `world-sorted` sorts by this sprite's own ground point, `explicit` uses
   * `depth`, and `relative` draws at the nearest depth-source ancestor's depth
   * plus `depthOffset` (attachments such as weapons, effect layers and
   * character visuals that sort by their body's feet).
   */
  readonly depthMode?: 'world-sorted' | 'explicit' | 'relative';
  readonly depthBand?: WorldDepthBand;
  readonly depth?: number;
  readonly depthOffset?: number;
  readonly depthResolver?: WorldDepthResolver;
  readonly occlusionBounds?: SourceOcclusionBounds;
  /** Full source rectangle (the editor and dev overlay draw it); only its bottom edge affects sorting. */
  readonly depthBounds?: SourceOcclusionBounds;
}

function colorNumber(value: string | undefined): number | undefined {
  if (!value) return undefined;
  if (!/^#[0-9a-f]{6}$/i.test(value)) throw new Error(`Sprite tint '${value}' must be #RRGGBB`);
  return Number.parseInt(value.slice(1), 16);
}

export class Sprite2DNode extends Node2D implements PresentationParticipant, WorldVisual {
  readonly effects: WorldVisualEffects = { scaleX: 1, scaleY: 1, alpha: 1, offsetX: 0, offsetY: 0 };
  private sprite?: Phaser.GameObjects.Sprite;
  private currentFrame?: number;
  private currentAlpha: number;
  private currentFlipX: boolean;
  private currentFlipY: boolean;
  private currentDepthOffset: number;
  private currentVisualOffset: Vector2;
  private resolvedDepth = 0;
  private resolvedSortY = 0;
  private relativeBase?: { readonly source: Node2D; readonly sortY: number; readonly depth: number };
  private readonly origin: Vector2;
  private readonly tint?: number;
  private readonly depthResolver: WorldDepthResolver;
  private lastPresentation?: {
    readonly transformRevision: number;
    readonly frame: number | undefined;
    readonly alpha: number;
    readonly flipX: boolean;
    readonly flipY: boolean;
    readonly depth: number;
    readonly visualOffsetX: number;
    readonly visualOffsetY: number;
    readonly visible: boolean;
    readonly effectScaleX: number;
    readonly effectScaleY: number;
    readonly effectAlpha: number;
    readonly effectOffsetX: number;
    readonly effectOffsetY: number;
  };

  constructor(private readonly spriteOptions: Sprite2DNodeOptions) {
    super(spriteOptions);
    this.origin = spriteOptions.origin ?? { x: 0.5, y: 0.5 };
    this.currentVisualOffset = spriteOptions.visualOffset ?? { x: 0, y: 0 };
    this.currentFlipX = spriteOptions.flipX === true;
    this.currentFlipY = spriteOptions.flipY === true;
    this.currentDepthOffset = spriteOptions.depthOffset ?? 0;
    this.tint = colorNumber(spriteOptions.tint);
    this.depthResolver = spriteOptions.depthResolver ?? defaultWorldDepthResolver;
    this.currentFrame = spriteOptions.frame;
    this.currentAlpha = spriteOptions.alpha ?? 1;
    const alpha = this.currentAlpha;
    if (![this.origin.x, this.origin.y, this.currentVisualOffset.x, this.currentVisualOffset.y, alpha, spriteOptions.depth ?? 0, this.currentDepthOffset].every(Number.isFinite)) {
      throw new Error('Sprite presentation values must be finite');
    }
    if (alpha < 0 || alpha > 1) throw new Error('Sprite alpha must be between 0 and 1');
    if (spriteOptions.frame !== undefined && (!Number.isInteger(spriteOptions.frame) || spriteOptions.frame < 0)) throw new Error('Sprite frame must be a non-negative integer');
  }

  get phaserObjectActive(): boolean { return this.sprite !== undefined; }
  get presentationObject(): Phaser.GameObjects.Sprite { return this.requireSprite(); }
  get occlusionBounds(): SourceOcclusionBounds | undefined { return this.spriteOptions.occlusionBounds; }
  get depthBounds(): SourceOcclusionBounds | undefined { return this.spriteOptions.depthBounds; }
  /** True when this sprite sorts by its own ground point rather than a depth-source ancestor or explicit depth. */
  get selfSorted(): boolean {
    const mode = this.spriteOptions.depthMode ?? 'world-sorted';
    return mode === 'world-sorted' || (mode === 'relative' && !this.isDepthSource && !this.find_depth_source());
  }

  /** Occlusion/depth-bounds guides for the dev overlay and Scene Studio; undefined while not rendered. */
  boundsGeometry(): SpriteBoundsGeometry | undefined {
    const sprite = this.sprite;
    if (!sprite) return undefined;
    const sourceFrame = { width: sprite.frame.realWidth, height: sprite.frame.realHeight };
    const occlusionSprite: RenderSpriteGeometry = {
      x: sprite.x, y: sprite.y, originX: sprite.originX, originY: sprite.originY,
      scaleX: sprite.scaleX, scaleY: sprite.scaleY, flipX: sprite.flipX, flipY: sprite.flipY,
    };
    const position = this.get_global_transform().position;
    // The runtime's depth math ignores the visual offset and vertical flip.
    const depthSprite: RenderSpriteGeometry = { ...occlusionSprite, x: position.x, y: position.y, flipY: false };
    const { occlusionBounds, depthBounds } = this.spriteOptions;
    return {
      sourceFrame,
      occlusionSprite,
      depthSprite,
      ...(occlusionBounds ? { occlusion: resolveWorldOcclusionRectangle(occlusionSprite, sourceFrame, occlusionBounds) } : {}),
      ...(depthBounds ? { depth: resolveWorldOcclusionRectangle(depthSprite, sourceFrame, depthBounds) } : {}),
      anchor: { x: position.x, y: this.resolvedSortY },
    };
  }
  get frame(): number { return this.currentFrame ?? 0; }
  set frame(value: number) {
    if (!Number.isInteger(value) || value < 0) throw new Error('Sprite frame must be a non-negative integer');
    this.currentFrame = value;
    this.sprite?.setFrame(value);
  }
  get alpha(): number { return this.currentAlpha; }
  set alpha(value: number) {
    if (!Number.isFinite(value) || value < 0 || value > 1) throw new Error('Sprite alpha must be between 0 and 1');
    this.currentAlpha = value;
    this.sprite?.setAlpha(value);
  }

  /** Horizontal mirror of the texture; animatable and settable by scripts (e.g. facing). */
  get flipX(): boolean { return this.currentFlipX; }
  set flipX(value: boolean) { this.currentFlipX = value === true; this.syncPresentation(1); }
  get flipY(): boolean { return this.currentFlipY; }
  set flipY(value: boolean) { this.currentFlipY = value === true; this.syncPresentation(1); }
  get visualOffset(): Vector2 { return { ...this.currentVisualOffset }; }
  set visualOffset(value: Vector2) {
    if (!Number.isFinite(value.x) || !Number.isFinite(value.y)) throw new Error('Sprite visual offset must be finite');
    this.currentVisualOffset = { x: value.x, y: value.y };
    this.syncPresentation(1);
  }
  /** Offset added to the depth source's depth when `depthMode` is `relative`. */
  get depthOffset(): number { return this.currentDepthOffset; }
  set depthOffset(value: number) {
    if (!Number.isFinite(value)) throw new Error('Sprite depth offset must be finite');
    this.currentDepthOffset = value;
    this.syncPresentation(1);
  }
  /** Render depth applied by the last presentation sync. */
  get renderDepth(): number { return this.resolvedDepth; }
  /** World-space ground Y this sprite's depth was sorted by in the last presentation sync. */
  get depthSortY(): number { return this.resolvedSortY; }

  setFlipX(flipped: boolean): this { this.flipX = flipped; return this; }
  setAlpha(alpha: number): this {
    if (!Number.isFinite(alpha) || alpha < 0 || alpha > 1) throw new Error('Sprite alpha must be between 0 and 1');
    this.effects.alpha = alpha;
    this.syncPresentation(1);
    return this;
  }
  setTintFill(color: number): this { this.sprite?.setTintFill(color); return this; }
  clearTint(): this { this.sprite?.clearTint(); return this; }

  resetEffects(): this {
    this.effects.scaleX = 1;
    this.effects.scaleY = 1;
    this.effects.alpha = 1;
    this.effects.offsetX = 0;
    this.effects.offsetY = 0;
    this.syncPresentation(1);
    return this;
  }

  getBounds(): Phaser.Geom.Rectangle { return this.requireSprite().getBounds(); }

  getRenderState(): WorldVisualRenderState {
    const sprite = this.requireSprite();
    return {
      textureKey: sprite.texture.key,
      frame: sprite.frame.name,
      sourceFrame: { width: sprite.frame.realWidth, height: sprite.frame.realHeight },
      x: sprite.x,
      y: sprite.y,
      originX: sprite.originX,
      originY: sprite.originY,
      scaleX: sprite.scaleX,
      scaleY: sprite.scaleY,
      alpha: sprite.alpha,
      flipX: sprite.flipX,
      flipY: sprite.flipY,
      rotation: sprite.rotation,
    };
  }

  mirrorTo(target: Phaser.GameObjects.Sprite, alpha = 0.72): void {
    const state = this.getRenderState();
    target
      .setTexture(state.textureKey, state.frame)
      .setPosition(state.x, state.y)
      .setOrigin(state.originX, state.originY)
      .setScale(state.scaleX, state.scaleY)
      .setFlip(state.flipX, state.flipY)
      .setRotation(state.rotation)
      .setAlpha(alpha);
  }

  override _enter_tree(): void {
    const resource = this.spriteOptions.context.resource(this.spriteOptions.texture);
    if (resource.kind !== 'texture' && resource.kind !== 'sprite-sheet') throw new Error(`Resource '${resource.resourceId}' cannot back Sprite2D`);
    const frame = this.currentFrame ?? (resource.kind === 'texture' ? resource.frame : undefined);
    if (frame !== undefined) this.currentFrame = frame;
    const sprite = this.spriteOptions.context.scene.add.sprite(0, 0, this.spriteOptions.context.assetKey(resource.assetId), frame);
    this.sprite = sprite;
    this.lastPresentation = undefined;
    sprite.setName(this.runtimeId);
    sprite.setOrigin(this.origin.x, this.origin.y);
    sprite.setAlpha(this.currentAlpha);
    sprite.setFlip(this.currentFlipX, this.currentFlipY);
    if (this.tint !== undefined) sprite.setTint(this.tint);
    const unregister = this.spriteOptions.context.registerPresentation(this);
    this.entryDisposables.add(() => unregister());
    this.entryDisposables.add(() => { sprite.destroy(); if (this.sprite === sprite) this.sprite = undefined; });
    this.syncPresentation(1);
  }

  syncPresentation(_alpha: number): void {
    const sprite = this.sprite;
    if (!sprite || sprite.active === false) return;
    const transformRevision = this.get_global_transform_revision();
    // Relative depth depends on another node, so it is re-resolved every sync;
    // self-sorted depth only changes with this sprite's own presentation.
    const relativeDepth = this.spriteOptions.depthMode === 'relative' ? this.resolveDepth(sprite) : undefined;
    const previous = this.lastPresentation;
    if (previous
      && previous.transformRevision === transformRevision
      && previous.frame === this.currentFrame
      && previous.alpha === this.currentAlpha
      && previous.flipX === this.currentFlipX
      && previous.flipY === this.currentFlipY
      && (relativeDepth === undefined || previous.depth === relativeDepth)
      && previous.visualOffsetX === this.currentVisualOffset.x
      && previous.visualOffsetY === this.currentVisualOffset.y
      && previous.visible === this.visible
      && previous.effectScaleX === this.effects.scaleX
      && previous.effectScaleY === this.effects.scaleY
      && previous.effectAlpha === this.effects.alpha
      && previous.effectOffsetX === this.effects.offsetX
      && previous.effectOffsetY === this.effects.offsetY) return;
    const transform = this.get_global_transform();
    const offsetX = this.currentVisualOffset.x * transform.scale.x;
    const offsetY = this.currentVisualOffset.y * transform.scale.y;
    const cosine = Math.cos(transform.rotation);
    const sine = Math.sin(transform.rotation);
    sprite.setPosition(
      transform.position.x + offsetX * cosine - offsetY * sine + this.effects.offsetX,
      transform.position.y + offsetX * sine + offsetY * cosine + this.effects.offsetY,
    );
    sprite.setRotation(transform.rotation);
    sprite.setScale(transform.scale.x * this.effects.scaleX, transform.scale.y * this.effects.scaleY);
    sprite.setAlpha(this.currentAlpha * this.effects.alpha);
    sprite.setFlip(this.currentFlipX, this.currentFlipY);
    if (this.currentFrame !== undefined) sprite.setFrame(this.currentFrame);
    sprite.setVisible(this.visible);
    const depth = relativeDepth ?? this.resolveDepth(sprite);
    sprite.setDepth(depth);
    this.lastPresentation = {
      transformRevision,
      frame: this.currentFrame,
      alpha: this.currentAlpha,
      flipX: this.currentFlipX,
      flipY: this.currentFlipY,
      depth,
      visualOffsetX: this.currentVisualOffset.x,
      visualOffsetY: this.currentVisualOffset.y,
      visible: this.visible,
      effectScaleX: this.effects.scaleX,
      effectScaleY: this.effects.scaleY,
      effectAlpha: this.effects.alpha,
      effectOffsetX: this.effects.offsetX,
      effectOffsetY: this.effects.offsetY,
    };
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): Sprite2DNode {
    return new Sprite2DNode({
      ...this.spriteOptions, runtimeId, name: this.name, position: this.position, rotation: this.rotation, scale: this.scale, visible: this.visible,
      flipX: this.currentFlipX, flipY: this.currentFlipY, depthOffset: this.currentDepthOffset, visualOffset: this.currentVisualOffset,
      depthAnchor: this.depthAnchor,
    });
  }

  private resolveDepth(sprite: Phaser.GameObjects.Sprite): number {
    const mode = this.spriteOptions.depthMode ?? 'world-sorted';
    if (mode === 'explicit') {
      this.resolvedSortY = this.get_global_transform().position.y;
      this.resolvedDepth = this.spriteOptions.depth ?? 0;
      return this.resolvedDepth;
    }
    if (mode === 'relative') {
      const source = this.isDepthSource ? this : this.find_depth_source();
      if (source) {
        const sortY = source.get_global_depth_anchor_y();
        const cache = this.relativeBase;
        const base = source.depthOverride ?? (cache && cache.source === source && cache.sortY === sortY
          ? cache.depth
          : this.depthResolver.resolve(sortY, { band: this.spriteOptions.depthBand, stableId: source.runtimeId }).depth);
        if (source.depthOverride === undefined) this.relativeBase = { source, sortY, depth: base };
        this.resolvedSortY = sortY;
        this.resolvedDepth = base + this.currentDepthOffset;
        return this.resolvedDepth;
      }
    }
    const transform = this.get_global_transform();
    this.resolvedSortY = this.spriteOptions.depthBounds
      ? resolveObjectDepthAnchorY(transform.position.y, {
          sourceFrameHeight: sprite.frame.realHeight,
          originY: this.origin.y,
          bounds: this.spriteOptions.depthBounds,
          scaleY: Math.abs(transform.scale.y * this.effects.scaleY),
        })
      : transform.position.y;
    this.resolvedDepth = this.depthResolver.resolve(this.resolvedSortY, { band: this.spriteOptions.depthBand, stableId: this.runtimeId }).depth
      + (mode === 'relative' ? this.currentDepthOffset : 0);
    return this.resolvedDepth;
  }

  private requireSprite(): Phaser.GameObjects.Sprite {
    if (!this.sprite) throw new Error(`Sprite2D '${this.runtimeId}' is outside the scene tree.`);
    return this.sprite;
  }
}
