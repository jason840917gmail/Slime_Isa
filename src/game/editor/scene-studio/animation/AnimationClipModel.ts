import type { JsonValue } from '../../../content/scenes/types';
import type { AnimationDomain, AnimationKeyTransition, AnimationPropertyKey, AnimationTrackInterpolation } from '../../../runtime/scene/animation/AnimationBinding';
import type { UniversalAnimationEvent } from '../../../runtime/scene/animation/AnimationEvent';
import type { UniversalAnimationDocument, UniversalAnimationPropertyTrack } from '../../../runtime/scene/animation/AnimationPlayerNode';
import type { AnimationLoopMode } from '../../../shared/animation';

/**
 * Pure, immutable editing operations for AnimationPlayer libraries. Every
 * function returns new documents and throws on invalid requests so the
 * caller can surface the message and keep the previous state.
 */

export type AnimationClips = Readonly<Record<string, UniversalAnimationDocument>>;

/** A key addressed by its track index and frame. */
export interface AnimationKeyRef {
  readonly track: number;
  readonly at: number;
}

/** Maps an old frame to its new frame, or undefined when the frame was removed. */
export type FrameRemap = (frame: number) => number | undefined;

export interface ClipEdit {
  readonly clip: UniversalAnimationDocument;
  readonly remap: FrameRemap;
}

export interface AnimationKeyClipboard {
  readonly entries: readonly {
    readonly binding: string;
    readonly property: string;
    readonly offset: number;
    readonly value: JsonValue;
    readonly transition?: AnimationKeyTransition;
  }[];
}

const CLIP_ID_PATTERN = /^[a-z0-9][a-z0-9._-]*$/i;
const EVENT_ID_PATTERN = /^[a-z0-9][a-z0-9._:-]*$/i;
const MAX_FRAMES = 10_000;

export function clipFrameCount(clip: Pick<UniversalAnimationDocument, 'durationSeconds' | 'framesPerSecond'>): number {
  return Math.max(1, Math.round(clip.durationSeconds * clip.framesPerSecond));
}

export function formatClipSeconds(frame: number, framesPerSecond: number): string {
  return `${(frame / framesPerSecond).toFixed(frame % framesPerSecond === 0 ? 1 : 3)}s`;
}

function requireClip(clips: AnimationClips, id: string): UniversalAnimationDocument {
  const clip = clips[id];
  if (!clip) throw new Error(`Unknown animation '${id}'`);
  return clip;
}

function requireTrack(clip: UniversalAnimationDocument, index: number): UniversalAnimationPropertyTrack {
  const track = clip.tracks[index];
  if (!track) throw new Error(`Unknown track #${index}`);
  return track;
}

function validClipId(id: string): string {
  const trimmed = id.trim();
  if (!CLIP_ID_PATTERN.test(trimmed)) throw new Error('Animation names use letters, digits, dots, dashes and underscores');
  return trimmed;
}

function sortedKeys(keys: readonly AnimationPropertyKey[]): AnimationPropertyKey[] {
  return [...keys].sort((left, right) => left.at - right.at);
}

function sortedEvents(events: readonly UniversalAnimationEvent[]): UniversalAnimationEvent[] {
  return [...events].sort((left, right) => left.at - right.at);
}

function withTracks(clip: UniversalAnimationDocument, tracks: readonly UniversalAnimationPropertyTrack[]): UniversalAnimationDocument {
  return { ...clip, tracks };
}

function replaceTrack(clip: UniversalAnimationDocument, index: number, track: UniversalAnimationPropertyTrack): UniversalAnimationDocument {
  requireTrack(clip, index);
  return withTracks(clip, clip.tracks.map((candidate, candidateIndex) => candidateIndex === index ? track : candidate));
}

function requireFrame(clip: UniversalAnimationDocument, at: number): number {
  if (!Number.isInteger(at) || at < 0 || at >= clipFrameCount(clip)) throw new Error(`Frame ${at} is outside 0–${clipFrameCount(clip) - 1}`);
  return at;
}

