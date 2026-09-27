import type { JsonValue, SceneNodeDocument } from '../../../content/scenes/types';
import type { UniversalAnimationDocument } from '../../../runtime/scene/animation/AnimationPlayerNode';
import { clipFrameCount, type FrameRemap } from './AnimationClipModel';

/**
 * Weapon hitbox timing lives in the WeaponScript's `attackPlans` (one plan per
 * attack direction naming its clip). The timeline shows those spans as lanes
 * so active frames are authored next to the keys they belong to.
 */

export interface WeaponHitboxSpan {
  readonly hitboxId: string;
  readonly from: number;
  readonly through: number;
  readonly damageMultiplier: number;
  readonly knockbackMultiplier: number;
}

export interface WeaponAttackLane {
  readonly direction: string;
  readonly hitboxId: string;
  /** Span indexes into the plan's hitboxSpans, with their frames. */
  readonly spans: readonly (WeaponHitboxSpan & { readonly index: number })[];
  /** True when a CollisionShape2D named `<direction>--<hitboxId>` exists. */
  readonly hasShape: boolean;
}

export type AttackPlans = Readonly<Record<string, JsonValue>>;

type PlanRecord = Readonly<Record<string, JsonValue>>;

function isRecord(value: JsonValue | undefined): value is PlanRecord {
  return value !== null && value !== undefined && typeof value === 'object' && !Array.isArray(value);
}

function spansOf(plan: PlanRecord): WeaponHitboxSpan[] {
  const spans = Array.isArray(plan.hitboxSpans) ? plan.hitboxSpans : [];
  return spans.flatMap((span) => {
    if (!isRecord(span) || typeof span.hitboxId !== 'string' || typeof span.from !== 'number' || typeof span.through !== 'number') return [];
    return [{
      hitboxId: span.hitboxId,
      from: span.from,
      through: span.through,
      damageMultiplier: typeof span.damageMultiplier === 'number' ? span.damageMultiplier : 1,
      knockbackMultiplier: typeof span.knockbackMultiplier === 'number' ? span.knockbackMultiplier : 1,
    }];
  });
}

function withSpans(plans: AttackPlans, direction: string, spans: readonly WeaponHitboxSpan[]): AttackPlans {
  const plan = plans[direction];
  if (!isRecord(plan)) throw new Error(`Unknown attack direction '${direction}'`);
  const ordered = [...spans].sort((left, right) => left.from - right.from || left.hitboxId.localeCompare(right.hitboxId));
  return { ...plans, [direction]: { ...plan, hitboxSpans: ordered as unknown as JsonValue } };
}

/** The ScriptNode that drives this AnimationPlayer's attacks, when it has attack plans. */
export function attackPlanOwner(nodes: readonly SceneNodeDocument[], playerNodeId: string): SceneNodeDocument | undefined {
  return nodes.find((node) => {
    const reference = node.properties.animation;
    return node.type === 'ScriptNode' && isRecord(reference) && reference.nodeId === playerNodeId && isRecord(node.properties.attackPlans);
  });
}

export function planDirectionsForClip(plans: AttackPlans, clipId: string): readonly string[] {
  return Object.entries(plans).filter(([, plan]) => isRecord(plan) && plan.animationId === clipId).map(([direction]) => direction);
}

/** Hitbox shape IDs available for a direction, from `<direction>--<id>` shape names. */
export function hitboxIdsForDirection(shapeNames: readonly string[], direction: string): readonly string[] {
  const prefix = `${direction}--`;
  return shapeNames.filter((name) => name.startsWith(prefix)).map((name) => name.slice(prefix.length)).filter(Boolean);
}

export function attackLanes(plans: AttackPlans, clipId: string, shapeNames: readonly string[]): readonly WeaponAttackLane[] {
  return planDirectionsForClip(plans, clipId).flatMap((direction) => {
    const plan = plans[direction] as PlanRecord;
    const spans = spansOf(plan).map((span, index) => ({ ...span, index }));
    const shapes = hitboxIdsForDirection(shapeNames, direction);
    const ids = [...new Set([...shapes, ...spans.map((span) => span.hitboxId)])];
    return ids.map((hitboxId) => ({ direction, hitboxId, spans: spans.filter((span) => span.hitboxId === hitboxId), hasShape: shapes.includes(hitboxId) }));
  });
}

/** Merges touching or overlapping spans of one hitbox, keeping the first span's multipliers. */
function canonicalize(spans: readonly WeaponHitboxSpan[]): WeaponHitboxSpan[] {
  const output: WeaponHitboxSpan[] = [];
  const byHitbox = new Map<string, WeaponHitboxSpan[]>();
  for (const span of spans) byHitbox.set(span.hitboxId, [...(byHitbox.get(span.hitboxId) ?? []), span]);
  for (const group of byHitbox.values()) {
    const sorted = [...group].sort((left, right) => left.from - right.from);
    let current: WeaponHitboxSpan | undefined;
    for (const span of sorted) {
      if (current && span.from <= current.through + 1 && span.damageMultiplier === current.damageMultiplier && span.knockbackMultiplier === current.knockbackMultiplier) {
        current = { ...current, through: Math.max(current.through, span.through) };
      } else {
        if (current) output.push(current);
        current = span;
      }
    }
    if (current) output.push(current);
  }
  return output;
}

