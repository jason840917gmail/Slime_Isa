import type Phaser from 'phaser';

import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { Vector2 } from '../../runtime/scene/Node2D';
import type { PhaserNodeContext } from '../scenes/PhaserNodeContext';
import { PhysicsBody2DNode, type PhysicsBody2DNodeOptions } from './PhysicsBody2DNode';

export interface CharacterBody2DNodeOptions extends PhysicsBody2DNodeOptions {
  readonly context: PhaserNodeContext;
  readonly velocity?: Vector2;
  /** Keep the body inside the physics world bounds (the loaded world's size). Defaults to true. */
  readonly collideWorldBounds?: boolean;
}

export class CharacterBody2DNode extends PhysicsBody2DNode {
  readonly kind = 'character-body' as const;
  readonly isStaticBody = false;
  private _velocity: Vector2;
  private queuedTeleport?: Vector2;
  collideWorldBounds: boolean;

  constructor(private readonly characterOptions: CharacterBody2DNodeOptions) {
    super(characterOptions);
    this._velocity = characterOptions.velocity ?? { x: 0, y: 0 };
    this.collideWorldBounds = characterOptions.collideWorldBounds ?? true;
    this.assertVelocity(this._velocity);
  }

  get velocity(): Vector2 { return { ...this._velocity }; }
  set velocity(value: Vector2) { this.assertVelocity(value); this._velocity = { ...value }; }

  queue_teleport(position: Vector2): void {
    this.assertVelocity(position);
    this.queuedTeleport = { ...position };
  }

  get physicsSprite(): Phaser.Physics.Arcade.Sprite {
    const object = this.physicsObject;
    if (!('setVelocity' in object)) throw new Error(`Character body '${this.runtimeId}' has no Arcade sprite backend.`);
    return object as Phaser.Physics.Arcade.Sprite;
  }

  protected override createPhysicsGameObject(): Phaser.Physics.Arcade.Sprite | Phaser.GameObjects.Zone {
    const physicsAdd = this.characterOptions.context.scene.physics.add as Phaser.Physics.Arcade.Factory & {
      sprite?: (x: number, y: number, texture: string) => Phaser.Physics.Arcade.Sprite;
    };
    return physicsAdd.sprite
      ? physicsAdd.sprite(0, 0, '__WHITE')
      : this.characterOptions.context.scene.add.zone(0, 0, 1, 1);
  }

  protected override beforeSynchronizeLogicalState(): void {
    if (!this.queuedTeleport) return;
    const transform = this.get_global_transform();
    this.set_global_transform({ ...transform, position: this.queuedTeleport });
    this.queuedTeleport = undefined;
  }

  protected override onSynchronizeDynamicBody(body: Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody): void {
    if (!('setVelocity' in body)) return;
    body.collideWorldBounds = this.collideWorldBounds;
    body.setVelocity(this._velocity.x, this._velocity.y);
  }

  protected override onReadDynamicBody(body: Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody): void {
    if ('velocity' in body) this._velocity = { x: body.velocity.x, y: body.velocity.y };
  }

  protected override duplicateBody(runtimeId: RuntimeNodeId): CharacterBody2DNode {
    return new CharacterBody2DNode({ ...this.characterOptions, runtimeId, name: this.name, position: this.position, rotation: this.rotation, scale: this.scale, visible: this.visible, velocity: this.velocity, collideWorldBounds: this.collideWorldBounds, collisionLayer: this.collisionLayer, collisionMask: this.collisionMask, collisionEnabled: this.collisionEnabled });
  }

  private assertVelocity(value: Vector2): void { if (!Number.isFinite(value.x) || !Number.isFinite(value.y)) throw new Error('Character velocity/teleport coordinates must be finite'); }
}
