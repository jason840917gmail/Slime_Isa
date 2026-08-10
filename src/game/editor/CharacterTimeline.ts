import type {
  AnimationTrackDocument,
  CharacterDocument,
  CharacterEventDocument,
  HitboxSpanDocument,
  VisualSetDocument,
} from '../content/characters/types';
import {
  AnimationTimelineError,
  duplicateKeyframe,
  evenKeyframeTimes,
  normalizeAnimationClip,
  timelineFrameCount,
} from '../shared/animation';

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

export function canonicalizeSpans(spans: readonly HitboxSpanDocument[] = []): HitboxSpanDocument[] {
  const sorted = spans.map(clone).sort((a, b) => a.from - b.from || a.through - b.through || a.hitboxId.localeCompare(b.hitboxId));
  const result: HitboxSpanDocument[] = [];
  for (const span of sorted) {
    const previous = result[result.length - 1];
    if (previous && previous.hitboxId === span.hitboxId && span.from <= previous.through + 1) {
      previous.through = Math.max(previous.through, span.through);
    } else result.push(span);
  }
  return result;
}

function trackFor(character: CharacterDocument, clipId: string): AnimationTrackDocument {
  const current = character.animationTracks[clipId] ?? {};
  character.animationTracks[clipId] = current;
  return current;
}

function materializeClip(clip: VisualSetDocument['clips'][string]): void {
  if (clip.frames.length === 0) return;
  const normalized = normalizeAnimationClip(clip);
  clip.durationSeconds = normalized.durationSeconds;
  clip.keyframeTimes = [...normalized.keyframeTimes];
}

function distributeClip(clip: VisualSetDocument['clips'][string]): void {
  if (clip.frames.length === 0) return;
  materializeClip(clip);
  const frames = Math.max(timelineFrameCount(clip), clip.frames.length);
  if (frames !== timelineFrameCount(clip)) clip.durationSeconds = frames / clip.framesPerSecond;
  clip.keyframeTimes = evenKeyframeTimes(frames, clip.frames.length);
}

export function insertTimelineFrames(
  character: CharacterDocument,
  visualSet: VisualSetDocument,
  clipId: string,
  index: number,
  frames: readonly number[],
): void {
  const clip = visualSet.clips[clipId];
  if (!clip || frames.length === 0) return;
  const position = Math.max(0, Math.min(index, clip.frames.length));
  clip.frames.splice(position, 0, ...frames);
  try {
    distributeClip(clip);
  } catch (error) {
    if (!(error instanceof AnimationTimelineError)) throw error;
    clip.frames.splice(position, frames.length);
  }
  trackFor(character, clipId);
}

export function removeTimelineFrame(character: CharacterDocument, visualSet: VisualSetDocument, clipId: string, index: number): void {
  const clip = visualSet.clips[clipId];
  if (!clip || index < 0 || index >= clip.frames.length || clip.frames.length <= 1) return;
  materializeClip(clip);
  const removedTime = clip.keyframeTimes?.[index] ?? index;
  clip.frames.splice(index, 1);
  const times = [...(clip.keyframeTimes ?? [])];
  times.splice(index, 1);
  clip.keyframeTimes = index === 0 ? times.map((time) => time - removedTime) : times;
  trackFor(character, clipId);
}

export function reorderTimelineFrame(visualSet: VisualSetDocument, clipId: string, from: number, to: number): void {
  const clip = visualSet.clips[clipId];
  if (!clip || from < 0 || to < 0 || from >= clip.frames.length || to >= clip.frames.length || from === to) return;
  materializeClip(clip);
  const [frame] = clip.frames.splice(from, 1);
  clip.frames.splice(to, 0, frame);
}

export function duplicateTimelineFrame(character: CharacterDocument, visualSet: VisualSetDocument, clipId: string, index: number): void {
  const clip = visualSet.clips[clipId];
  if (!clip || index < 0 || index >= clip.frames.length) return;
  materializeClip(clip);
  try {
    const duplicated = duplicateKeyframe(normalizeAnimationClip(clip), index);
    clip.frames = duplicated.frames;
    clip.keyframeTimes = duplicated.keyframeTimes;
  } catch (error) {
    if (!(error instanceof AnimationTimelineError)) throw error;
  }
  trackFor(character, clipId);
}

export function addTrackSpan(character: CharacterDocument, clipId: string, span: HitboxSpanDocument): void {
  const track = trackFor(character, clipId);
  track.hitboxSpans = canonicalizeSpans([...(track.hitboxSpans ?? []), span]);
}

export function removeTrackSpan(character: CharacterDocument, clipId: string, spanIndex: number): void {
  const track = trackFor(character, clipId);
  track.hitboxSpans?.splice(spanIndex, 1);
  track.hitboxSpans = canonicalizeSpans(track.hitboxSpans);
}

export function addTrackEvent(character: CharacterDocument, clipId: string, event: CharacterEventDocument): void {
  const track = trackFor(character, clipId);
  track.events = [...(track.events ?? []), clone(event)];
}

export function removeTrackEvent(character: CharacterDocument, clipId: string, eventIndex: number): void {
  const track = trackFor(character, clipId);
  track.events?.splice(eventIndex, 1);
}
