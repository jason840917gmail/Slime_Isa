import type { WeaponAttackTrackDocument, WeaponEventDocument } from '../content/weapons/types';
import { AnimationClock, type AnimationPlaybackContext } from '../shared/animation';

export interface WeaponTrackEvent extends WeaponEventDocument { readonly playbackId: number; readonly position: number }
export interface WeaponAttackTrackRunnerCallbacks {
  readonly onHitboxActivated?: (hitboxId: string, activationId: string) => void;
  readonly onHitboxDeactivated?: (hitboxId: string, activationId: string) => void;
}
export interface WeaponAttackTrackRunnerState {
  readonly playbackId: number; readonly position: number; readonly elapsedMs: number; readonly paused: boolean; readonly activeHitboxes: ReadonlySet<string>;
}
interface ActiveSpan { readonly hitboxId: string; readonly spanIndex: number; readonly activationId: string }

/** Hitbox-span consumer of a weapon-owned animation clock. */
export class WeaponAttackTrackRunner {
  private readonly active = new Map<string, ActiveSpan>();
  private readonly unsubscribe: () => void;
  private destroyed = false;
  constructor(private readonly clock: AnimationClock, private readonly track: WeaponAttackTrackDocument, private readonly callbacks: WeaponAttackTrackRunnerCallbacks = {}) {
    this.unsubscribe = clock.subscribeFrame('track', (_state, context) => this.applyPosition(context));
  }
  get state(): WeaponAttackTrackRunnerState { const state = this.clock.state; return { playbackId: state.playbackId, position: state.timelineFrame, elapsedMs: state.elapsedMs, paused: state.paused, activeHitboxes: new Set(this.active.keys()) }; }
  cancel(): void { this.disableAll(); }
  destroy(): void { if (this.destroyed) return; this.destroyed = true; this.disableAll(); this.unsubscribe(); }
  private applyPosition(context: AnimationPlaybackContext): void {
    for (const [hitboxId, active] of this.active) if (!this.track.hitboxSpans.some((span) => span.hitboxId === hitboxId && span.from <= context.timelineFrame && context.timelineFrame <= span.through)) this.deactivate(active);
    for (const [index, span] of this.track.hitboxSpans.entries()) if (span.from <= context.timelineFrame && context.timelineFrame <= span.through && !this.active.has(span.hitboxId)) this.activate(span.hitboxId, index, context);
  }
  private activate(hitboxId: string, spanIndex: number, context: AnimationPlaybackContext): void { const activationId = `${this.clock.state.playbackId}:${context.cycle}:${hitboxId}:${spanIndex}`; const active = { hitboxId, spanIndex, activationId }; this.active.set(hitboxId, active); this.callbacks.onHitboxActivated?.(hitboxId, activationId); }
  private deactivate(active: ActiveSpan): void { this.active.delete(active.hitboxId); this.callbacks.onHitboxDeactivated?.(active.hitboxId, active.activationId); }
  private disableAll(): void { for (const active of [...this.active.values()]) this.deactivate(active); this.active.clear(); }
}
