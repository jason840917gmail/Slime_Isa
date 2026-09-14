import type { PropertyDescriptor } from '../../../content/scenes/propertyDescriptors';
import type { AnimationLibraryResourceDocument, JsonValue } from '../../../content/scenes/resources/types';
import type { UniversalAnimationDocument, UniversalAnimationPropertyTrack } from '../../../runtime/scene/animation/AnimationPlayerNode';
import type { UniversalAnimationEvent } from '../../../runtime/scene/animation/AnimationEvent';
import { AnimationClock } from '../../../shared/animation';

export interface AnimationTrackOption {
  readonly property: string;
  readonly interpolation: 'step' | 'numeric';
  readonly domains: readonly ('physics' | 'render')[];
}

export function animationTrackOptions(descriptors: readonly PropertyDescriptor[]): readonly AnimationTrackOption[] {
  return descriptors.flatMap((descriptor) => descriptor.animation ? [{ property: descriptor.key, interpolation: descriptor.animation.interpolation, domains: descriptor.animation.domains }] : []);
}

export class AnimationPreviewCursor {
  private positionValue = 0;
  get position(): number { return this.positionValue; }
  seek(position: number): void {
    if (!Number.isFinite(position) || position < 0) throw new Error('Animation preview position must be non-negative and finite');
    this.positionValue = position;
  }
}

function animations(resource: AnimationLibraryResourceDocument): Record<string, UniversalAnimationDocument> {
  return structuredClone(resource.animations) as unknown as Record<string, UniversalAnimationDocument>;
}

export function addPropertyTrack(
  resource: AnimationLibraryResourceDocument,
  animationId: string,
  binding: string,
  descriptor: PropertyDescriptor,
): AnimationLibraryResourceDocument {
  if (!descriptor.animation) throw new Error(`Property '${descriptor.key}' is not animatable`);
  const collection = animations(resource);
  const animation = collection[animationId];
  if (!animation) throw new Error(`Unknown animation '${animationId}'`);
  if (animation.tracks.some((track) => track.binding === binding && track.property === descriptor.key)) throw new Error(`Track '${binding}.${descriptor.key}' already exists`);
  const track: UniversalAnimationPropertyTrack = { binding, property: descriptor.key, keys: [] };
  collection[animationId] = { ...animation, tracks: [...animation.tracks, track] };
  return { ...resource, animations: collection as unknown as Readonly<Record<string, JsonValue>> };
}

export function setPropertyKey(
  resource: AnimationLibraryResourceDocument,
  animationId: string,
  binding: string,
  property: string,
  at: number,
  value: JsonValue,
): AnimationLibraryResourceDocument {
  if (!Number.isInteger(at) || at < 0) throw new Error('Animation key position must be a non-negative integer');
  const collection = animations(resource);
  const animation = collection[animationId];
  if (!animation) throw new Error(`Unknown animation '${animationId}'`);
  let found = false;
  const tracks = animation.tracks.map((track) => {
    if (track.binding !== binding || track.property !== property) return track;
    found = true;
    return { ...track, keys: [...track.keys.filter((key) => key.at !== at), { at, value: structuredClone(value) }].sort((left, right) => left.at - right.at) };
  });
  if (!found) throw new Error(`Unknown track '${binding}.${property}'`);
  collection[animationId] = { ...animation, tracks };
  return { ...resource, animations: collection as unknown as Readonly<Record<string, JsonValue>> };
}

export function addAnimationEvent(resource: AnimationLibraryResourceDocument, animationId: string, event: UniversalAnimationEvent): AnimationLibraryResourceDocument {
  if (!Number.isInteger(event.at) || event.at < 0 || !event.eventId) throw new Error('Animation event requires a stable ID and non-negative integer position');
  const collection = animations(resource);
  const animation = collection[animationId];
  if (!animation) throw new Error(`Unknown animation '${animationId}'`);
  collection[animationId] = { ...animation, events: [...(animation.events ?? []), structuredClone(event)].sort((left, right) => left.at - right.at) };
  return { ...resource, animations: collection as unknown as Readonly<Record<string, JsonValue>> };
}

export function validateAnimationDomain(animation: UniversalAnimationDocument, domain: 'physics' | 'render'): readonly string[] {
  const issues: string[] = [];
  if (domain === 'render' && animation.events?.some((event) => event.gameplay)) issues.push('Gameplay animation events require the physics domain');
  return issues;
}

export class AnimationWorkbenchState {
  private readonly clock: AnimationClock;
  private animation?: UniversalAnimationDocument;
  private playingValue = false;

  constructor(onEvent: (event: UniversalAnimationEvent) => void = () => undefined) {
    this.clock = new AnimationClock({ onEvent });
  }

  get frame(): number { return this.clock.state.timelineFrame; }
  get playing(): boolean { return this.playingValue; }
  play(animation: UniversalAnimationDocument): void { this.animation = animation; this.playingValue = true; this.clock.start(animation, animation.events ?? []); }
  pause(): void { this.playingValue = false; this.clock.pause(); }
  resume(): void { if (!this.animation) return; this.playingValue = true; this.clock.resume(); }
  update(milliseconds: number): void { if (this.playingValue) this.clock.update(milliseconds); }
  seek(frame: number): void { this.playingValue = false; this.clock.pause(); this.clock.scrub(frame); }
  stop(): void { this.playingValue = false; this.animation = undefined; this.clock.stop(); }
}