/** Applies a frame remap to every key and event, dropping removed frames; later keys win collisions. */
function remapClip(clip: UniversalAnimationDocument, remap: FrameRemap): UniversalAnimationDocument {
  const tracks = clip.tracks.map((track) => {
    const byFrame = new Map<number, AnimationPropertyKey>();
    for (const key of sortedKeys(track.keys)) {
      const at = remap(key.at);
      if (at !== undefined) byFrame.set(at, { ...key, at });
    }
    return { ...track, keys: sortedKeys([...byFrame.values()]) };
  });
  const events = (clip.events ?? []).flatMap((event) => {
    const at = remap(event.at);
    return at === undefined ? [] : [{ ...event, at }];
  });
  return { ...clip, tracks, ...(clip.events ? { events: sortedEvents(events) } : {}) };
}

// ---------------------------------------------------------------------------
// Clips
// ---------------------------------------------------------------------------

export function createClip(clips: AnimationClips, id: string, options: { readonly framesPerSecond?: number; readonly frameCount?: number; readonly loop?: boolean } = {}): AnimationClips {
  const name = validClipId(id);
  if (clips[name]) throw new Error(`Animation '${name}' already exists`);
  const framesPerSecond = options.framesPerSecond ?? 12;
  const frameCount = options.frameCount ?? framesPerSecond;
  return { ...clips, [name]: { durationSeconds: frameCount / framesPerSecond, framesPerSecond, loop: options.loop ?? false, loopMode: 'wrap', tracks: [], events: [] } };
}

/** Renames a clip in place, keeping its position in the library. */
export function renameClip(clips: AnimationClips, from: string, to: string): AnimationClips {
  requireClip(clips, from);
  const name = validClipId(to);
  if (name === from) return clips;
  if (clips[name]) throw new Error(`Animation '${name}' already exists`);
  return Object.fromEntries(Object.entries(clips).map(([id, clip]) => [id === from ? name : id, clip]));
}

export function duplicateClip(clips: AnimationClips, from: string, to: string): AnimationClips {
  const source = requireClip(clips, from);
  const name = validClipId(to);
  if (clips[name]) throw new Error(`Animation '${name}' already exists`);
  return { ...clips, [name]: structuredClone(source) };
}

export function deleteClip(clips: AnimationClips, id: string): AnimationClips {
  requireClip(clips, id);
  return Object.fromEntries(Object.entries(clips).filter(([candidate]) => candidate !== id));
}

export function uniqueClipId(clips: AnimationClips, base: string): string {
  const normalized = base.replace(/[^a-z0-9._-]+/gi, '-').replace(/^-+/, '') || 'animation';
  let candidate = normalized;
  let suffix = 2;
  while (clips[candidate]) candidate = `${normalized}-${suffix++}`;
  return candidate;
}

function mirrorValue(property: string, value: JsonValue, axis: 'x' | 'y'): JsonValue {
  const component = axis === 'x' ? 0 : 1;
  if ((property === 'position' || property === 'visualOffset' || property === 'velocity') && Array.isArray(value) && value.length === 2) {
    return value.map((entry, index) => index === component && typeof entry === 'number' ? -entry : entry);
  }
  if (property === 'rotation' && typeof value === 'number') return -value;
  if (property === 'angleRad' && typeof value === 'number') return axis === 'x' ? Math.PI - value : -value;
  if (property === (axis === 'x' ? 'flipX' : 'flipY') && typeof value === 'boolean') return !value;
  return value;
}

/**
 * Duplicates a clip mirrored across an axis — the old studio's right→left and
 * down→up direction workflow. Positions, offsets and rotations flip sign and
 * the matching flip flag toggles.
 */
export function mirrorClip(clips: AnimationClips, from: string, to: string, axis: 'x' | 'y'): AnimationClips {
  const source = requireClip(clips, from);
  const name = validClipId(to);
  if (clips[name] && name !== from) throw new Error(`Animation '${name}' already exists`);
  const mirrored: UniversalAnimationDocument = {
    ...structuredClone(source),
    tracks: source.tracks.map((track) => ({ ...structuredClone(track), keys: track.keys.map((key) => ({ ...structuredClone(key), value: mirrorValue(track.property, key.value, axis) })) })),
  };
  return { ...clips, [name]: mirrored };
}

// ---------------------------------------------------------------------------
// Timing
// ---------------------------------------------------------------------------

