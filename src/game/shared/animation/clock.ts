import type {
  AnimationEventDocument,
  AnimationLoopMode,
  AnimationPlaybackContext,
} from './types';

export interface AnimationClockDocument {
  readonly durationSeconds: number;
  readonly framesPerSecond: number;
  readonly loop: boolean;
  readonly loopMode?: AnimationLoopMode;
}

export interface AnimationClockFrameState {
  readonly timelineFrame: number;
  readonly playbackId: number;
  readonly loopIteration: number;
}

export interface AnimationClockState extends AnimationClockFrameState {
  readonly timeline?: AnimationClockDocument;
  readonly paused: boolean;
  readonly elapsedMs: number;
  readonly finished: boolean;
}

export type AnimationClockFramePhase = 'visual' | 'track';
export type AnimationClockFrameSubscriber = (
  state: AnimationClockFrameState,
  context: AnimationPlaybackContext,
) => void;

export interface AnimationClockCallbacks {
  readonly onEvent?: (event: AnimationEventDocument, context: AnimationPlaybackContext) => void;
  readonly onComplete?: () => void;
  readonly onDiagnostic?: (message: string) => void;
}

function timelineFrameCount(timeline: AnimationClockDocument): number {
  return Math.max(1, Math.round(timeline.durationSeconds * timeline.framesPerSecond));
}

function cycleFrameCount(timeline: AnimationClockDocument): number {
  const frameCount = timelineFrameCount(timeline);
  return timeline.loop && timeline.loopMode === 'ping-pong' && frameCount > 1
    ? frameCount * 2 - 2
    : frameCount;
}

function frameAtStep(timeline: AnimationClockDocument, step: number): number {
  const frameCount = timelineFrameCount(timeline);
  if (frameCount <= 1) return 0;
  const cycleLength = cycleFrameCount(timeline);
  const offset = Math.max(0, Math.floor(step)) % cycleLength;
  return timeline.loop && timeline.loopMode === 'ping-pong' && offset >= frameCount
    ? cycleLength - offset
    : offset;
}

function directionAtStep(timeline: AnimationClockDocument, step: number): 1 | -1 {
  if (timeline.loop && timeline.loopMode === 'ping-pong' && timelineFrameCount(timeline) > 1) {
    const frameCount = timelineFrameCount(timeline);
    const cycleLength = cycleFrameCount(timeline);
    return Math.floor(step) % cycleLength >= frameCount ? -1 : 1;
  }
  return 1;
}

/** One timeline owner with deterministic visual, track, event, and completion dispatch. */
export class AnimationClock {
  private timeline?: AnimationClockDocument;
  private events: readonly AnimationEventDocument[] = [];
  private readonly visualSubscribers = new Set<AnimationClockFrameSubscriber>();
  private readonly trackSubscribers = new Set<AnimationClockFrameSubscriber>();
  private elapsedMs = 0;
  private playbackId = 0;
  private loopIteration = 0;
  private position = 0;
  private absoluteStep = 0;
  private paused = true;
  private destroyed = false;

  constructor(private readonly callbacks: AnimationClockCallbacks = {}) {}

  get state(): AnimationClockState {
    const frameCount = this.timeline ? timelineFrameCount(this.timeline) : 1;
    return {
      timelineFrame: this.position,
      playbackId: this.playbackId,
      loopIteration: this.loopIteration,
      timeline: this.timeline,
      paused: this.paused,
      elapsedMs: this.elapsedMs,
      finished: Boolean(this.timeline && !this.timeline.loop && this.paused && this.absoluteStep >= frameCount - 1),
    };
  }

  subscribeFrame(phase: AnimationClockFramePhase, subscriber: AnimationClockFrameSubscriber): () => void {
    const subscribers = phase === 'visual' ? this.visualSubscribers : this.trackSubscribers;
    subscribers.add(subscriber);
    return () => subscribers.delete(subscriber);
  }

  start(
    timeline: AnimationClockDocument,
    events: readonly AnimationEventDocument[] = [],
    forceRestart = true,
  ): void {
    if (this.destroyed) return;
    if (!forceRestart && !this.paused && this.timeline === timeline) return;
    this.timeline = timeline;
    this.events = [...events].sort((left, right) => left.at - right.at);
    this.elapsedMs = 0;
    this.loopIteration = 0;
    this.position = 0;
    this.absoluteStep = 0;
    this.paused = false;
    this.playbackId += 1;
    this.dispatchFrame(null, 1, false);
    this.dispatchEvents(0, null, 1, false);
  }

  stop(): void {
    this.paused = true;
    this.position = 0;
    this.absoluteStep = 0;
    this.elapsedMs = 0;
  }

  pause(): void { this.paused = true; }

  resume(): void {
    if (this.timeline && !this.destroyed) this.paused = false;
  }

  scrub(position: number): void {
    if (!this.timeline || this.destroyed) return;
    const nextPosition = Math.max(0, Math.min(Math.floor(position), timelineFrameCount(this.timeline) - 1));
    const previous = this.position;
    this.position = nextPosition;
    this.absoluteStep = nextPosition;
    this.dispatchFrame(previous, nextPosition >= previous ? 1 : -1, true);
  }

  update(deltaMs: number): void {
    if (this.destroyed || this.paused || !this.timeline) return;
    const frameDurationMs = 1000 / this.timeline.framesPerSecond;
    this.elapsedMs += Math.max(0, deltaMs);
    const targetStep = Math.floor(this.elapsedMs / frameDurationMs);
    const frameCount = timelineFrameCount(this.timeline);
    if (!this.timeline.loop && targetStep >= frameCount) {
      while (this.absoluteStep < frameCount - 1) {
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
    this.timeline = undefined;
    this.events = [];
    this.visualSubscribers.clear();
    this.trackSubscribers.clear();
  }

  private enterStep(step: number): void {
    if (!this.timeline) return;
    const cycleLength = cycleFrameCount(this.timeline);
    const nextLoop = Math.floor(step / cycleLength);
    if (nextLoop !== this.loopIteration) this.loopIteration = nextLoop;
    const nextPosition = frameAtStep(this.timeline, step);
    const direction = directionAtStep(this.timeline, step);
    const previous = this.position;
    this.position = nextPosition;
    this.dispatchFrame(previous, direction, false);
    this.dispatchEvents(nextPosition, previous, direction, false);
  }

  private dispatchFrame(
    previousTimelineFrame: number | null,
    direction: 1 | -1,
    isScrub: boolean,
  ): void {
    const context: AnimationPlaybackContext = {
      previousTimelineFrame,
      timelineFrame: this.position,
      direction,
      cycle: this.loopIteration,
      isScrub,
    };
    const state: AnimationClockFrameState = {
      timelineFrame: this.position,
      playbackId: this.playbackId,
      loopIteration: this.loopIteration,
    };
    for (const subscriber of this.visualSubscribers) subscriber(state, context);
    for (const subscriber of this.trackSubscribers) subscriber(state, context);
  }

  private dispatchEvents(
    position: number,
    previousTimelineFrame: number | null,
    direction: 1 | -1,
    isScrub: boolean,
  ): void {
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
