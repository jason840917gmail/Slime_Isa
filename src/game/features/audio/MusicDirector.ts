/** A looping music node the director fades in and out. */
export interface MusicTrack {
  readonly playing: boolean;
  play(): void;
  stop(): void;
  /** Runtime fade multiplier on top of the authored volume, 0..1. */
  setGain(gain: number): void;
}

export interface MusicDirectorContext {
  /** The world's own music (a looping `MusicPlayer` in the world scene), if it has one. */
  readonly world?: MusicTrack;
  /** Music for boss fights (`Music/BossMusic` in `audio.global`), if authored. */
  readonly boss?: MusicTrack;
  /** Fades wait until the browser lets audio play, so a locked page never "finishes" a fade silently. */
  isAudioUnlocked(): boolean;
  /** Lowers the music bus while a menu pauses the game (1 = full volume). */
  setMusicDuck(factor: number): void;
}

/** World music rises this slowly after arriving in an area. */
export const MUSIC_FADE_IN_MS = 1500;
/** World and boss music swap over this long. */
export const MUSIC_CROSSFADE_MS = 1200;
/** Music level under a pause menu. */
export const MUSIC_PAUSE_DUCK = 0.35;
export const MUSIC_DUCK_MS = 250;

/**
 * Keeps music transitions smooth: world music fades in on arrival, crossfades
 * to boss music while a boss fight lasts and back afterwards, dips while the
 * game is paused, and fades out before the player leaves the area (a map
 * change reloads the page). Tracks never start at full volume or stop mid-note.
 */
export class MusicDirector {
  private worldGain = 0;
  private bossGain = 0;
  private duck = 1;
  private bossFight = false;
  private paused = false;
  private leavingMs?: number;

  constructor(private readonly ctx: MusicDirectorContext) {
    ctx.world?.setGain(0);
    ctx.boss?.setGain(0);
  }

  setBossFight(active: boolean): void {
    this.bossFight = active;
    if (active && this.ctx.boss && !this.ctx.boss.playing) this.ctx.boss.play();
  }

  setPaused(paused: boolean): void {
    this.paused = paused;
  }

  /** Fades every track out over `durationMs` (before leaving the area). */
  fadeOut(durationMs: number): void {
    this.leavingMs = Math.max(1, durationMs);
  }

  update(deltaMs: number): void {
    const step = Math.max(0, deltaMs);
    const duckTarget = this.paused ? MUSIC_PAUSE_DUCK : 1;
    this.duck = approach(this.duck, duckTarget, step / MUSIC_DUCK_MS * (1 - MUSIC_PAUSE_DUCK));
    this.ctx.setMusicDuck(this.duck);
    if (!this.ctx.isAudioUnlocked()) return;

    const bossActive = this.bossFight && this.ctx.boss !== undefined;
    const leaving = this.leavingMs !== undefined;
    const worldTarget = leaving || bossActive ? 0 : 1;
    const bossTarget = !leaving && bossActive ? 1 : 0;
    const worldDuration = leaving ? this.leavingMs! : bossActive || this.bossGain > 0 ? MUSIC_CROSSFADE_MS : MUSIC_FADE_IN_MS;
    const bossDuration = leaving ? this.leavingMs! : MUSIC_CROSSFADE_MS;
    this.worldGain = approach(this.worldGain, worldTarget, step / worldDuration);
    this.bossGain = approach(this.bossGain, bossTarget, step / bossDuration);
    this.ctx.world?.setGain(this.worldGain);
    this.ctx.boss?.setGain(this.bossGain);
    // A finished boss track stops at silence so the next fight starts from the top.
    if (this.bossGain === 0 && !bossActive && this.ctx.boss?.playing) this.ctx.boss.stop();
  }
}

function approach(value: number, target: number, maxStep: number): number {
  if (value < target) return Math.min(target, value + maxStep);
  if (value > target) return Math.max(target, value - maxStep);
  return value;
}
