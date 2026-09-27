import type { RuntimeNodeId } from '../../../content/scenes/identifiers';
import type { Node } from '../Node';

export type PhysicsOwnerKind = 'character-body' | 'static-body' | 'area';

export interface ShapeContact {
  readonly observerShapeId: RuntimeNodeId;
  readonly otherShapeId: RuntimeNodeId;
}

export interface PhysicsContact {
  readonly observerId: RuntimeNodeId;
  readonly otherId: RuntimeNodeId;
  readonly observerKind: PhysicsOwnerKind;
  readonly otherKind: PhysicsOwnerKind;
  readonly observer?: Node;
  readonly other?: Node;
  readonly shapes: readonly ShapeContact[];
}

export interface BlockingContact {
  readonly colliderId: RuntimeNodeId;
  readonly collider?: Node;
  readonly normal: Readonly<{ x: number; y: number }>;
  readonly position?: Readonly<{ x: number; y: number }>;
}

export function collisionMembershipAccepts(mask: number, layer: number): boolean {
  return ((mask >>> 0) & (layer >>> 0)) !== 0;
}

/** Collision membership of one blocking body, as the blocking rule sees it. */
export interface BlockingMembership {
  readonly collisionLayer: number;
  readonly collisionMask: number;
  /** Static bodies never move, so their mask never matters. */
  readonly isStatic: boolean;
}

/**
 * Godot blocking semantics, in one place:
 * - a moving body is blocked by another body when the mover's mask contains
 *   the other body's layer;
 * - a static body's mask is irrelevant (it never moves, so it is never "blocked");
 * - two static bodies never interact;
 * - two moving bodies interact when EITHER mask contains the other's layer,
 *   because Arcade separation is symmetric (it pushes both bodies).
 */
export function blockingPairAccepts(first: BlockingMembership, second: BlockingMembership): boolean {
  if (first.isStatic && second.isStatic) return false;
  const firstBlockedBySecond = !first.isStatic && collisionMembershipAccepts(first.collisionMask, second.collisionLayer);
  const secondBlockedByFirst = !second.isStatic && collisionMembershipAccepts(second.collisionMask, first.collisionLayer);
  return firstBlockedBySecond || secondBlockedByFirst;
}

export function validateCollisionBits(value: number, label: string): number {
  if (!Number.isInteger(value) || value < 0 || value > 0xffff_ffff) {
    throw new Error(`${label} must be an unsigned 32-bit integer`);
  }
  return value >>> 0;
}
