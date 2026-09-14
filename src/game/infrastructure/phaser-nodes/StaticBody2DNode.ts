import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import { PhysicsBody2DNode } from './PhysicsBody2DNode';

export class StaticBody2DNode extends PhysicsBody2DNode {
  readonly kind = 'static-body' as const;
  readonly isStaticBody = true;

  protected override duplicateBody(runtimeId: RuntimeNodeId): StaticBody2DNode {
    return new StaticBody2DNode({ ...this.bodyOptions, runtimeId, name: this.name, position: this.position, rotation: this.rotation, scale: this.scale, visible: this.visible, collisionLayer: this.collisionLayer, collisionMask: this.collisionMask, collisionEnabled: this.collisionEnabled });
  }
}
