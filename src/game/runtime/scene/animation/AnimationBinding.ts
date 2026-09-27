import type { PropertyDescriptor } from '../../../content/scenes/propertyDescriptors';
import type { JsonValue } from '../../../content/scenes/types';
import type { Node } from '../Node';

export type AnimationDomain = 'physics' | 'render';

/** Easing applied between a key and the next one (Godot's per-key transition). */
export type AnimationKeyTransition = 'linear' | 'ease-in' | 'ease-out' | 'ease-in-out';

/** Per-track override of the descriptor's interpolation; `linear` requires a numeric property. */
export type AnimationTrackInterpolation = 'nearest' | 'linear';

export const ANIMATION_KEY_TRANSITIONS: readonly AnimationKeyTransition[] = ['linear', 'ease-in', 'ease-out', 'ease-in-out'];

export interface AnimationPropertyKey {
  readonly at: number;
  readonly value: JsonValue;
  readonly transition?: AnimationKeyTransition;
}

const writers = new WeakMap<Node, Map<string, object>>();

function clone<T>(value: T): T { return structuredClone(value); }

function normalizeValue(value: JsonValue, descriptor: PropertyDescriptor): unknown {
  if (descriptor.value.kind === 'vector2' && Array.isArray(value) && value.length === 2) return { x: Number(value[0]), y: Number(value[1]) };
  return clone(value);
}

export function easeAnimationRatio(ratio: number, transition: AnimationKeyTransition | undefined): number {
  switch (transition) {
    case 'ease-in': return ratio * ratio;
    case 'ease-out': return 1 - (1 - ratio) * (1 - ratio);
    case 'ease-in-out': return ratio < 0.5 ? 2 * ratio * ratio : 1 - (-2 * ratio + 2) ** 2 / 2;
    default: return ratio;
  }
}

function interpolate(left: unknown, right: unknown, ratio: number): unknown {
  if (typeof left === 'number' && typeof right === 'number') return left + (right - left) * ratio;
  if (left !== null && right !== null && typeof left === 'object' && typeof right === 'object') {
    const a = left as Readonly<Record<string, unknown>>;
    const b = right as Readonly<Record<string, unknown>>;
    if (typeof a.x === 'number' && typeof a.y === 'number' && typeof b.x === 'number' && typeof b.y === 'number') {
      return { x: a.x + (b.x - a.x) * ratio, y: a.y + (b.y - a.y) * ratio };
    }
  }
  throw new Error('Numeric animation interpolation requires numbers or Vector2 values');
}

/** Resolves the effective interpolation of a track, rejecting linear blends of step-only properties. */
export function trackInterpolation(descriptor: PropertyDescriptor, override: AnimationTrackInterpolation | undefined): AnimationTrackInterpolation {
  const numeric = descriptor.animation?.interpolation === 'numeric';
  if (override === 'linear' && !numeric) throw new Error(`Property '${descriptor.key}' only supports nearest interpolation`);
  return override ?? (numeric ? 'linear' : 'nearest');
}

export class AnimationBinding {
  private owner?: object;
  private baseline?: unknown;

  constructor(
    readonly target: Node,
    readonly property: string,
    readonly descriptor: PropertyDescriptor,
  ) {
    if (descriptor.key !== property) throw new Error(`Animation descriptor '${descriptor.key}' does not match property '${property}'`);
    if (!descriptor.animation) throw new Error(`Property '${property}' is not animatable`);
    if (!(property in target)) throw new Error(`Animation target '${target.name}' has no property '${property}'`);
  }

  acquire(owner: object, domain: AnimationDomain): void {
    if (!this.descriptor.animation?.domains.includes(domain)) throw new Error(`Property '${this.property}' cannot animate in the ${domain} domain`);
    const targetWriters = writers.get(this.target) ?? new Map<string, object>();
    const current = targetWriters.get(this.property);
    if (current) throw new Error(`Property '${this.target.get_path()}.${this.property}' already has an active animation writer`);
    this.baseline = clone((this.target as unknown as Record<string, unknown>)[this.property]);
    targetWriters.set(this.property, owner);
    writers.set(this.target, targetWriters);
    this.owner = owner;
  }

  apply(frame: number, keys: readonly AnimationPropertyKey[], interpolation?: AnimationTrackInterpolation): void {
    if (!this.owner || keys.length === 0) return;
    const sorted = [...keys].sort((left, right) => left.at - right.at);
    let left = sorted[0];
    let right = sorted.at(-1) ?? left;
    for (const key of sorted) {
      if (key.at <= frame) left = key;
      if (key.at >= frame) { right = key; break; }
    }
    const leftValue = normalizeValue(left.value, this.descriptor);
    const value = trackInterpolation(this.descriptor, interpolation) === 'linear' && right.at > left.at
      ? interpolate(leftValue, normalizeValue(right.value, this.descriptor), easeAnimationRatio((frame - left.at) / (right.at - left.at), left.transition))
      : leftValue;
    (this.target as unknown as Record<string, unknown>)[this.property] = value;
  }

  release(owner: object, restoreBaseline: boolean): void {
    if (this.owner !== owner) return;
    const targetWriters = writers.get(this.target);
    if (targetWriters?.get(this.property) !== owner) return;
    if (restoreBaseline) (this.target as unknown as Record<string, unknown>)[this.property] = clone(this.baseline);
    targetWriters.delete(this.property);
    if (targetWriters.size === 0) writers.delete(this.target);
    this.owner = undefined;
    this.baseline = undefined;
  }
}
