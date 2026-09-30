import type Phaser from 'phaser';

export interface WorldVisualRenderState {
  readonly textureKey: string;
  readonly frame: number | string;
  readonly sourceFrame: { readonly width: number; readonly height: number };
  readonly x: number;
  readonly y: number;
  readonly originX: number;
  readonly originY: number;
  readonly scaleX: number;
  readonly scaleY: number;
  readonly alpha: number;
  readonly flipX: boolean;
  readonly flipY: boolean;
  readonly rotation: number;
}

export interface WorldVisualEffects {
  scaleX: number;
  scaleY: number;
  alpha: number;
  offsetX: number;
  offsetY: number;
}

export interface WorldVisual {
  readonly effects: WorldVisualEffects;
  setFlipX(flipped: boolean): this;
  setAlpha(alpha: number): this;
  setTintFill(color: number): this;
  /** Multiplies the art by `color` (a look such as a Gulp form); `clearTint` removes it. */
  setTint(color: number): this;
  clearTint(): this;
  resetEffects(): this;
  getBounds(): Phaser.Geom.Rectangle;
  getRenderState(): WorldVisualRenderState;
  mirrorTo(target: Phaser.GameObjects.Sprite, alpha?: number): void;
}
