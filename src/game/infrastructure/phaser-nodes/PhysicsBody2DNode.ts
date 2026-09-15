import type Phaser from 'phaser';

import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import { Node2D, type Node2DOptions, type Transform2D, type Vector2 } from '../../runtime/scene/Node2D';
import type { ContactParticipant } from '../../runtime/scene/physics/ContactRouter';
import { validateCollisionBits, type BlockingContact, type PhysicsContact, type PhysicsOwnerKind } from '../../runtime/scene/physics/PhysicsContact';
import { sensorShapeBounds, type SensorBounds, type SensorShape } from '../../runtime/scene/physics/SensorGeometry';
import type { PhaserBlockingParticipant, PhaserNodeContext } from '../scenes/PhaserNodeContext';
import type { CollisionShape2DNode, CollisionShapeOwner } from './CollisionShape2DNode';

export interface PhysicsBody2DNodeOptions extends Node2DOptions {
  readonly context: PhaserNodeContext;
  readonly collisionLayer?: number;
  readonly collisionMask?: number;
  readonly collisionEnabled?: boolean;
}

type ArcadeBody = Phaser.Physics.Arcade.Body | Phaser.Physics.Arcade.StaticBody;
type PhysicsGameObject = Phaser.GameObjects.Zone | Phaser.Physics.Arcade.Sprite;

function centers(shape: SensorShape): Vector2 {
  if (shape.shape === 'rectangle') return { x: shape.x + shape.width / 2, y: shape.y + shape.height / 2 };
  if (shape.shape === 'circle' || shape.shape === 'ellipse') return { x: shape.centerX, y: shape.centerY };
  return { x: shape.originX, y: shape.originY };
}

export abstract class PhysicsBody2DNode extends Node2D implements CollisionShapeOwner, ContactParticipant, PhaserBlockingParticipant {
  private readonly shapes = new Set<CollisionShape2DNode>();
  private physicsGameObject?: PhysicsGameObject;
  private currentBlockingContacts: BlockingContact[] = [];
  private completedBlockingContacts: readonly BlockingContact[] = [];
  private configuredShapeSignature?: string;
  private centerOffset: Vector2 = { x: 0, y: 0 };
  private initialized = false;
  private _collisionLayer: number;
  private _collisionMask: number;
  private _collisionEnabled: boolean;

  abstract readonly kind: PhysicsOwnerKind;
  abstract readonly isStaticBody: boolean;

  constructor(protected readonly bodyOptions: PhysicsBody2DNodeOptions) {
    super(bodyOptions);
    this._collisionLayer = validateCollisionBits(bodyOptions.collisionLayer ?? 1, 'Collision layer');
    this._collisionMask = validateCollisionBits(bodyOptions.collisionMask ?? 0xffff_ffff, 'Collision mask');
    this._collisionEnabled = bodyOptions.collisionEnabled ?? true;
  }

  get collisionLayer(): number { return this._collisionLayer; }
  set collisionLayer(value: number) { this._collisionLayer = validateCollisionBits(value, 'Collision layer'); }
  get collisionMask(): number { return this._collisionMask; }
  set collisionMask(value: number) { this._collisionMask = validateCollisionBits(value, 'Collision mask'); }
  get collisionEnabled(): boolean { return this._collisionEnabled; }
  set collisionEnabled(value: boolean) {
    this._collisionEnabled = value;
    const body = this.body();
    if (!value) { if (body) body.enable = false; this.currentBlockingContacts = []; this.completedBlockingContacts = []; }
  }
  get blockingContacts(): readonly BlockingContact[] { return this.completedBlockingContacts; }
  get physicsObject(): Phaser.GameObjects.GameObject {
    if (!this.physicsGameObject) throw new Error(`Physics body '${this.name}' is outside the tree`);
    return this.physicsGameObject;
  }
  get blockingActive(): boolean { return this.contactActive; }
  get node(): Node2D { return this; }
  get monitoring(): boolean { return false; }
  get monitorable(): boolean { return this._collisionEnabled; }
  get contactActive(): boolean { return this.is_inside_tree() && this._collisionEnabled && !this.is_freed(); }

  override _enter_tree(): void {
    const physicsGameObject = this.createPhysicsGameObject().setName(this.runtimeId).setVisible(false);
    if (!physicsGameObject.body) {
      this.bodyOptions.context.scene.physics.add.existing(physicsGameObject, this.isStaticBody);
    }
    this.physicsGameObject = physicsGameObject;
    const body = physicsGameObject.body as ArcadeBody | null;
    if (body) body.enable = false;
    this.entryDisposables.add(() => {
      physicsGameObject.destroy();
      if (this.physicsGameObject === physicsGameObject) this.physicsGameObject = undefined;
    });
    this.entryDisposables.add(this.bodyOptions.context.registerContactParticipant(this, body ?? undefined));
    this.entryDisposables.add(this.bodyOptions.context.registerBlockingParticipant(this));
    this.entryDisposables.add(this.bodyOptions.context.registerCallback('physics-sync', () => this.synchronizeToBackend()));
    this.entryDisposables.add(this.bodyOptions.context.registerCallback('physics-readback', () => this.readAuthoritativeState()));
  }

