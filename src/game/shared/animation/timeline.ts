import type {
  AnimationClipDocument,
  ExpandedAnimation,
  NormalizedAnimationClipDocument,
} from './types';

export class AnimationTimelineError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AnimationTimelineError';
  }
}

export function timelineFrameCount(clip: Pick<AnimationClipDocument, 'durationSeconds' | 'framesPerSecond'>): number {
  const requestedDuration = clip.durationSeconds ?? 0;
  return Math.max(1, Math.round(requestedDuration * clip.framesPerSecond));
}

export function legacyTimelineFrameCount(clip: Pick<AnimationClipDocument, 'frames' | 'framesPerSecond'>): number {
  return Math.max(1, clip.frames.length);
}

export function evenKeyframeTimes(timelineFrames: number, keyframeCount: number): number[] {
  if (keyframeCount < 1) throw new AnimationTimelineError('An animation must contain at least one keyframe.');
  if (keyframeCount > timelineFrames) {
    throw new AnimationTimelineError(`Cannot place ${keyframeCount} keyframes in ${timelineFrames} timeline frames.`);
  }
  return Array.from({ length: keyframeCount }, (_, index) => Math.floor(index * timelineFrames / keyframeCount));
}

export function validateNormalizedAnimationClip(clip: NormalizedAnimationClipDocument): string[] {
  const issues: string[] = [];
  const frameCount = clip.frames.length;
  const timelineFrames = timelineFrameCount(clip);
  if (frameCount === 0) issues.push('frames must contain at least one source frame');
  if (!Number.isFinite(clip.durationSeconds) || clip.durationSeconds <= 0) issues.push('durationSeconds must be positive and finite');
  if (!Number.isInteger(clip.framesPerSecond) || clip.framesPerSecond < 1 || clip.framesPerSecond > 240) {
    issues.push('framesPerSecond must be an integer from 1 through 240');
  }
  if (clip.keyframeTimes.length !== frameCount) issues.push('keyframeTimes must match frames length');
  if (clip.keyframeTimes[0] !== 0) issues.push('the first keyframe must start at timeline frame 0');
  for (const [index, time] of clip.keyframeTimes.entries()) {
    if (!Number.isInteger(time) || time < 0 || time >= timelineFrames) issues.push(`keyframeTimes[${index}] must be inside [0, ${timelineFrames})`);
    if (index > 0 && time <= clip.keyframeTimes[index - 1]) issues.push('keyframeTimes must be strictly increasing');
  }
  if (frameCount > timelineFrames) issues.push('the clip has more keyframes than timeline frames');
  return issues;
}

export function normalizeAnimationClip(clip: AnimationClipDocument): NormalizedAnimationClipDocument {
  if (clip.frames.length === 0) throw new AnimationTimelineError('Cannot normalize an empty animation clip.');
  const hasTimes = clip.keyframeTimes !== undefined;
  const hasDuration = clip.durationSeconds !== undefined;
  if (hasTimes !== hasDuration) throw new AnimationTimelineError('keyframeTimes and durationSeconds must be authored together.');

  const durationSeconds = clip.durationSeconds ?? clip.frames.length / clip.framesPerSecond;
  const timelineFrames = Math.max(1, Math.round(durationSeconds * clip.framesPerSecond));
  const keyframeTimes = clip.keyframeTimes
    ? [...clip.keyframeTimes]
    : Array.from({ length: clip.frames.length }, (_, index) => index);
  const normalized: NormalizedAnimationClipDocument = {
    ...clip,
    keyframeTimes,
    durationSeconds,
  };
  const issues = validateNormalizedAnimationClip(normalized);
  if (issues.length > 0) throw new AnimationTimelineError(issues.join('; '));
  if (timelineFrames < keyframeTimes.length) throw new AnimationTimelineError('The clip cannot fit all keyframes in its timeline.');
  return normalized;
}

export function keyframeIndexAtTimelineFrame(clip: NormalizedAnimationClipDocument, timelineFrame: number): number {
  const frame = Math.max(0, Math.min(Math.floor(timelineFrame), timelineFrameCount(clip) - 1));
  let index = 0;
  for (let candidate = 1; candidate < clip.keyframeTimes.length; candidate += 1) {
    if (clip.keyframeTimes[candidate] > frame) break;
    index = candidate;
  }
  return index;
}

export function holdLengthAtKeyframe(clip: NormalizedAnimationClipDocument, keyframeIndex: number): number {
  const start = clip.keyframeTimes[keyframeIndex];
  const next = clip.keyframeTimes[keyframeIndex + 1] ?? timelineFrameCount(clip);
  return Math.max(0, next - start);
}