/** Changes the frame rate. `keepDuration` rescales keys so timing in seconds is preserved. */
export function setFramesPerSecond(clip: UniversalAnimationDocument, framesPerSecond: number, keepDuration: boolean): ClipEdit {
  if (!Number.isFinite(framesPerSecond) || framesPerSecond <= 0 || framesPerSecond > 240) throw new Error('Frame rate must be between 0 and 240');
  const oldFrames = clipFrameCount(clip);
  if (!keepDuration) {
    return { clip: { ...clip, framesPerSecond, durationSeconds: oldFrames / framesPerSecond }, remap: (frame) => frame };
  }
  const newFrames = Math.max(1, Math.round(clip.durationSeconds * framesPerSecond));
  const factor = framesPerSecond / clip.framesPerSecond;
  const remap: FrameRemap = (frame) => Math.min(newFrames - 1, Math.round(frame * factor));
  return { clip: remapClip({ ...clip, framesPerSecond, durationSeconds: newFrames / framesPerSecond }, remap), remap };
}

/** Changes the clip length in frames. `stretch` rescales keys; otherwise keys past the end are dropped. */
export function setFrameCount(clip: UniversalAnimationDocument, frameCount: number, stretch: boolean): ClipEdit {
  if (!Number.isInteger(frameCount) || frameCount < 1 || frameCount > MAX_FRAMES) throw new Error(`Length must be 1–${MAX_FRAMES} frames`);
  const oldFrames = clipFrameCount(clip);
  const remap: FrameRemap = stretch
    ? (frame) => (oldFrames <= 1 ? 0 : Math.min(frameCount - 1, Math.round(frame * (frameCount - 1) / (oldFrames - 1))))
    : (frame) => (frame < frameCount ? frame : undefined);
  return { clip: remapClip({ ...clip, durationSeconds: frameCount / clip.framesPerSecond }, remap), remap };
}

export function setLoop(clip: UniversalAnimationDocument, loop: boolean, loopMode: AnimationLoopMode): UniversalAnimationDocument {
  return { ...clip, loop, loopMode };
}

/** Inserts empty frames at `at`, shifting later keys and events right. */
export function insertFrames(clip: UniversalAnimationDocument, at: number, count: number): ClipEdit {
  if (!Number.isInteger(count) || count < 1) throw new Error('Insert at least one frame');
  const frames = clipFrameCount(clip);
  if (frames + count > MAX_FRAMES) throw new Error(`Clips are limited to ${MAX_FRAMES} frames`);
  requireFrame(clip, at);
  const remap: FrameRemap = (frame) => (frame >= at ? frame + count : frame);
  return { clip: remapClip({ ...clip, durationSeconds: (frames + count) / clip.framesPerSecond }, remap), remap };
}

/** Removes `count` frames starting at `at` with their keys and events, shifting later ones left. */
export function deleteFrames(clip: UniversalAnimationDocument, at: number, count: number): ClipEdit {
  const frames = clipFrameCount(clip);
  requireFrame(clip, at);
  const removed = Math.min(count, frames - at);
  if (removed < 1 || frames - removed < 1) throw new Error('A clip keeps at least one frame');
  const remap: FrameRemap = (frame) => (frame < at ? frame : frame < at + removed ? undefined : frame - removed);
  return { clip: remapClip({ ...clip, durationSeconds: (frames - removed) / clip.framesPerSecond }, remap), remap };
}

// ---------------------------------------------------------------------------
// Tracks
// ---------------------------------------------------------------------------

export function addTrack(clip: UniversalAnimationDocument, binding: string, property: string, firstKey?: AnimationPropertyKey): UniversalAnimationDocument {
  if (!binding || !property) throw new Error('A track needs a node path and a property');
  if (clip.tracks.some((track) => track.binding === binding && track.property === property)) throw new Error(`Track '${binding}:${property}' already exists`);
  if (firstKey) requireFrame(clip, firstKey.at);
  return withTracks(clip, [...clip.tracks, { binding, property, keys: firstKey ? [structuredClone(firstKey)] : [] }]);
}

export function removeTrack(clip: UniversalAnimationDocument, index: number): UniversalAnimationDocument {
  requireTrack(clip, index);
  return withTracks(clip, clip.tracks.filter((_, candidate) => candidate !== index));
}

