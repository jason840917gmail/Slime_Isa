import type Phaser from 'phaser';

import { resolveWorldDepth } from '../../presentation/WorldDepth';

export interface SlimeTrailOptions {
  /** Marks in the pool; the oldest is reused when all are out. */
  readonly poolSize: number;
  /** Distance the slime moves between two marks. */
  readonly spacing: number;
  /** A mark fades out over this time. */
  readonly lifetimeMs: number;
  /** A mark slows enemies while younger than this. */
  readonly freshMs: number;
}

export const SLIME_TRAIL_OPTIONS: SlimeTrailOptions = Object.freeze({
  poolSize: 28,
  spacing: 30,
  lifetimeMs: 5000,
  freshMs: 2500,
});

interface TrailMark {
  x: number;
  y: number;
  bornAt: number;
  live: boolean;
}

/**
 * Where the slime's goo marks are and how old (roadmap 9.4), with no
 * rendering: a fixed pool of marks reused oldest first, one dropped every
 * `spacing` pixels of movement.
 */
export class SlimeTrailModel {
  readonly marks: readonly TrailMark[];
  private next = 0;
  private last?: { x: number; y: number };

  constructor(readonly options: SlimeTrailOptions = SLIME_TRAIL_OPTIONS) {
    this.marks = Array.from({ length: options.poolSize }, () => ({ x: 0, y: 0, bornAt: 0, live: false }));
  }

  /**
   * Ages the marks and, given the slime's position, drops a new one once it has
   * moved `spacing` since the last; `at` undefined (mid-jump) only ages them.
   * Returns the index of a newly dropped mark, if any.
   */
  step(now: number, at?: Readonly<{ x: number; y: number }>): number | undefined {
    for (const mark of this.marks) if (mark.live && now - mark.bornAt >= this.options.lifetimeMs) mark.live = false;
    if (!at) {
      this.last = undefined;
      return undefined;
    }
    if (this.last && Math.hypot(at.x - this.last.x, at.y - this.last.y) < this.options.spacing) return undefined;
    this.last = { x: at.x, y: at.y };
    const index = this.next;
    this.next = (this.next + 1) % this.marks.length;
    const mark = this.marks[index]!;
    mark.x = at.x;
    mark.y = at.y;
    mark.bornAt = now;
    mark.live = true;
    return index;
  }

  /** Forget the last position (a teleport or map change should not draw a streak). */
  reset(): void {
    this.last = undefined;
  }

  /** 1 when fresh, fading to 0 at the end of its life. */
  opacity(mark: TrailMark, now: number): number {
    if (!mark.live) return 0;
    return Math.max(0, 1 - (now - mark.bornAt) / this.options.lifetimeMs);
  }

  /** Marks young enough to slow enemies. */
  freshPoints(now: number): { x: number; y: number }[] {
    return this.marks.filter((mark) => mark.live && now - mark.bornAt < this.options.freshMs).map((mark) => ({ x: mark.x, y: mark.y }));
  }
}

const MARK_ALPHA = 0.5;

/** Draws the trail model with one pooled image per mark (roadmap 9.4). */
export class SlimeTrail {
  readonly model: SlimeTrailModel;
  private readonly images: Phaser.GameObjects.Image[];

  constructor(scene: Phaser.Scene, texture = 'fx-goo-mark', options: SlimeTrailOptions = SLIME_TRAIL_OPTIONS) {
    this.model = new SlimeTrailModel(options);
    this.images = this.model.marks.map(() => scene.add.image(0, 0, texture).setVisible(false));
  }

  /** Call once per gameplay frame with the slime's feet position, or undefined while it is off the ground. */
  update(now: number, at?: Readonly<{ x: number; y: number }>): void {
    const dropped = this.model.step(now, at);
    if (dropped !== undefined && at) {
      const image = this.images[dropped]!;
      image.setPosition(at.x, at.y).setAngle(((dropped * 47) % 30) - 15).setVisible(true);
      // Ground decal: under everything that stands on it.
      image.setDepth(resolveWorldDepth(at.y, { band: 'ground-decals', stableId: `slime-trail-${dropped}` }).depth);
    }
    this.model.marks.forEach((mark, index) => {
      const image = this.images[index]!;
      if (!mark.live) { if (image.visible) image.setVisible(false); return; }
      image.setAlpha(MARK_ALPHA * this.model.opacity(mark, now));
    });
  }

  destroy(): void {
    for (const image of this.images) image.destroy();
  }
}