/** Sets whether a hitbox is active on one frame, splitting or merging spans as needed. */
export function setHitboxFrame(plans: AttackPlans, direction: string, hitboxId: string, frame: number, active: boolean): AttackPlans {
  const plan = plans[direction];
  if (!isRecord(plan)) throw new Error(`Unknown attack direction '${direction}'`);
  if (!Number.isInteger(frame) || frame < 0) throw new Error('Hitbox frames are non-negative integers');
  const spans = spansOf(plan);
  const covering = spans.find((span) => span.hitboxId === hitboxId && span.from <= frame && frame <= span.through);
  if (active === Boolean(covering)) return plans;
  if (active) {
    const neighbour = spans.find((span) => span.hitboxId === hitboxId && (span.through === frame - 1 || span.from === frame + 1));
    const added: WeaponHitboxSpan = { hitboxId, from: frame, through: frame, damageMultiplier: neighbour?.damageMultiplier ?? 1, knockbackMultiplier: neighbour?.knockbackMultiplier ?? 1 };
    return withSpans(plans, direction, canonicalize([...spans, added]));
  }
  const remaining = spans.filter((span) => span !== covering);
  const split: WeaponHitboxSpan[] = [];
  if (covering!.from < frame) split.push({ ...covering!, through: frame - 1 });
  if (frame < covering!.through) split.push({ ...covering!, from: frame + 1 });
  return withSpans(plans, direction, [...remaining, ...split]);
}

export function hitboxActiveAt(plans: AttackPlans, direction: string, hitboxId: string, frame: number): boolean {
  const plan = plans[direction];
  return isRecord(plan) && spansOf(plan).some((span) => span.hitboxId === hitboxId && span.from <= frame && frame <= span.through);
}

export function updateHitboxSpan(plans: AttackPlans, direction: string, index: number, patch: Partial<Omit<WeaponHitboxSpan, 'hitboxId'>>, frameCount: number): AttackPlans {
  const plan = plans[direction];
  if (!isRecord(plan)) throw new Error(`Unknown attack direction '${direction}'`);
  const spans = spansOf(plan);
  const span = spans[index];
  if (!span) throw new Error(`Unknown hitbox span #${index}`);
  const next = { ...span, ...patch };
  if (!Number.isInteger(next.from) || !Number.isInteger(next.through) || next.from < 0 || next.through < next.from || next.through >= frameCount) {
    throw new Error(`Hitbox spans need 0 ≤ from ≤ through < ${frameCount}`);
  }
  if (!(next.damageMultiplier >= 0) || !(next.knockbackMultiplier >= 0)) throw new Error('Multipliers cannot be negative');
  return withSpans(plans, direction, spans.map((candidate, candidateIndex) => candidateIndex === index ? next : candidate));
}

export function removeHitboxSpan(plans: AttackPlans, direction: string, index: number): AttackPlans {
  const plan = plans[direction];
  if (!isRecord(plan)) throw new Error(`Unknown attack direction '${direction}'`);
  const spans = spansOf(plan);
  if (!spans[index]) throw new Error(`Unknown hitbox span #${index}`);
  return withSpans(plans, direction, spans.filter((_, candidate) => candidate !== index));
}

/**
 * Keeps every plan that plays `clipId` in step with the clip: duration and
 * frame rate are copied and spans follow the same frame remap as the keys.
 */
export function syncPlansWithClip(plans: AttackPlans, clipId: string, clip: UniversalAnimationDocument, remap: FrameRemap = (frame) => frame): AttackPlans {
  const frames = clipFrameCount(clip);
  let next = plans;
  for (const direction of planDirectionsForClip(plans, clipId)) {
    const plan = next[direction] as PlanRecord;
    const spans = spansOf(plan).flatMap((span) => {
      const from = remap(span.from);
      const through = remap(span.through);
      const start = from ?? through;
      const end = through ?? from;
      if (start === undefined || end === undefined) return [];
      return [{ ...span, from: Math.min(start, frames - 1), through: Math.min(Math.max(start, end), frames - 1) }];
    });
    next = { ...next, [direction]: { ...plan, durationMs: clip.durationSeconds * 1000, framesPerSecond: clip.framesPerSecond, hitboxSpans: canonicalize(spans) as unknown as JsonValue } };
  }
  return next;
}

/** Points plans at a renamed clip. */
export function renamePlanClip(plans: AttackPlans, from: string, to: string): AttackPlans {
  let next = plans;
  for (const direction of planDirectionsForClip(plans, from)) next = { ...next, [direction]: { ...(next[direction] as PlanRecord), animationId: to } };
  return next;
}