export function moveTrack(clip: UniversalAnimationDocument, index: number, offset: number): UniversalAnimationDocument {
  const track = requireTrack(clip, index);
  const target = Math.max(0, Math.min(clip.tracks.length - 1, index + offset));
  if (target === index) return clip;
  const tracks = clip.tracks.filter((_, candidate) => candidate !== index);
  tracks.splice(target, 0, track);
  return withTracks(clip, tracks);
}

export function setTrackEnabled(clip: UniversalAnimationDocument, index: number, enabled: boolean): UniversalAnimationDocument {
  const { enabled: _previous, ...track } = requireTrack(clip, index);
  return replaceTrack(clip, index, enabled ? track : { ...track, enabled: false });
}

export function setTrackInterpolation(clip: UniversalAnimationDocument, index: number, interpolation: AnimationTrackInterpolation | undefined): UniversalAnimationDocument {
  const { interpolation: _previous, ...track } = requireTrack(clip, index);
  return replaceTrack(clip, index, interpolation ? { ...track, interpolation } : track);
}

/** Points a track at another node path (Godot's "change track path" for broken tracks). */
export function retargetTrack(clip: UniversalAnimationDocument, index: number, binding: string): UniversalAnimationDocument {
  const track = requireTrack(clip, index);
  if (!binding) throw new Error('A track needs a node path');
  if (clip.tracks.some((candidate, candidateIndex) => candidateIndex !== index && candidate.binding === binding && candidate.property === track.property)) {
    throw new Error(`Track '${binding}:${track.property}' already exists`);
  }
  return replaceTrack(clip, index, { ...track, binding });
}

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

export function keyAt(track: UniversalAnimationPropertyTrack, at: number): AnimationPropertyKey | undefined {
  return track.keys.find((key) => key.at === at);
}

/** Inserts or replaces a key; an existing transition survives unless a new one is given. */
export function setKey(clip: UniversalAnimationDocument, trackIndex: number, at: number, value: JsonValue, transition?: AnimationKeyTransition): UniversalAnimationDocument {
  const track = requireTrack(clip, trackIndex);
  requireFrame(clip, at);
  const previous = keyAt(track, at);
  const nextTransition = transition ?? previous?.transition;
  const key: AnimationPropertyKey = { at, value: structuredClone(value), ...(nextTransition && nextTransition !== 'linear' ? { transition: nextTransition } : {}) };
  return replaceTrack(clip, trackIndex, { ...track, keys: sortedKeys([...track.keys.filter((candidate) => candidate.at !== at), key]) });
}

export function removeKeys(clip: UniversalAnimationDocument, refs: readonly AnimationKeyRef[]): UniversalAnimationDocument {
  const doomed = new Set(refs.map((ref) => `${ref.track}:${ref.at}`));
  return withTracks(clip, clip.tracks.map((track, index) => ({ ...track, keys: track.keys.filter((key) => !doomed.has(`${index}:${key.at}`)) })));
}

/**
 * Moves (or, with `copy`, duplicates) keys by a frame delta. Moved keys
 * overwrite unselected keys at their destination, like Godot.
 */
export function moveKeys(clip: UniversalAnimationDocument, refs: readonly AnimationKeyRef[], delta: number, copy = false): { readonly clip: UniversalAnimationDocument; readonly refs: readonly AnimationKeyRef[] } {
  if (!Number.isInteger(delta)) throw new Error('Keys move by whole frames');
  if (refs.length === 0 || (delta === 0 && !copy)) return { clip, refs };
  const frames = clipFrameCount(clip);
  const moving = new Map<number, Set<number>>();
  for (const ref of refs) {
    const track = requireTrack(clip, ref.track);
    if (!keyAt(track, ref.at)) throw new Error(`No key at frame ${ref.at}`);
    const target = ref.at + delta;
    if (target < 0 || target >= frames) throw new Error('Keys cannot move outside the clip');
    moving.set(ref.track, (moving.get(ref.track) ?? new Set()).add(ref.at));
  }
  const tracks = clip.tracks.map((track, index) => {
    const frameSet = moving.get(index);
    if (!frameSet) return track;
    const moved = track.keys.filter((key) => frameSet.has(key.at)).map((key) => ({ ...structuredClone(key), at: key.at + delta }));
    const destinations = new Set(moved.map((key) => key.at));
    const kept = track.keys.filter((key) => (copy || !frameSet.has(key.at)) && !destinations.has(key.at));
    return { ...track, keys: sortedKeys([...kept, ...moved]) };
  });
  return { clip: withTracks(clip, tracks), refs: refs.map((ref) => ({ track: ref.track, at: ref.at + delta })) };
}

