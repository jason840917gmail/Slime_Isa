import type { Node } from '../../runtime/scene/Node';
import type { Node2D } from '../../runtime/scene/Node2D';
import type { SensorBounds } from '../../runtime/scene/physics/SensorGeometry';
import type { PlayerRuntimePorts } from './PlayerServicePorts';

export interface PlayerVelocityBody extends Node2D {
  velocity: Readonly<{ x: number; y: number }>;
  queue_teleport(position: Readonly<{ x: number; y: number }>): void;
}

interface BoundsNode extends Node {
  contactBounds(): SensorBounds | undefined;
}

export interface PlayerAnimationNode extends Node {
  readonly currentAnimation?: string;
  hasAnimation(animationId: string): boolean;
  play(animationId: string): void;
}

export class PlayerNodePorts implements PlayerRuntimePorts {
  constructor(
    private readonly body: PlayerVelocityBody,
    private readonly damageArea: BoundsNode,
    private readonly animation: PlayerAnimationNode,
    private readonly dodging: () => boolean,
  ) {}

  getPosition(): Readonly<{ x: number; y: number }> {
    return { ...this.body.get_global_transform().position };
  }

  getBodyBounds(): Readonly<{ x: number; y: number; width: number; height: number }> {
    const bounds = this.damageArea.contactBounds();
    if (!bounds) throw new Error(`Player damage area '${this.damageArea.runtimeId}' has no active collision bounds.`);
    return { x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height };
  }

  isDodging(): boolean {
    return this.dodging();
  }

  setVelocity(direction: Readonly<{ x: number; y: number }>, speed: number): void {
    const length = Math.hypot(direction.x, direction.y);
    if (!Number.isFinite(speed) || speed < 0) throw new Error('Player movement speed must be a finite non-negative number.');
    this.body.velocity = length > 0
      ? { x: direction.x / length * speed, y: direction.y / length * speed }
      : { x: 0, y: 0 };
  }

  stop(): void {
    this.body.velocity = { x: 0, y: 0 };
  }

  teleport(position: Readonly<{ x: number; y: number }>): void {
    if (!Number.isFinite(position.x) || !Number.isFinite(position.y)) throw new Error('Player teleport coordinates must be finite.');
    this.body.queue_teleport(position);
  }

  applyKnockback(direction: Readonly<{ x: number; y: number }>, strength: number, _durationMs: number): void {
    this.setVelocity(direction, strength);
  }

  play(animationId: string): boolean {
    if (!this.animation.hasAnimation(animationId)) return false;
    if (this.animation.currentAnimation !== animationId) this.animation.play(animationId);
    return true;
  }
}

export function requirePlayerVelocityBody(node: Node | undefined, ownerId: string): PlayerVelocityBody {
  if (!node || !node.has_runtime_capability('character-body') || !('velocity' in node) || !('queue_teleport' in node) || !('get_global_transform' in node)) {
    throw new Error(`PlayerScript '${ownerId}' requires a CharacterBody2D body reference.`);
  }
  return node as PlayerVelocityBody;
}

export function requirePlayerBoundsNode(node: Node | undefined, ownerId: string): BoundsNode {
  if (!node || !('contactBounds' in node)) throw new Error(`PlayerScript '${ownerId}' requires an Area2D damageArea reference.`);
  return node as BoundsNode;
}

export function requirePlayerAnimationNode(node: Node | undefined, ownerId: string): PlayerAnimationNode {
  if (!node || !('hasAnimation' in node) || !('play' in node)) {
    throw new Error(`PlayerScript '${ownerId}' requires an AnimationPlayer reference.`);
  }
  return node as PlayerAnimationNode;
}
