import type {
  CharacterDocument,
  CharacterEventDocument,
  HitboxSpanDocument,
  VisualSetDocument,
} from '../../content/characters/types';
import { animationCycleFrameCount, animationFrameIndexAtStep } from '../../shared/animationLoop';

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
  private elapsedMs = 0;
  private playbackId = 0;
  private loopIteration = 0;
  private position = -1;
  private absoluteStep = 0;
  private paused = false;
  private destroyed = false;
  private active = new Map<string, ActiveSpan>();

  constructor(
    private readonly character: CharacterDocument,
    private readonly visualSet: VisualSetDocument,
    private readonly callbacks: CharacterTrackRunnerCallbacks = {},
  ) {}

  get state(): CharacterTrackRunnerState {
    return {
      clipId: this.clipId,
      playbackId: this.playbackId,
      loopIteration: this.loopIteration,
      position: Math.max(0, this.position),
      paused: this.paused,
      activeHitboxes: new Set(this.active.keys()),
    };
  }

  start(clipId: string, forceRestart = true): void {
    if (this.destroyed) return;
    if (!forceRestart && this.clipId === clipId) return;
    if (!this.visualSet.clips[clipId]) throw new Error(`Unknown clip '${clipId}'`);
    this.disableAll();
    this.clipId = clipId;
    this.elapsedMs = 0;
    this.loopIteration = 0;
    this.position = -1;
    this.absoluteStep = 0;
    this.paused = false;
    this.playbackId += 1;
    this.enterPosition(0, true);
  }

  stop(): void {
    this.disableAll();
    this.clipId = undefined;
    this.position = -1;
    this.elapsedMs = 0;
    this.absoluteStep = 0;
  }

  cancel(): void { this.stop(); }
  pause(): void { this.paused = true; }
  resume(): void { this.paused = false; }

  scrub(position: number): void {
    const clip = this.clipId ? this.visualSet.clips[this.clipId] : undefined;
    if (!clip) return;
    const nextPosition = Math.max(0, Math.min(Math.floor(position), clip.frames.length - 1));
    this.disableAll();
    this.position = nextPosition;
    this.absoluteStep = nextPosition;
    for (const { span, index } of spansAt(this.trackSpans, nextPosition)) this.activate(span, index);
  }

  update(deltaMs: number): void {
    if (this.destroyed || this.paused || !this.clipId) return;
    const clip = this.visualSet.clips[this.clipId];
    const durationMs = 1000 / clip.framesPerSecond;
    this.elapsedMs += Math.max(0, deltaMs);
    const targetStep = Math.floor(this.elapsedMs / durationMs);
    const cycleLength = animationCycleFrameCount(clip);
    const targetLoop = Math.floor(targetStep / cycleLength);
    const targetPosition = animationFrameIndexAtStep(clip, targetStep);
    if (!clip.loop && targetStep >= clip.frames.length) {
      this.disableAll();
      this.position = clip.frames.length - 1;
      this.absoluteStep = clip.frames.length;
      this.callbacks.onComplete?.();
      this.paused = true;
      return;
    }
    if (targetLoop - this.loopIteration > 4) {
      this.callbacks.onDiagnostic?.(`Skipped ${targetLoop - this.loopIteration} animation loops for '${this.clipId}'`);
      this.disableAll();
      this.loopIteration = targetLoop;
      this.position = targetPosition;
      this.absoluteStep = targetStep;
      for (const { span, index } of spansAt(this.trackSpans, targetPosition)) this.activate(span, index);
      return;
    }
    while (this.absoluteStep < targetStep) {
      this.absoluteStep += 1;
      const nextLoop = Math.floor(this.absoluteStep / cycleLength);
      if (nextLoop !== this.loopIteration) {
        this.disableAll();
        this.loopIteration = nextLoop;
        this.position = -1;
      }
      this.enterPosition(animationFrameIndexAtStep(clip, this.absoluteStep), false);
    }
  }

  destroy(): void { if (this.destroyed) return; this.destroyed = true; this.disableAll(); }

  private get trackSpans(): readonly HitboxSpanDocument[] {
    return this.clipId ? this.character.animationTracks[this.clipId]?.hitboxSpans ?? [] : [];
  }

  private enterPosition(position: number, initial: boolean): void {
    const spans = this.trackSpans;
    for (const [hitboxId, activeSpan] of this.active) {
      if (!spans.some((span) => span.hitboxId === hitboxId && span.from <= position && position <= span.through)) {
        this.deactivate(activeSpan);
      }
    }
    for (const { span, index } of spansAt(spans, position)) {
      if (!this.active.has(span.hitboxId)) this.activate(span, index);
    }
    this.position = position;
    if (initial || position >= 0) this.dispatchEvents(position);
  }

  private activate(span: HitboxSpanDocument, spanIndex: number): void {
    const activationId = `${this.playbackId}:${this.loopIteration}:${this.clipId ?? ''}:${span.hitboxId}:${spanIndex}`;
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

  private dispatchEvents(position: number): void {
    if (!this.clipId) return;
    for (const event of this.character.animationTracks[this.clipId]?.events ?? []) {
      if (event.at !== position) continue;
      this.callbacks.onEvent?.({
        characterId: this.character.characterId,
        clipId: this.clipId,
        playbackId: this.playbackId,
        loopIteration: this.loopIteration,
        position,
        eventId: event.eventId,
        payload: event.payload,
      });
    }
  }
}
