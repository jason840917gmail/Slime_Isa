import { AnimationClock } from './clock';
import { keyframeIndexAtTimelineFrame } from './timeline';
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

/** Single-layer compatibility adapter over the shared animation clock. */
export class AnimationPlayer {
  private clip?: NormalizedAnimationClipDocument;
  private readonly clock: AnimationClock;

  constructor(private readonly callbacks: AnimationPlayerCallbacks = {}) {
    this.clock = new AnimationClock({
      onEvent: callbacks.onEvent,
      onComplete: callbacks.onComplete,
      onDiagnostic: callbacks.onDiagnostic,
    });
    this.clock.subscribeFrame('visual', (state, context) => this.emitFrame(state.timelineFrame, context));
  }

  get state(): AnimationPlayerState {
    const clockState = this.clock.state;
    if (!this.clip) {
      return {
        timelineFrame: 0,
        keyframeIndex: 0,
        sourceFrame: 0,
        occurrenceIndex: 0,
        finished: false,
        playbackId: clockState.playbackId,
        loopIteration: clockState.loopIteration,
        paused: clockState.paused,
        elapsedMs: clockState.elapsedMs,
      };
    }
    const keyframeIndex = keyframeIndexAtTimelineFrame(this.clip, clockState.timelineFrame);
    return {
      timelineFrame: clockState.timelineFrame,
      keyframeIndex,
      sourceFrame: this.clip.frames[keyframeIndex],
      occurrenceIndex: keyframeIndex,
      finished: clockState.finished,
      clip: this.clip,
      playbackId: clockState.playbackId,
      loopIteration: clockState.loopIteration,
      paused: clockState.paused,
      elapsedMs: clockState.elapsedMs,
    };
  }

  start(clip: NormalizedAnimationClipDocument, events: readonly AnimationEventDocument[] = [], forceRestart = true): void {
    this.clip = clip;
    this.clock.start(clip, events, forceRestart);
  }

  stop(): void { this.clock.stop(); }
  pause(): void { this.clock.pause(); }
  resume(): void { this.clock.resume(); }
  scrub(position: number): void { this.clock.scrub(position); }
  update(deltaMs: number): void { this.clock.update(deltaMs); }

  destroy(): void {
    this.clock.destroy();
    this.clip = undefined;
  }

  private emitFrame(timelineFrame: number, context: AnimationPlaybackContext): void {
    if (!this.clip) return;
    const keyframeIndex = keyframeIndexAtTimelineFrame(this.clip, timelineFrame);
    this.callbacks.onFrame?.({
      timelineFrame,
      keyframeIndex,
      sourceFrame: this.clip.frames[keyframeIndex],
      occurrenceIndex: keyframeIndex,
      finished: false,
    }, context);
  }
}
