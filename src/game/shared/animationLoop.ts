import type { AnimationClipDocument } from './animation';
import { timelineFrameCount } from './animation';

type AnimationLoopClip = Pick<AnimationClipDocument, 'frames' | 'framesPerSecond' | 'loop' | 'loopMode' | 'durationSeconds' | 'keyframeTimes'>;

function playbackFrameCount(clip: AnimationLoopClip): number {
  return clip.keyframeTimes !== undefined && clip.durationSeconds !== undefined
    ? timelineFrameCount(clip)
    : Math.max(1, clip.frames.length);
}

export function isPingPongLoop(clip: AnimationLoopClip): boolean {
  return clip.loop && clip.loopMode === 'ping-pong' && playbackFrameCount(clip) > 1;
}

/** Number of frame steps in one complete loop cycle. Endpoints are not repeated. */
export function animationCycleFrameCount(clip: AnimationLoopClip): number {
  const frameCount = playbackFrameCount(clip);
  if (isPingPongLoop(clip)) return frameCount * 2 - 2;
  return frameCount;
}

/** Resolve an absolute playback step to the authored timeline frame index. */
export function animationFrameIndexAtStep(clip: AnimationLoopClip, step: number): number {
  const frameCount = playbackFrameCount(clip);
  if (frameCount <= 1) return 0;
  const cycleLength = animationCycleFrameCount(clip);
  const offset = Math.max(0, Math.floor(step)) % cycleLength;
  return isPingPongLoop(clip) && offset >= frameCount
    ? cycleLength - offset
    : offset;
}

export function animationCycleDurationMs(clip: AnimationLoopClip): number {
  return animationCycleFrameCount(clip) * (1000 / clip.framesPerSecond);
}
