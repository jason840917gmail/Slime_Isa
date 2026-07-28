import type {
  AnimationTrackDocument,
  CharacterDocument,
  CharacterEventDocument,
  HitboxSpanDocument,
  VisualSetDocument,
} from '../content/characters/types';

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
  const track = trackFor(character, clipId);
  track.events = (track.events ?? []).map((event) => event.at >= position ? { ...event, at: event.at + frames.length } : event);
  track.hitboxSpans = canonicalizeSpans((track.hitboxSpans ?? []).map((span) => {
    if (span.from >= position) return { ...span, from: span.from + frames.length, through: span.through + frames.length };
    if (span.through >= position) return { ...span, through: span.through + frames.length };
    return span;
  }));
}

export function removeTimelineFrame(character: CharacterDocument, visualSet: VisualSetDocument, clipId: string, index: number): void {
  const clip = visualSet.clips[clipId];
  if (!clip || index < 0 || index >= clip.frames.length || clip.frames.length <= 1) return;
  clip.frames.splice(index, 1);
  const track = trackFor(character, clipId);
  track.events = (track.events ?? []).filter((event) => event.at !== index).map((event) => event.at > index ? { ...event, at: event.at - 1 } : event);
  const nextSpans: HitboxSpanDocument[] = [];
  for (const span of track.hitboxSpans ?? []) {
    if (span.through < index) nextSpans.push(span);
    else if (span.from > index) nextSpans.push({ ...span, from: span.from - 1, through: span.through - 1 });
    else if (span.from === index && span.through === index) continue;
    else if (span.from === index) nextSpans.push({ ...span, from: index, through: span.through - 1 });
    else if (span.through === index) nextSpans.push({ ...span, through: span.through - 1 });
    else nextSpans.push({ ...span, through: span.through - 1 });
  }
  track.hitboxSpans = canonicalizeSpans(nextSpans);
}

export function reorderTimelineFrame(visualSet: VisualSetDocument, clipId: string, from: number, to: number): void {
  const clip = visualSet.clips[clipId];
  if (!clip || from < 0 || to < 0 || from >= clip.frames.length || to >= clip.frames.length || from === to) return;
  const [frame] = clip.frames.splice(from, 1);
  clip.frames.splice(to, 0, frame);
}

export function duplicateTimelineFrame(character: CharacterDocument, visualSet: VisualSetDocument, clipId: string, index: number): void {
  const clip = visualSet.clips[clipId];
  if (!clip || index < 0 || index >= clip.frames.length) return;
  insertTimelineFrames(character, visualSet, clipId, index + 1, [clip.frames[index]]);
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
