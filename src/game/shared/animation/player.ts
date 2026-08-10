import { keyframeIndexAtTimelineFrame, timelineFrameCount } from './timeline';
import type {
  AnimationEventDocument,
  AnimationPlaybackContext,
  AnimationPlaybackState,
  NormalizedAnimationClipDocument,
} from './types';

export interface AnimationPlayerCallbacks {
  readonly onFrame?: (state: AnimationPlaybackState, context: AnimationPlaybackContext) => void;
  readonly onEvent?: (event: AnimationEventDocument, context: AnimationPlaybackContext) => void;
  readonly onComplete?: () => void;
  readonly onDiagnostic?: (message: string) => void;
}

export interface AnimationPlayerState extends AnimationPlaybackState {
  readonly clip?: NormalizedAnimationClipDocument;
  readonly playbackId: number;
  readonly loopIteration: number;
  readonly paused: boolean;
  readonly elapsedMs: number;
}

function cycleFrameCount(clip: NormalizedAnimationClipDocument): number {
  const frameCount = timelineFrameCount(clip);
  return clip.loop && clip.loopMode === 'ping-pong' && frameCount > 1
    ? frameCount * 2 - 2
    : frameCount;
}

function frameAtStep(clip: NormalizedAnimationClipDocument, step: number): number {
  const frameCount = timelineFrameCount(clip);
  if (frameCount <= 1) return 0;
  const cycleLength = cycleFrameCount(clip);
  const offset = Math.max(0, Math.floor(step)) % cycleLength;
  return clip.loop && clip.loopMode === 'ping-pong' && offset >= frameCount
    ? cycleLength - offset
    : offset;
}

function directionAtStep(clip: NormalizedAnimationClipDocument, step: number): 1 | -1 {
  if (clip.loop && clip.loopMode === 'ping-pong' && timelineFrameCount(clip) > 1) {
    const frameCount = timelineFrameCount(clip);
    const cycleLength = cycleFrameCount(clip);
    return Math.floor(step) % cycleLength >= frameCount ? -1 : 1;
  }
  return 1;
}

/** Shared timeline player. It knows timing; hosts decide what a frame means. */
export class AnimationPlayer {
  private clip?: NormalizedAnimationClipDocument;
  private events: readonly AnimationEventDocument[] = [];
  private elapsedMs = 0;
  private playbackId = 0;
  private loopIteration = 0;
  private position = 0;
  private absoluteStep = 0;
  private paused = true;
  private destroyed = false;

  constructor(private readonly callbacks: AnimationPlayerCallbacks = {}) {}

  get state(): AnimationPlayerState {
    if (!this.clip) {
      return {
        timelineFrame: 0,
        keyframeIndex: 0,
        sourceFrame: 0,
        occurrenceIndex: 0,
        finished: false,
        playbackId: this.playbackId,
        loopIteration: this.loopIteration,
        paused: this.paused,
        elapsedMs: this.elapsedMs,
      };
    }
    const keyframeIndex = keyframeIndexAtTimelineFrame(this.clip, this.position);
    return {
      timelineFrame: this.position,
      keyframeIndex,
      sourceFrame: this.clip.frames[keyframeIndex],
      occurrenceIndex: keyframeIndex,
      finished: !this.clip.loop && this.paused && this.absoluteStep >= timelineFrameCount(this.clip) - 1,
      clip: this.clip,
      playbackId: this.playbackId,
      loopIteration: this.loopIteration,
      paused: this.paused,
      elapsedMs: this.elapsedMs,
    };
  }

  start(clip: NormalizedAnimationClipDocument, events: readonly AnimationEventDocument[] = [], forceRestart = true): void {
    if (this.destroyed) return;
    if (!forceRestart && !this.paused && this.clip === clip) return;
    this.clip = clip;
    this.events = [...events].sort((left, right) => left.at - right.at);
    this.elapsedMs = 0;
    this.loopIteration = 0;
    this.position = 0;
    this.absoluteStep = 0;
    this.paused = false;
    this.playbackId += 1;
    this.emitFrame(null, 1, false);
    this.emitEventsAt(0, null, 1, false);
  }

  stop(): void {
    this.paused = true;
    this.position = 0;
    this.absoluteStep = 0;
    this.elapsedMs = 0;
  }

  pause(): void { this.paused = true; }
  resume(): void { if (this.clip && !this.destroyed) this.paused = false; }

  scrub(position: number): void {
    if (!this.clip || this.destroyed) return;
    const nextPosition = Math.max(0, Math.min(Math.floor(position), timelineFrameCount(this.clip) - 1));
    const previous = this.position;
    this.position = nextPosition;
    this.absoluteStep = nextPosition;
    this.emitFrame(previous, nextPosition >= previous ? 1 : -1, true);
  }

  update(deltaMs: number): void {
    if (this.destroyed || this.paused || !this.clip) return;
    const frameDurationMs = 1000 / this.clip.framesPerSecond;
    this.elapsedMs += Math.max(0, deltaMs);
    const targetStep = Math.floor(this.elapsedMs / frameDurationMs);
    const timelineFrames = timelineFrameCount(this.clip);
    if (!this.clip.loop && targetStep >= timelineFrames) {
      while (this.absoluteStep < timelineFrames - 1) {
        this.absoluteStep += 1;
        this.enterStep(this.absoluteStep);
      }
      this.paused = true;
      this.callbacks.onComplete?.();
      return;
    }
    const stepDelta = targetStep - this.absoluteStep;
    if (stepDelta > 10000) this.callbacks.onDiagnostic?.(`Advancing across ${stepDelta} animation steps`);
    while (this.absoluteStep < targetStep) {
      this.absoluteStep += 1;
      this.enterStep(this.absoluteStep);
    }
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.stop();
    this.clip = undefined;
    this.events = [];
  }

  private enterStep(step: number): void {
    if (!this.clip) return;
    const cycleLength = cycleFrameCount(this.clip);
    const nextLoop = Math.floor(step / cycleLength);
    if (nextLoop !== this.loopIteration) this.loopIteration = nextLoop;
    const nextPosition = frameAtStep(this.clip, step);
    const direction = directionAtStep(this.clip, step);
    const previous = this.position;
    this.position = nextPosition;
    this.emitFrame(previous, direction, false);
    this.emitEventsAt(nextPosition, previous, direction, false);
  }

  private emitFrame(previousTimelineFrame: number | null, direction: 1 | -1, isScrub: boolean): void {
    if (!this.clip) return;
    const keyframeIndex = keyframeIndexAtTimelineFrame(this.clip, this.position);
    const context: AnimationPlaybackContext = {
      previousTimelineFrame,
      timelineFrame: this.position,
      direction,
      cycle: this.loopIteration,
      isScrub,
    };
    this.callbacks.onFrame?.({
      timelineFrame: this.position,
      keyframeIndex,
      sourceFrame: this.clip.frames[keyframeIndex],
      occurrenceIndex: keyframeIndex,
      finished: false,
    }, context);
  }

  private emitEventsAt(position: number, previousTimelineFrame: number | null, direction: 1 | -1, isScrub: boolean): void {
    if (isScrub) return;
    const context: AnimationPlaybackContext = {
      previousTimelineFrame,
      timelineFrame: position,
      direction,
      cycle: this.loopIteration,
      isScrub,
    };
    for (const event of this.events) {
      if (event.at === position) this.callbacks.onEvent?.(event, context);
    }
  }
}
