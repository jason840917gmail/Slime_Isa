/**
 * Game feel (roadmap 9.1): named screen-shake and hit-stop presets per event,
 * so every shake in the game goes through one place that respects the player's
 * Screen shake slider and Reduce motion. Hit-stop freezes the simulation for a
 * few milliseconds (the world scene advances it by zero) while rendering, the
 * camera shake and particles keep going.
 *
 * Feel values are presentation, owned here rather than in game-constants.json.
 */

export type FeelEvent =
  | 'hit'
  | 'critical-hit'
  | 'combo-finisher'
  | 'player-hurt'
  | 'slam'
  | 'boss-landing'
  | 'boss-defeated'
  | 'player-defeated'
  | 'ground-crack'
  | 'building-restored';

export interface FeelPreset {
  readonly shakeMs: number;
  /** Phaser camera shake intensity at a full Screen shake slider. */
  readonly shakeIntensity: number;
  /** Simulation freeze; 0 for none. */
  readonly hitStopMs: number;
}

export const FEEL_PRESETS: Readonly<Record<FeelEvent, FeelPreset>> = Object.freeze({
  // Light hit: the weapon connects with a creature.
  hit: { shakeMs: 0, shakeIntensity: 0, hitStopMs: 35 },
  // Heavy hits.
  'critical-hit': { shakeMs: 80, shakeIntensity: 0.006, hitStopMs: 60 },
  'combo-finisher': { shakeMs: 120, shakeIntensity: 0.008, hitStopMs: 70 },
  slam: { shakeMs: 150, shakeIntensity: 0.01, hitStopMs: 60 },
  'player-hurt': { shakeMs: 110, shakeIntensity: 0.005, hitStopMs: 50 },
  // Boss slam (Fatty lands); the boss scene can author its own numbers.
  'boss-landing': { shakeMs: 100, shakeIntensity: 0.003, hitStopMs: 0 },
  // Defeats.
  'boss-defeated': { shakeMs: 450, shakeIntensity: 0.012, hitStopMs: 140 },
  'player-defeated': { shakeMs: 400, shakeIntensity: 0.012, hitStopMs: 120 },
  // World moments.
  'ground-crack': { shakeMs: 260, shakeIntensity: 0.012, hitStopMs: 0 },
  'building-restored': { shakeMs: 320, shakeIntensity: 0.006, hitStopMs: 0 },
});

export interface FeelSettings {
  /** 0–1 Screen shake slider, already 0 under Reduce motion. */
  readonly shakeScale: number;
  readonly reduceMotion: boolean;
}

/** What game feel needs from the running scene. */
export interface FeelStage {
  now(): number;
  shake(durationMs: number, intensity: number): void;
}

export class GameFeel {
  private stage?: FeelStage;
  private frozenUntil = 0;

  constructor(private readonly settings: () => FeelSettings) {}

  /** The world scene binds itself on create; returns the unbind for its cleanup. */
  bind(stage: FeelStage): () => void {
    this.stage = stage;
    this.frozenUntil = 0;
    return () => {
      if (this.stage !== stage) return;
      this.stage = undefined;
      this.frozenUntil = 0;
    };
  }

  /** Plays an event's preset; `shake` overrides its shake (a boss's authored landing). */
  play(event: FeelEvent, shake?: Readonly<{ durationMs: number; intensity: number }>): void {
    const preset = FEEL_PRESETS[event];
    this.shake(shake?.durationMs ?? preset.shakeMs, shake?.intensity ?? preset.shakeIntensity);
    this.hitStop(preset.hitStopMs);
  }

  /** A camera shake scaled by the Screen shake slider (none under Reduce motion). */
  shake(durationMs: number, intensity: number): void {
    const scale = this.settings().shakeScale;
    if (!this.stage || durationMs <= 0 || intensity <= 0 || scale <= 0) return;
    this.stage.shake(durationMs, intensity * scale);
  }

  /** Freezes the simulation for `ms` (none under Reduce motion); overlapping stops do not add up. */
  hitStop(ms: number): void {
    if (!this.stage || ms <= 0 || this.settings().reduceMotion) return;
    this.frozenUntil = Math.max(this.frozenUntil, this.stage.now() + ms);
  }

  /** True while a hit-stop holds the simulation still. */
  get frozen(): boolean {
    return !!this.stage && this.stage.now() < this.frozenUntil;
  }
}
