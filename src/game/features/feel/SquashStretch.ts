import type Phaser from 'phaser';

import type { WorldVisualEffects } from '../../presentation/WorldVisual';

/** Roadmap 9.2: the moments the slime's jelly body deforms. */
export type SquashEvent = 'move-start' | 'jump' | 'land' | 'hit' | 'gulp';

export interface SquashPreset {
  /** Scale the body snaps to, then springs back from to 1. */
  readonly scaleX: number;
  readonly scaleY: number;
  readonly durationMs: number;
  readonly ease: string;
}

export const SQUASH_PRESETS: Readonly<Record<SquashEvent, SquashPreset>> = Object.freeze({
  // Leaning into a walk: a little taller and thinner.
  'move-start': { scaleX: 0.9, scaleY: 1.12, durationMs: 170, ease: 'Back.Out' },
  // Take-off stretch (the jump ability tweens its own stretch through the arc; this is its shape).
  jump: { scaleX: 0.82, scaleY: 1.35, durationMs: 200, ease: 'Quad.Out' },
  // Landing splat.
  land: { scaleX: 1.32, scaleY: 0.72, durationMs: 220, ease: 'Back.Out' },
  // Getting hit: flattened for a moment.
  hit: { scaleX: 1.22, scaleY: 0.8, durationMs: 190, ease: 'Back.Out' },
  // Swallowing a Gulp material: a wobbling bulge.
  gulp: { scaleX: 1.24, scaleY: 0.86, durationMs: 320, ease: 'Elastic.Out' },
});

/** Reduce motion keeps a third of the deformation. */
export const REDUCED_MOTION_SQUASH = 0.35;

/** The scale a deformation starts from; reduce motion softens it toward rest. */
export function squashStart(preset: SquashPreset, reduceMotion: boolean): { readonly x: number; readonly y: number } {
  const amount = reduceMotion ? REDUCED_MOTION_SQUASH : 1;
  return { x: 1 + (preset.scaleX - 1) * amount, y: 1 + (preset.scaleY - 1) * amount };
}

export interface SquashStretchContext {
  readonly scene: Phaser.Scene;
  /** The player sprite's effect channel (multiplied into its authored scale). */
  effects(): WorldVisualEffects | undefined;
  reduceMotion(): boolean;
  /** An ability is animating the body (jump arc, slam, teleport): leave it alone. */
  busy(): boolean;
}

/**
 * Event-driven squash and stretch on the slime (roadmap 9.2). Each event snaps
 * the body to its preset shape and springs back to rest; a new event replaces
 * the one playing, and the body always ends at scale 1.
 */
export class SquashStretch {
  private tween?: Phaser.Tweens.Tween;

  constructor(private readonly ctx: SquashStretchContext) {}

  /** `force` plays even while an ability is busy (the jump's own landing). */
  play(event: SquashEvent, force = false): void {
    const effects = this.ctx.effects();
    if (!effects || (!force && this.ctx.busy())) return;
    this.tween?.stop();
    const start = squashStart(SQUASH_PRESETS[event], this.ctx.reduceMotion());
    effects.scaleX = start.x;
    effects.scaleY = start.y;
    const rest = () => {
      effects.scaleX = 1;
      effects.scaleY = 1;
      this.tween = undefined;
    };
    this.tween = this.ctx.scene.tweens.add({
      targets: effects,
      scaleX: 1,
      scaleY: 1,
      duration: SQUASH_PRESETS[event].durationMs,
      ease: SQUASH_PRESETS[event].ease,
      onComplete: rest,
      onStop: rest,
    });
  }

  destroy(): void {
    this.tween?.stop();
    this.tween = undefined;
  }
}
