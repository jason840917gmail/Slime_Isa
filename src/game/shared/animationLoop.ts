import type { VisualClipDocument } from '../content/characters/types';

type AnimationLoopClip = {
  readonly frames: readonly VisualClipDocument['frames'][number][];
  readonly framesPerSecond: number;
  readonly loop: boolean;
  readonly loopMode?: VisualClipDocument['loopMode'];
};

export function isPingPongLoop(clip: AnimationLoopClip): boolean {
  return clip.loop && clip.loopMode === 'ping-pong' && clip.frames.length > 1;
}

/** Number of frame steps in one complete loop cycle. Endpoints are not repeated. */
export function animationCycleFrameCount(clip: AnimationLoopClip): number {
  if (isPingPongLoop(clip)) return clip.frames.length * 2 - 2;
  return Math.max(clip.frames.length, 1);
}

/** Resolve an absolute playback step to the authored timeline frame index. */
export function animationFrameIndexAtStep(clip: AnimationLoopClip, step: number): number {
  const frameCount = clip.frames.length;
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