export function setKeyTransition(clip: UniversalAnimationDocument, refs: readonly AnimationKeyRef[], transition: AnimationKeyTransition): UniversalAnimationDocument {
  const chosen = new Set(refs.map((ref) => `${ref.track}:${ref.at}`));
  return withTracks(clip, clip.tracks.map((track, index) => ({
    ...track,
    keys: track.keys.map((key) => {
      if (!chosen.has(`${index}:${key.at}`)) return key;
      const { transition: _previous, ...rest } = key;
      return transition === 'linear' ? rest : { ...rest, transition };
    }),
  })));
}

export function copyKeys(clip: UniversalAnimationDocument, refs: readonly AnimationKeyRef[]): AnimationKeyClipboard {
  if (refs.length === 0) return { entries: [] };
  const origin = Math.min(...refs.map((ref) => ref.at));
  return {
    entries: refs.flatMap((ref) => {
      const track = requireTrack(clip, ref.track);
      const key = keyAt(track, ref.at);
      return key ? [{ binding: track.binding, property: track.property, offset: ref.at - origin, value: structuredClone(key.value), ...(key.transition ? { transition: key.transition } : {}) }] : [];
    }),
  };
}

/**
 * Pastes keys at a frame. Entries go to their original track; a clipboard
 * copied from a single track can instead target `fallbackTrack`.
 */
export function pasteKeys(clip: UniversalAnimationDocument, clipboard: AnimationKeyClipboard, at: number, fallbackTrack?: number): { readonly clip: UniversalAnimationDocument; readonly refs: readonly AnimationKeyRef[] } {
  if (clipboard.entries.length === 0) throw new Error('Nothing copied');
  const singleTrack = new Set(clipboard.entries.map((entry) => `${entry.binding}::${entry.property}`)).size === 1;
  const frames = clipFrameCount(clip);
  let next = clip;
  const refs: AnimationKeyRef[] = [];
  for (const entry of clipboard.entries) {
    const target = at + entry.offset;
    if (target >= frames) continue;
    let index = next.tracks.findIndex((track) => track.binding === entry.binding && track.property === entry.property);
    if (singleTrack && fallbackTrack !== undefined && next.tracks[fallbackTrack]?.property === entry.property) index = fallbackTrack;
    if (index < 0) continue;
    next = setKey(next, index, target, entry.value, entry.transition ?? 'linear');
    refs.push({ track: index, at: target });
  }
  if (refs.length === 0) throw new Error('No matching tracks for the copied keys');
  return { clip: next, refs };
}

function sameValue(left: JsonValue, right: JsonValue): boolean {
  return JSON.stringify(left) === JSON.stringify(right);
}

function numericLerp(left: JsonValue, right: JsonValue, ratio: number): JsonValue | undefined {
  if (typeof left === 'number' && typeof right === 'number') return left + (right - left) * ratio;
  if (Array.isArray(left) && Array.isArray(right) && left.length === 2 && right.length === 2 && [...left, ...right].every((entry) => typeof entry === 'number')) {
    return [(left[0] as number) + ((right[0] as number) - (left[0] as number)) * ratio, (left[1] as number) + ((right[1] as number) - (left[1] as number)) * ratio];
  }
  return undefined;
}

function nearlyEqual(left: JsonValue | undefined, right: JsonValue): boolean {
  if (left === undefined) return false;
  if (typeof left === 'number' && typeof right === 'number') return Math.abs(left - right) < 1e-6;
  if (Array.isArray(left) && Array.isArray(right)) return left.length === right.length && left.every((entry, index) => nearlyEqual(entry, right[index]));
  return sameValue(left, right);
}

/**
 * Drops keys that do not change the result: repeats on nearest tracks and
 * collinear keys on linear tracks. Converted clips key every frame, so this
 * turns them back into hand-editable timelines.
 */
