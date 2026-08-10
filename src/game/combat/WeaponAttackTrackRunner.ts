import type {
  NormalizedWeaponAnimationDocument,
  WeaponAttackTrackDocument,
  WeaponEventDocument,
} from '../content/weapons/types';
import {
  AnimationPlayer,
  type AnimationPlaybackContext,
} from '../shared/animation';

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

/** Drives weapon hitbox windows and events through the shared animation player. */
export class WeaponAttackTrackRunner {
  private readonly playbackClip: NormalizedWeaponAnimationDocument;
  private readonly active = new Map<string, ActiveSpan>();
  private readonly player: AnimationPlayer;
  private destroyed = false;

  constructor(
    clip: NormalizedWeaponAnimationDocument,
    private readonly track: WeaponAttackTrackDocument,
    private readonly callbacks: WeaponAttackTrackRunnerCallbacks = {},
  ) {
    // Combat attacks are always one-shot, even if malformed legacy data says loop.
    this.playbackClip = { ...clip, loop: false };
    this.player = new AnimationPlayer({
      onFrame: (_state, context) => this.applyPosition(context),
      onEvent: (event, context) => this.dispatchEvent(event, context),
      onComplete: () => {
        this.disableAll();
        this.callbacks.onComplete?.();
      },
      onDiagnostic: callbacks.onDiagnostic,
    });
  }

  get state(): WeaponAttackTrackRunnerState {
    const state = this.player.state;
    return {
      playbackId: state.playbackId,
      position: state.timelineFrame,
      elapsedMs: state.elapsedMs,
      paused: state.paused,
      activeHitboxes: new Set(this.active.keys()),
    };
  }

  start(forceRestart = true): void {
    if (this.destroyed || (!forceRestart && !this.player.state.paused)) return;
    this.disableAll();
    this.player.start(this.playbackClip, this.track.events ?? [], forceRestart);
  }

  cancel(): void {
    this.disableAll();
    this.player.stop();
  }

  pause(): void { this.player.pause(); }
  resume(): void { this.player.resume(); }
  update(deltaMs: number): void { this.player.update(deltaMs); }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.cancel();
    this.player.destroy();
  }

  private applyPosition(context: AnimationPlaybackContext): void {
    for (const [hitboxId, activeSpan] of this.active) {
      if (!this.track.hitboxSpans.some((span) => span.hitboxId === hitboxId && span.from <= context.timelineFrame && context.timelineFrame <= span.through)) {
        this.deactivate(activeSpan);
      }
    }
    for (const [index, span] of this.track.hitboxSpans.entries()) {
      if (span.from <= context.timelineFrame && context.timelineFrame <= span.through && !this.active.has(span.hitboxId)) {
        this.activate(span.hitboxId, index, context);
      }
    }
  }

  private activate(hitboxId: string, spanIndex: number, context: AnimationPlaybackContext): void {
    const state = this.player.state;
    const activationId = `${state.playbackId}:${context.cycle}:${hitboxId}:${spanIndex}`;
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

  private dispatchEvent(event: WeaponEventDocument, context: AnimationPlaybackContext): void {
    this.callbacks.onEvent?.({
      ...event,
      playbackId: this.player.state.playbackId,
      position: context.timelineFrame,
    });
  }
}
