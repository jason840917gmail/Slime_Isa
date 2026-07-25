import Phaser from 'phaser';

import {
  getVisualSet,
  resolveFrameVisual,
  type ResolvedVisualTransform,
  type VisualSetId,
} from '../../content/visuals/VisualCatalog';
import { getAsset } from '../../infrastructure/assets/manifest';

type VisualAnchor = Phaser.GameObjects.GameObject & {
  readonly x: number;
  readonly y: number;
};

export interface VisualEffects {
  scaleX: number;
  scaleY: number;
  alpha: number;
}

export interface AnimatedVisualOptions {
  readonly depth: number;
  readonly initialFrame?: number;
}

/**
 * Render-only animated sprite attached to a stable gameplay/physics anchor.
 *
 * Visual-set transforms and temporary effects are applied only to this
 * sprite. They never resize or relocate the anchor's Arcade body.
 */
export class AnimatedVisual {
  readonly sprite: Phaser.GameObjects.Sprite;
  readonly effects: VisualEffects = { scaleX: 1, scaleY: 1, alpha: 1 };

  private frameIndex: number;
  private transform: ResolvedVisualTransform;
  private destroyed = false;

  constructor(
    private readonly scene: Phaser.Scene,
    private readonly anchor: VisualAnchor,
    readonly visualSetId: VisualSetId,
    options: AnimatedVisualOptions,
  ) {
    const definition = getVisualSet(visualSetId);
    const asset = getAsset(definition.assetId);
    const textureKey = asset.runtime.textureKey;
    this.frameIndex = options.initialFrame ?? 0;
    this.transform = resolveFrameVisual(visualSetId, this.frameIndex);
    this.sprite = asset.source.kind === 'spritesheet'
      ? scene.add.sprite(anchor.x, anchor.y, textureKey, this.frameIndex)
      : scene.add.sprite(anchor.x, anchor.y, textureKey);
    this.sprite.setDepth(options.depth);
    this.sprite.on(Phaser.Animations.Events.ANIMATION_UPDATE, this.handleAnimationUpdate);
    this.anchor.once(Phaser.GameObjects.Events.DESTROY, this.handleAnchorDestroy);
    this.scene.events.once(Phaser.Scenes.Events.SHUTDOWN, this.handleSceneShutdown);
    this.applyTransform();
  }

  play(runtimeKey: string, ignoreIfPlaying = true): this {
    this.sprite.play(runtimeKey, ignoreIfPlaying);
    const currentFrame = this.sprite.anims.currentFrame?.textureFrame;
    this.setFrameIndex(typeof currentFrame === 'number' ? currentFrame : Number(currentFrame) || 0);
    return this;
  }

  onceComplete(runtimeKey: string, callback: () => void): this {
    this.sprite.once(
      Phaser.Animations.Events.ANIMATION_COMPLETE_KEY + runtimeKey,
      callback,
    );
    return this;
  }

  setFlipX(flipped: boolean): this {
    this.sprite.setFlipX(flipped);
    this.applyTransform();
    return this;
  }

  setTint(color: number): this {
    this.sprite.setTint(color);
    return this;
  }

  setTintFill(color: number): this {
    this.sprite.setTintFill(color);
    return this;
  }

  clearTint(): this {
    this.sprite.clearTint();
    return this;
  }

  setAlpha(alpha: number): this {
    this.effects.alpha = alpha;
    this.applyTransform();
    return this;
  }

  setDepth(depth: number): this {
    this.sprite.setDepth(depth);
    return this;
  }

  setVisible(visible: boolean): this {
    this.sprite.setVisible(visible);
    return this;
  }

  setScaleMultiplier(scaleX: number, scaleY = scaleX): this {
    this.effects.scaleX = scaleX;
    this.effects.scaleY = scaleY;
    this.applyTransform();
    return this;
  }

  resetEffects(): this {
    this.effects.scaleX = 1;
    this.effects.scaleY = 1;
    this.effects.alpha = 1;
    this.applyTransform();
    return this;
  }

  update(): void {
    this.applyTransform();
  }

  getBounds(): Phaser.Geom.Rectangle {
    return this.sprite.getBounds();
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.scene.tweens.killTweensOf(this.effects);
    this.scene.tweens.killTweensOf(this.sprite);
    this.sprite.off(Phaser.Animations.Events.ANIMATION_UPDATE, this.handleAnimationUpdate);
    this.anchor.off(Phaser.GameObjects.Events.DESTROY, this.handleAnchorDestroy);
    this.scene.events.off(Phaser.Scenes.Events.SHUTDOWN, this.handleSceneShutdown);
    this.sprite.destroy();
  }

  private setFrameIndex(frameIndex: number): void {
    if (this.frameIndex === frameIndex) return;
    this.frameIndex = frameIndex;
    this.transform = resolveFrameVisual(this.visualSetId, frameIndex);
    this.applyTransform();
  }

  private applyTransform(): void {
    if (this.destroyed) return;
    const [scaleX, scaleY] = this.transform.scale;
    const resolvedScaleX = scaleX * this.effects.scaleX;
    const resolvedScaleY = scaleY * this.effects.scaleY;
    const horizontalDirection = this.sprite.flipX ? -1 : 1;
    const verticalDirection = this.sprite.flipY ? -1 : 1;
    const offsetX = this.transform.sourceOffset[0] * resolvedScaleX * horizontalDirection;
    const offsetY = this.transform.sourceOffset[1] * resolvedScaleY * verticalDirection;

    this.sprite
      .setOrigin(this.transform.origin[0], this.transform.origin[1])
      .setScale(resolvedScaleX, resolvedScaleY)
      .setAlpha(this.effects.alpha)
      .setPosition(this.anchor.x + offsetX, this.anchor.y + offsetY);
  }

  private readonly handleAnimationUpdate = (
    _animation: Phaser.Animations.Animation,
    frame: Phaser.Animations.AnimationFrame,
  ): void => {
    const frameIndex = typeof frame.textureFrame === 'number'
      ? frame.textureFrame
      : Number(frame.textureFrame) || 0;
    this.setFrameIndex(frameIndex);
  };

  private readonly handleAnchorDestroy = (): void => {
    this.destroy();
  };

  private readonly handleSceneShutdown = (): void => {
    this.destroy();
  };
}
