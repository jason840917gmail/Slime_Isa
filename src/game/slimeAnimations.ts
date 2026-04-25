/**
 * Slime sprite-sheet animation map.
 *
 * Sheet layout: 8 columns × 8 rows, 256 × 256 px per cell.
 * Frame index = row * 8 + column  (0-based).
 *
 * Row 0  (frames  0– 7)  – Idle / expressions
 * Row 1  (frames  8–15)  – Walk / scoot (side motion)
 * Row 2  (frames 16–23)  – Hop (upward)
 * Row 3  (frames 24–31)  – Squash / landing impact
 * Row 4  (frames 32–39)  – Stretch (vertical)
 * Row 5  (frames 40–47)  – Roll (ball form, boost)
 * Row 6  (frames 48–55)  – Attack / hit (trick)
 * Row 7  (frames 56–63)  – Special (teleport / drip)
 */

export interface AnimClip {
  /** Phaser animation key, also used in play() calls */
  key: string;
  /** Frame indices from the sprite-sheet */
  frames: number[];
  /** Playback rate in frames per second */
  frameRate: number;
  /** -1 = loop, 0 = play once */
  repeat: number;
}

export const SLIME_ANIMS: Readonly<AnimClip[]> = [
  // ── Idle ───────────────────────────────────────────────────────────
  {
    key: 'slime-idle',
    frames: [0, 1, 2, 1, 4, 5, 4, 2],
    frameRate: 6,
    repeat: -1,
  },

  // ── Walk / scoot (flip sprite for left) ────────────────────────────
  {
    key: 'slime-walk',
    frames: [9, 10, 11, 12, 13, 14, 15, 14, 13, 12],
    frameRate: 10,
    repeat: -1,
  },

  // ── Hop (up / down vertical movement) ──────────────────────────────
  {
    key: 'slime-hop',
    frames: [17, 18, 19, 20, 21, 22, 23, 22, 21],
    frameRate: 11,
    repeat: -1,
  },

  // ── Squash (landing / down impact) ─────────────────────────────────
  {
    key: 'slime-squash',
    frames: [24, 25, 26, 27, 28, 29, 30, 31],
    frameRate: 12,
    repeat: -1,
  },

  // ── Stretch (upward dash) ───────────────────────────────────────────
  {
    key: 'slime-stretch',
    frames: [32, 33, 34, 35, 36, 37, 38, 39],
    frameRate: 12,
    repeat: -1,
  },

  // ── Roll (boost / ball form) ────────────────────────────────────────
  {
    key: 'slime-roll',
    frames: [ 43,44],
    frameRate: 14,
    repeat: -1,
  },

  // ── Trick / attack (play-once) ──────────────────────────────────────
  {
    key: 'slime-trick',
    frames: [48, 49, 50, 51, 52, 53, 52, 51],
    frameRate: 10,
    repeat: 0,
  },

  // ── Teleport / special (play-once) ─────────────────────────────────
  {
    key: 'slime-teleport',
    frames: [56, 57, 58, 59, 60, 61, 60, 59],
    frameRate: 12,
    repeat: 0,
  },
] as const;

// Quick lookup by key
export const SLIME_ANIM_MAP: Readonly<Record<string, AnimClip>> = Object.fromEntries(
  SLIME_ANIMS.map((clip) => [clip.key, clip]),
);
