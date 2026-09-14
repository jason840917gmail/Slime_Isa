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

export function validateCollisionBits(value: number, label: string): number {
  if (!Number.isInteger(value) || value < 0 || value > 0xffff_ffff) {
    throw new Error(`${label} must be an unsigned 32-bit integer`);
  }
  return value >>> 0;
}
