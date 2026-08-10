import type { NormalizedAnimationClipDocument } from '../shared/animation';
import { holdLengthAtKeyframe, timelineFrameCount } from '../shared/animation';

export interface AnimationTimelineKeyframeView {
  readonly index: number;
  readonly sourceFrame: number;
  readonly start: number;
  readonly hold: number;
  readonly through: number;
}

export interface AnimationTimelineViewModel {
  readonly timelineFrames: number;
  readonly keyframes: readonly AnimationTimelineKeyframeView[];
}

/** Shared editor view model for the ruler and duration-block visual track. */
export function createAnimationTimelineView(clip: NormalizedAnimationClipDocument): AnimationTimelineViewModel {
  const totalFrames = timelineFrameCount(clip);
  return {
    timelineFrames: totalFrames,
    keyframes: clip.frames.map((sourceFrame, index) => {
      const start = clip.keyframeTimes[index];
      const hold = holdLengthAtKeyframe(clip, index);
      return { index, sourceFrame, start, hold, through: start + hold - 1 };
    }),
  };
}

export function toggleTimelineSelection(selected: readonly number[], index: number): number[] {
  const next = new Set(selected);
  if (next.has(index)) next.delete(index);
  else next.add(index);
  return [...next].sort((left, right) => left - right);
}