  override _ready(): void { this.synchronizeToBackend(); }

  registerCollisionShape(shape: CollisionShape2DNode): () => void {
    this.shapes.add(shape);
    let active = true;
    return () => { if (!active) return; active = false; this.shapes.delete(shape); this.configuredShapeSignature = undefined; };
  }

  contactShapes(): readonly SensorShape[] {
    if (!this.contactActive) return [];
    return [this.enabledShape().worldShape()];
  }

  contactBounds(): SensorBounds | undefined {
    const shape = this.contactShapes()[0];
    return shape ? sensorShapeBounds(shape) : undefined;
  }

  contactEntered(_contact: PhysicsContact): void {}
  contactExited(_contact: PhysicsContact): void {}
  beginBlockingStep(): void { this.currentBlockingContacts = []; }
  recordBlockingContact(contact: BlockingContact): void {
    if (this.currentBlockingContacts.some((entry) => entry.colliderId === contact.colliderId)) return;
    this.currentBlockingContacts.push(contact);
  }

  protected body(): ArcadeBody | undefined { return this.physicsGameObject?.body as ArcadeBody | undefined; }
  protected createPhysicsGameObject(): PhysicsGameObject {
    return this.bodyOptions.context.scene.add.zone(0, 0, 1, 1);
  }
  protected beforeSynchronizeLogicalState(): void {}
  protected onSynchronizeDynamicBody(_body: ArcadeBody): void {}
  protected onReadDynamicBody(_body: ArcadeBody): void {}
  protected abstract duplicateBody(runtimeId: RuntimeNodeId): PhysicsBody2DNode;
  protected override _duplicateSelf(runtimeId: RuntimeNodeId): PhysicsBody2DNode { return this.duplicateBody(runtimeId); }

  private enabledShape(): CollisionShape2DNode {
    const enabled = [...this.shapes].filter((shape) => !shape.disabled);
    if (enabled.length !== 1) throw new Error(`${this.constructor.name} '${this.name}' requires exactly one enabled CollisionShape2D while collision is enabled`);
    const shape = enabled[0];
    const geometry = shape.worldShape();
    if (geometry.shape === 'sector') throw new Error(`${this.constructor.name} '${this.name}' only supports rectangle, circle, or ellipse blocking geometry`);
    return shape;
  }

  private synchronizeToBackend(): void {
    const body = this.body();
    const physicsGameObject = this.physicsGameObject;
    if (!body || !physicsGameObject) return;
    if (!this._collisionEnabled) { body.enable = false; return; }
    this.beforeSynchronizeLogicalState();
    const shape = this.enabledShape().worldShape();
    if (shape.shape === 'sector') throw new Error(`${this.constructor.name} '${this.name}' only supports rectangle, circle, or ellipse blocking geometry`);
    const anchor = this.get_global_transform().position;
    const center = centers(shape);
    this.centerOffset = { x: center.x - anchor.x, y: center.y - anchor.y };
    const signature = shape.shape === 'rectangle'
      ? `rectangle:${shape.width}:${shape.height}`
      : shape.shape === 'ellipse'
        ? `ellipse:${shape.radiusX}:${shape.radiusY}`
        : `circle:${shape.radius}`;
    if (signature !== this.configuredShapeSignature) {
      if (shape.shape === 'rectangle') {
        physicsGameObject.setSize(shape.width, shape.height);
        body.setSize(shape.width, shape.height, true);
      } else if (shape.shape === 'ellipse') {
        const width = shape.radiusX * 2;
        const height = shape.radiusY * 2;
        // Arcade has no ellipse body; match the legacy runtime's conservative bounds contract.
        physicsGameObject.setSize(width, height);
        body.setSize(width, height, true);
      } else if (shape.shape === 'circle') {
        physicsGameObject.setSize(shape.radius * 2, shape.radius * 2);
        body.setCircle(shape.radius, 0, 0);
      }
      this.configuredShapeSignature = signature;
    }
    const bodyCenter = body.center;
    if (!this.initialized || Math.abs(bodyCenter.x - center.x) > 1e-7 || Math.abs(bodyCenter.y - center.y) > 1e-7) {
      physicsGameObject.setPosition(center.x, center.y);
      if (this.isStaticBody) (body as Phaser.Physics.Arcade.StaticBody).updateFromGameObject();
      else (body as Phaser.Physics.Arcade.Body).reset(center.x, center.y);
      this.initialized = true;
    }
    // Keep the backend object's public transform at the authored node anchor.
    // Arcade owns its body center independently during the manual physics step.
    physicsGameObject.setPosition(anchor.x, anchor.y);
    body.enable = true;
    this.onSynchronizeDynamicBody(body);
  }

  private readAuthoritativeState(): void {
    const body = this.body();
    if (!body || !body.enable || !this.initialized) return;
    const transform = this.get_global_transform();
    const next: Transform2D = { ...transform, position: { x: body.center.x - this.centerOffset.x, y: body.center.y - this.centerOffset.y } };
    this.set_global_transform(next);
    this.physicsGameObject?.setPosition(next.position.x, next.position.y);
    this.onReadDynamicBody(body);
    this.completedBlockingContacts = this.currentBlockingContacts.map((contact) => ({ ...contact }));
  }
}