export function expandAnimationClip(clip: NormalizedAnimationClipDocument): ExpandedAnimation {
  const timelineFrames = timelineFrameCount(clip);
  const sourceFrames: number[] = [];
  const occurrenceIndices: number[] = [];
  for (let timelineFrame = 0; timelineFrame < timelineFrames; timelineFrame += 1) {
    const occurrenceIndex = keyframeIndexAtTimelineFrame(clip, timelineFrame);
    sourceFrames.push(clip.frames[occurrenceIndex]);
    occurrenceIndices.push(occurrenceIndex);
  }
  return {
    sourceFrames,
    occurrenceIndices,
    timelineFrameCount: timelineFrames,
    effectiveDurationMs: timelineFrames * (1000 / clip.framesPerSecond),
  };
}

export function rescaleKeyframeTimes(
  clip: NormalizedAnimationClipDocument,
  nextDurationSeconds: number,
  nextFramesPerSecond: number,
): number[] {
  const nextTimelineFrames = Math.max(1, Math.round(nextDurationSeconds * nextFramesPerSecond));
  if (clip.frames.length > nextTimelineFrames) {
    throw new AnimationTimelineError(`Cannot fit ${clip.frames.length} keyframes in ${nextTimelineFrames} timeline frames.`);
  }
  const raw = clip.keyframeTimes.map((time) => Math.round(time * nextTimelineFrames / timelineFrameCount(clip)));
  return raw.map((time, index) => {
    if (index === 0) return 0;
    return Math.min(
      nextTimelineFrames - (clip.frames.length - index),
      Math.max(raw[index - 1] + 1, time),
    );
  });
}

export function moveKeyframeTime(
  clip: NormalizedAnimationClipDocument,
  keyframeIndex: number,
  requestedTimelineFrame: number,
): number[] {
  if (keyframeIndex < 0 || keyframeIndex >= clip.keyframeTimes.length) throw new AnimationTimelineError('Unknown keyframe.');
  const min = keyframeIndex === 0 ? 0 : clip.keyframeTimes[keyframeIndex - 1] + 1;
  const max = keyframeIndex === clip.keyframeTimes.length - 1
    ? timelineFrameCount(clip) - 1
    : clip.keyframeTimes[keyframeIndex + 1] - 1;
  if (min > max) throw new AnimationTimelineError('There is no free timeline cell for this keyframe.');
  const next = [...clip.keyframeTimes];
  next[keyframeIndex] = Math.max(min, Math.min(max, Math.round(requestedTimelineFrame)));
  return next;
}

export function deleteKeyframes(
  clip: NormalizedAnimationClipDocument,
  selectedIndices: readonly number[],
): { frames: number[]; keyframeTimes: number[]; removedIndices: number[] } {
  const selected = [...new Set(selectedIndices)].filter((index) => index >= 0 && index < clip.frames.length).sort((a, b) => a - b);
  if (selected.length === 0) throw new AnimationTimelineError('Select at least one keyframe.');
  if (selected.length >= clip.frames.length) throw new AnimationTimelineError('An animation must contain at least one keyframe.');
  const selectedSet = new Set(selected);
  const firstRemoved = selected[0];
  const nextFrames = clip.frames.filter((_, index) => !selectedSet.has(index));
  const nextTimes = clip.keyframeTimes.filter((_, index) => !selectedSet.has(index));
  const offset = firstRemoved === 0 ? nextTimes[0] : 0;
  return {
    frames: nextFrames,
    keyframeTimes: nextTimes.map((time) => time - offset),
    removedIndices: selected,
  };
}

export function duplicateKeyframe(
  clip: NormalizedAnimationClipDocument,
  keyframeIndex: number,
): { frames: number[]; keyframeTimes: number[]; newIndex: number; newToOldPositions: number[] } {
  if (keyframeIndex < 0 || keyframeIndex >= clip.frames.length) throw new AnimationTimelineError('Unknown keyframe.');
  const holds = clip.frames.map((_, index) => holdLengthAtKeyframe(clip, index));
  const longestHold = Math.max(...holds);
  const ownerIndex = holds.findIndex((hold) => hold === longestHold);
  if (longestHold <= 1) throw new AnimationTimelineError('There is no free timeline cell for a duplicate keyframe.');
  const duplicateTime = clip.keyframeTimes[ownerIndex] + Math.floor(longestHold / 2);
  const insertionIndex = clip.keyframeTimes.findIndex((time) => time > duplicateTime);
  const nextIndex = insertionIndex === -1 ? clip.frames.length : insertionIndex;
  const frames = [...clip.frames];
  const keyframeTimes = [...clip.keyframeTimes];
  frames.splice(nextIndex, 0, clip.frames[keyframeIndex]);
  keyframeTimes.splice(nextIndex, 0, duplicateTime);
  return {
    frames,
    keyframeTimes,
    newIndex: nextIndex,
    newToOldPositions: [...Array.from({ length: nextIndex }, (_, index) => index), keyframeIndex, ...Array.from({ length: clip.frames.length - nextIndex }, (_, index) => nextIndex + index)],
  };
}