export function simplifyKeys(clip: UniversalAnimationDocument, isLinear: (track: UniversalAnimationPropertyTrack) => boolean): { readonly clip: UniversalAnimationDocument; readonly removed: number } {
  let removed = 0;
  const tracks = clip.tracks.map((track) => {
    const keys = sortedKeys(track.keys);
    const linear = isLinear(track);
    const kept: AnimationPropertyKey[] = [];
    keys.forEach((key, index) => {
      const previous = kept.at(-1);
      const next = keys[index + 1];
      if (!previous) { kept.push(key); return; }
      if (!linear) {
        if (sameValue(previous.value, key.value) && !key.transition) { removed += 1; return; }
        kept.push(key);
        return;
      }
      if (!next) {
        if (sameValue(previous.value, key.value) && !previous.transition) { removed += 1; return; }
        kept.push(key);
        return;
      }
      const expected = previous.transition || key.transition ? undefined : numericLerp(previous.value, next.value, (key.at - previous.at) / (next.at - previous.at));
      if (nearlyEqual(expected, key.value)) { removed += 1; return; }
      kept.push(key);
    });
    return { ...track, keys: kept };
  });
  return { clip: withTracks(clip, tracks), removed };
}

/** The value a track produces at a frame, mirroring AnimationBinding (vectors stay [x, y]). */
export function sampleTrack(track: UniversalAnimationPropertyTrack, frame: number, linear: boolean): JsonValue | undefined {
  const keys = sortedKeys(track.keys);
  if (keys.length === 0) return undefined;
  let left = keys[0];
  let right = keys.at(-1) ?? left;
  for (const key of keys) {
    if (key.at <= frame) left = key;
    if (key.at >= frame) { right = key; break; }
  }
  if (!linear || right.at <= left.at) return structuredClone(left.value);
  const ratio = (frame - left.at) / (right.at - left.at);
  const eased = left.transition === 'ease-in' ? ratio * ratio
    : left.transition === 'ease-out' ? 1 - (1 - ratio) ** 2
      : left.transition === 'ease-in-out' ? (ratio < 0.5 ? 2 * ratio * ratio : 1 - (-2 * ratio + 2) ** 2 / 2)
        : ratio;
  return numericLerp(left.value, right.value, eased) ?? structuredClone(left.value);
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

function validEvent(clip: UniversalAnimationDocument, event: UniversalAnimationEvent): UniversalAnimationEvent {
  requireFrame(clip, event.at);
  if (!EVENT_ID_PATTERN.test(event.eventId)) throw new Error('Event IDs use letters, digits, dots, colons, dashes and underscores');
  return structuredClone(event);
}

export function addEvent(clip: UniversalAnimationDocument, event: UniversalAnimationEvent): { readonly clip: UniversalAnimationDocument; readonly index: number } {
  const added = validEvent(clip, event);
  const events = sortedEvents([...(clip.events ?? []), added]);
  return { clip: { ...clip, events }, index: events.lastIndexOf(added) };
}

export function updateEvent(clip: UniversalAnimationDocument, index: number, patch: Partial<UniversalAnimationEvent>): { readonly clip: UniversalAnimationDocument; readonly index: number } {
  const current = clip.events?.[index];
  if (!current) throw new Error(`Unknown event #${index}`);
  const merged = { ...current, ...patch } as Record<string, unknown>;
  for (const key of Object.keys(merged)) if (merged[key] === undefined) delete merged[key];
  if (merged.gameplay === false) delete merged.gameplay;
  const updated = validEvent(clip, merged as unknown as UniversalAnimationEvent);
  const events = sortedEvents([...(clip.events ?? []).filter((_, candidate) => candidate !== index), updated]);
  return { clip: { ...clip, events }, index: events.lastIndexOf(updated) };
}

export function removeEvent(clip: UniversalAnimationDocument, index: number): UniversalAnimationDocument {
  if (!clip.events?.[index]) throw new Error(`Unknown event #${index}`);
  return { ...clip, events: clip.events.filter((_, candidate) => candidate !== index) };
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

export function clipDomainIssues(clip: UniversalAnimationDocument, domain: AnimationDomain): readonly string[] {
  const issues: string[] = [];
  if (domain === 'render' && clip.events?.some((event) => event.gameplay)) issues.push('Gameplay events require the physics clock domain');
  return issues;
}
