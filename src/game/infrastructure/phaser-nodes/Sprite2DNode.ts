import type Phaser from 'phaser';

import type { ResourceId, RuntimeNodeId } from '../../content/scenes/identifiers';
import { Node2D, type Node2DOptions, type Vector2 } from '../../runtime/scene/Node2D';
import { defaultWorldDepthResolver, type WorldDepthBand, type WorldDepthResolver } from '../../presentation/WorldDepth';
import type { PhaserNodeContext } from '../scenes/PhaserNodeContext';
import type { PresentationParticipant } from './PresentationSync';
import type {
  WorldVisual,
  WorldVisualEffects,
  WorldVisualRenderState,
} from '../../presentation/WorldVisual';

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
  readonly depthMode?: 'world-sorted' | 'explicit';
  readonly depthBand?: WorldDepthBand;
  readonly depth?: number;
  readonly depthResolver?: WorldDepthResolver;
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
  private readonly origin: Vector2;
  private readonly visualOffset: Vector2;
  private readonly tint?: number;
  private readonly depthResolver: WorldDepthResolver;

  constructor(private readonly spriteOptions: Sprite2DNodeOptions) {
    super(spriteOptions);
    this.origin = spriteOptions.origin ?? { x: 0.5, y: 0.5 };
    this.visualOffset = spriteOptions.visualOffset ?? { x: 0, y: 0 };
    this.tint = colorNumber(spriteOptions.tint);
    this.depthResolver = spriteOptions.depthResolver ?? defaultWorldDepthResolver;
    this.currentFrame = spriteOptions.frame;
    this.currentAlpha = spriteOptions.alpha ?? 1;
    const alpha = this.currentAlpha;
    if (![this.origin.x, this.origin.y, this.visualOffset.x, this.visualOffset.y, alpha, spriteOptions.depth ?? 0].every(Number.isFinite)) {
      throw new Error('Sprite presentation values must be finite');
    }
    if (alpha < 0 || alpha > 1) throw new Error('Sprite alpha must be between 0 and 1');
    if (spriteOptions.frame !== undefined && (!Number.isInteger(spriteOptions.frame) || spriteOptions.frame < 0)) throw new Error('Sprite frame must be a non-negative integer');
  }

  get phaserObjectActive(): boolean { return this.sprite !== undefined; }
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

  setFlipX(flipped: boolean): this { this.sprite?.setFlipX(flipped); return this; }
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
    sprite.setName(this.runtimeId);
    sprite.setOrigin(this.origin.x, this.origin.y);
    sprite.setAlpha(this.currentAlpha);
    sprite.setFlip(Boolean(this.spriteOptions.flipX), Boolean(this.spriteOptions.flipY));
    if (this.tint !== undefined) sprite.setTint(this.tint);
    const unregister = this.spriteOptions.context.registerPresentation(this);
    this.entryDisposables.add(() => unregister());
    this.entryDisposables.add(() => { sprite.destroy(); if (this.sprite === sprite) this.sprite = undefined; });
    this.syncPresentation(1);
  }

  syncPresentation(_alpha: number): void {
    const sprite = this.sprite;
    if (!sprite) return;
    const transform = this.get_global_transform();
    const offsetX = this.visualOffset.x * transform.scale.x;
    const offsetY = this.visualOffset.y * transform.scale.y;
    const cosine = Math.cos(transform.rotation);
    const sine = Math.sin(transform.rotation);
    sprite.setPosition(
      transform.position.x + offsetX * cosine - offsetY * sine + this.effects.offsetX,
      transform.position.y + offsetX * sine + offsetY * cosine + this.effects.offsetY,
    );
    sprite.setRotation(transform.rotation);
    sprite.setScale(transform.scale.x * this.effects.scaleX, transform.scale.y * this.effects.scaleY);
    sprite.setAlpha(this.currentAlpha * this.effects.alpha);
    if (this.currentFrame !== undefined) sprite.setFrame(this.currentFrame);
    sprite.setVisible(this.visible);
    const depth = this.spriteOptions.depthMode === 'explicit'
      ? this.spriteOptions.depth ?? 0
      : this.depthResolver.resolve(transform.position.y, { band: this.spriteOptions.depthBand, stableId: this.runtimeId }).depth;
    sprite.setDepth(depth);
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): Sprite2DNode {
    return new Sprite2DNode({ ...this.spriteOptions, runtimeId, name: this.name, position: this.position, rotation: this.rotation, scale: this.scale, visible: this.visible });
  }

  private requireSprite(): Phaser.GameObjects.Sprite {
    if (!this.sprite) throw new Error(`Sprite2D '${this.runtimeId}' is outside the scene tree.`);
    return this.sprite;
  }
}
