import type {
  CharacterDocument,
  CharacterEventDocument,
  HitboxSpanDocument,
  VisualSetDocument,
} from '../../content/characters/types';
import {
  AnimationPlayer,
  normalizeAnimationClip,
  type AnimationPlaybackContext,
} from '../../shared/animation';

export interface CharacterTrackEvent {
  readonly characterId: string;
  readonly clipId: string;
  readonly playbackId: number;
  readonly loopIteration: number;
  readonly position: number;
  readonly eventId: string;
  readonly payload?: CharacterEventDocument['payload'];
}

export interface CharacterTrackRunnerCallbacks {
  readonly onHitboxActivated?: (hitboxId: string, activationId: string) => void;
  readonly onHitboxDeactivated?: (hitboxId: string, activationId: string) => void;
  readonly onEvent?: (event: CharacterTrackEvent) => void;
  readonly onComplete?: () => void;
  readonly onDiagnostic?: (message: string) => void;
}

export interface CharacterTrackRunnerState {
  readonly clipId?: string;
  readonly playbackId: number;
  readonly loopIteration: number;
  readonly position: number;
  readonly paused: boolean;
  readonly activeHitboxes: ReadonlySet<string>;
}

interface ActiveSpan {
  readonly hitboxId: string;
  readonly spanIndex: number;
  readonly activationId: string;
}

function spansAt(spans: readonly HitboxSpanDocument[], position: number): Array<{ span: HitboxSpanDocument; index: number }> {
  return spans.map((span, index) => ({ span, index })).filter(({ span }) => span.from <= position && position <= span.through);
}

export class CharacterAnimationTrackRunner {
  private clipId?: string;
  private destroyed = false;
  private active = new Map<string, ActiveSpan>();
  private readonly player: AnimationPlayer;

  constructor(
    private readonly character: CharacterDocument,
    private readonly visualSet: VisualSetDocument,
    private readonly callbacks: CharacterTrackRunnerCallbacks = {},
  ) {
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

  get state(): CharacterTrackRunnerState {
    const state = this.player.state;
    return {
      clipId: this.clipId,
      playbackId: state.playbackId,
      loopIteration: state.loopIteration,
      position: state.timelineFrame,
      paused: state.paused,
      activeHitboxes: new Set(this.active.keys()),
    };
  }

  start(clipId: string, forceRestart = true): void {
    if (this.destroyed) return;
    if (!forceRestart && !this.player.state.paused) return;
    const sourceClip = this.visualSet.clips[clipId];
    if (!sourceClip) throw new Error(`Unknown clip '${clipId}'`);
    this.disableAll();
    this.clipId = clipId;
    const clip = normalizeAnimationClip(sourceClip);
    this.player.start(clip, this.character.animationTracks[clipId]?.events ?? [], forceRestart);
  }

  stop(): void {
    this.disableAll();
    this.player.stop();
    this.clipId = undefined;
  }

  cancel(): void { this.stop(); }
  pause(): void { this.player.pause(); }
  resume(): void { this.player.resume(); }
  scrub(position: number): void { this.player.scrub(position); }
  update(deltaMs: number): void { this.player.update(deltaMs); }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.disableAll();
    this.player.destroy();
  }

  private get trackSpans(): readonly HitboxSpanDocument[] {
    return this.clipId ? this.character.animationTracks[this.clipId]?.hitboxSpans ?? [] : [];
  }

  private applyPosition(context: AnimationPlaybackContext): void {
    if (context.isScrub) this.disableAll();
    const spans = this.trackSpans;
    for (const [hitboxId, activeSpan] of this.active) {
      if (!spans.some((span) => span.hitboxId === hitboxId && span.from <= context.timelineFrame && context.timelineFrame <= span.through)) {
        this.deactivate(activeSpan);
      }
    }
    for (const { span, index } of spansAt(spans, context.timelineFrame)) {
      if (!this.active.has(span.hitboxId)) this.activate(span, index, context);
    }
  }

  private activate(span: HitboxSpanDocument, spanIndex: number, context: AnimationPlaybackContext): void {
    const state = this.player.state;
    const activationId = `${state.playbackId}:${context.cycle}:${this.clipId ?? ''}:${span.hitboxId}:${spanIndex}`;
    const activeSpan = { hitboxId: span.hitboxId, spanIndex, activationId };
    this.active.set(span.hitboxId, activeSpan);
    this.callbacks.onHitboxActivated?.(span.hitboxId, activationId);
  }

  private deactivate(activeSpan: ActiveSpan): void {
    this.active.delete(activeSpan.hitboxId);
    this.callbacks.onHitboxDeactivated?.(activeSpan.hitboxId, activeSpan.activationId);
  }

  private disableAll(): void {
    for (const activeSpan of this.active.values()) this.callbacks.onHitboxDeactivated?.(activeSpan.hitboxId, activeSpan.activationId);
    this.active.clear();
  }

  private dispatchEvent(event: { at: number; eventId: string; payload?: unknown }, context: AnimationPlaybackContext): void {
    if (!this.clipId) return;
    this.callbacks.onEvent?.({
      characterId: this.character.characterId,
      clipId: this.clipId,
      playbackId: this.player.state.playbackId,
      loopIteration: context.cycle,
      position: context.timelineFrame,
      eventId: event.eventId,
      payload: event.payload as CharacterEventDocument['payload'],
    });
  }
}
