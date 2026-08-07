import type {
  WeaponAnimationDocument,
  WeaponAttackTrackDocument,
  WeaponEventDocument,
} from '../content/weapons/types';

export interface WeaponTrackEvent extends WeaponEventDocument {
  readonly playbackId: number;
  readonly position: number;
}

export interface WeaponAttackTrackRunnerCallbacks {
  readonly onHitboxActivated?: (hitboxId: string, activationId: string) => void;
  readonly onHitboxDeactivated?: (hitboxId: string, activationId: string) => void;
  readonly onEvent?: (event: WeaponTrackEvent) => void;
  readonly onComplete?: () => void;
  readonly onDiagnostic?: (message: string) => void;
}

export interface WeaponAttackTrackRunnerState {
  readonly playbackId: number;
  readonly position: number;
  readonly elapsedMs: number;
  readonly paused: boolean;
  readonly activeHitboxes: ReadonlySet<string>;
}

interface ActiveSpan {
  readonly hitboxId: string;
  readonly spanIndex: number;
  readonly activationId: string;
}

function spansAt(track: WeaponAttackTrackDocument, position: number): Array<{ span: WeaponAttackTrackDocument['hitboxSpans'][number]; index: number }> {
  return track.hitboxSpans
    .map((span, index) => ({ span, index }))
    .filter(({ span }) => span.from <= position && position <= span.through);
}

/** Drives weapon hitbox windows and events from an authored attack clip. */
export class WeaponAttackTrackRunner {
  private elapsedMs = 0;
  private playbackId = 0;
  private position = -1;
  private absoluteStep = 0;
  private paused = true;
  private destroyed = false;
  private active = new Map<string, ActiveSpan>();

  constructor(
    private readonly clip: WeaponAnimationDocument,
    private readonly track: WeaponAttackTrackDocument,
    private readonly callbacks: WeaponAttackTrackRunnerCallbacks = {},
  ) {}

  get state(): WeaponAttackTrackRunnerState {
    return {
      playbackId: this.playbackId,
      position: Math.max(0, this.position),
      elapsedMs: this.elapsedMs,
      paused: this.paused,
      activeHitboxes: new Set(this.active.keys()),
    };
  }

  start(forceRestart = true): void {
    if (this.destroyed || (!forceRestart && !this.paused)) return;
    this.disableAll();
    this.elapsedMs = 0;
    this.position = -1;
    this.absoluteStep = 0;
    this.paused = false;
    this.playbackId += 1;
    this.enterPosition(0);
  }

  cancel(): void {
    this.disableAll();
    this.paused = true;
    this.position = -1;
    this.elapsedMs = 0;
    this.absoluteStep = 0;
  }

  pause(): void { this.paused = true; }
  resume(): void { this.paused = false; }

  update(deltaMs: number): void {
    if (this.destroyed || this.paused) return;
    const frameDurationMs = 1000 / Math.max(1, this.clip.framesPerSecond);
    this.elapsedMs += Math.max(0, deltaMs);
    const targetStep = Math.floor(this.elapsedMs / frameDurationMs);
    if (targetStep >= this.clip.frames.length) {
      while (this.absoluteStep < this.clip.frames.length - 1) {
        this.absoluteStep += 1;
        this.enterPosition(this.absoluteStep);
      }
      this.disableAll();
      this.position = Math.max(0, this.clip.frames.length - 1);
      this.paused = true;
      this.callbacks.onComplete?.();
      return;
    }

    while (this.absoluteStep < targetStep) {
      this.absoluteStep += 1;
      this.enterPosition(this.absoluteStep);
    }
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.cancel();
  }

  private enterPosition(position: number): void {
    for (const [hitboxId, activeSpan] of this.active) {
      if (!this.track.hitboxSpans.some((span) => span.hitboxId === hitboxId && span.from <= position && position <= span.through)) {
        this.deactivate(activeSpan);
      }
    }
    for (const { span, index } of spansAt(this.track, position)) {
      if (!this.active.has(span.hitboxId)) {
        this.activate(span.hitboxId, index);
      }
    }
    this.position = position;
    for (const event of this.track.events ?? []) {
      if (event.at !== position) continue;
      this.callbacks.onEvent?.({ ...event, playbackId: this.playbackId, position });
    }
  }

  private activate(hitboxId: string, spanIndex: number): void {
    const activationId = `${this.playbackId}:${hitboxId}:${spanIndex}`;
    const activeSpan = { hitboxId, spanIndex, activationId };
    this.active.set(hitboxId, activeSpan);
    this.callbacks.onHitboxActivated?.(hitboxId, activationId);
  }

  private deactivate(activeSpan: ActiveSpan): void {
    this.active.delete(activeSpan.hitboxId);
    this.callbacks.onHitboxDeactivated?.(activeSpan.hitboxId, activeSpan.activationId);
  }

  private disableAll(): void {
    for (const activeSpan of this.active.values()) this.deactivate(activeSpan);
    this.active.clear();
  }
}
