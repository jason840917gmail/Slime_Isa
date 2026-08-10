export type AnimationLoopMode = 'wrap' | 'ping-pong';

export type AnimationJsonValue =
  | null
  | boolean
  | number
  | string
  | AnimationJsonValue[]
  | { [key: string]: AnimationJsonValue };

/** Shared authored animation contract. Frame references stay local to the owning asset package. */
export interface AnimationClipDocument {
  readonly frames: readonly number[];
  readonly keyframeTimes?: readonly number[];
  readonly durationSeconds?: number;
  readonly framesPerSecond: number;
  readonly loop: boolean;
  readonly loopMode?: AnimationLoopMode;
}

export interface NormalizedAnimationClipDocument extends AnimationClipDocument {
  readonly keyframeTimes: readonly number[];
  readonly durationSeconds: number;
}

export interface AnimationEventDocument {
  readonly at: number;
  readonly eventId: string;
  readonly payload?: AnimationJsonValue;
}

export interface AnimationTrackDocument {
  readonly events?: readonly AnimationEventDocument[];
}

export interface AnimationPlaybackState {
  readonly timelineFrame: number;
  readonly keyframeIndex: number;
  readonly sourceFrame: number;
  readonly occurrenceIndex: number;
  readonly finished: boolean;
}

export interface AnimationPlaybackContext {
  readonly previousTimelineFrame: number | null;
  readonly timelineFrame: number;
  readonly direction: 1 | -1;
  readonly cycle: number;
  readonly isScrub: boolean;
}

export interface ExpandedAnimation {
  readonly sourceFrames: readonly number[];
  readonly occurrenceIndices: readonly number[];
  readonly timelineFrameCount: number;
  readonly effectiveDurationMs: number;
}
