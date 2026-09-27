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

/**
 * The body's true geometric centre. Arcade's `body.center` uses the floored
 * `halfWidth`/`halfHeight`, which is half a pixel off for odd sizes and would
 * make every sync see a mismatch (and drift the node) for such bodies.
 */
function geometricCenter(body: ArcadeBody): Vector2 {
  return { x: body.position.x + body.width / 2, y: body.position.y + body.height / 2 };
}

/**
 * Places a dynamic body so its centre is exactly `center`. `Body.reset(x, y)`
 * puts the body's top-left at the game object's top-left and ignores the body
 * offset, so on its own it lands the body `offset` pixels away from the
 * requested point (teleports and spawns were off by about half a body).
 */
function placeDynamicBody(body: Phaser.Physics.Arcade.Body, center: Vector2): void {
  body.reset(center.x, center.y);
  const x = center.x - body.width / 2;
  const y = center.y - body.height / 2;
  const frames = body as unknown as Partial<Record<'position' | 'prev' | 'prevFrame' | 'autoFrame', { x: number; y: number }>>;
  for (const vector of [frames.position, frames.prev, frames.prevFrame, frames.autoFrame]) {
    if (vector) { vector.x = x; vector.y = y; }
  }
  if (typeof body.updateCenter === 'function') body.updateCenter();
}

export abstract class PhysicsBody2DNode extends Node2D implements CollisionShapeOwner, ContactParticipant, PhaserBlockingParticipant {
  private readonly shapes = new Set<CollisionShape2DNode>();
  private physicsGameObject?: PhysicsGameObject;
  private currentBlockingContacts: BlockingContact[] = [];
  private completedBlockingContacts: readonly BlockingContact[] = [];
  private configuredShapeSignature?: string;
  private staticSyncKey?: string;
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
  set collisionLayer(value: number) { this._collisionLayer = validateCollisionBits(value, 'Collision layer'); this.refreshBlockingMembership(); }
  get collisionMask(): number { return this._collisionMask; }
  set collisionMask(value: number) { this._collisionMask = validateCollisionBits(value, 'Collision mask'); this.refreshBlockingMembership(); }
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
    this.entryDisposables.add(this.bodyOptions.context.registerContactParticipant(this));
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

  private refreshBlockingMembership(): void {
    if (this.physicsGameObject) this.bodyOptions.context.refreshBlockingParticipant(this);
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
    let shape: CollisionShape2DNode | undefined;
    let enabledCount = 0;
    for (const candidate of this.shapes) if (!candidate.disabled) { shape = candidate; enabledCount += 1; }
    if (enabledCount !== 1 || !shape) throw new Error(`${this.constructor.name} '${this.name}' requires exactly one enabled CollisionShape2D while collision is enabled`);
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
    const shapeNode = this.enabledShape();
    // Static bodies never move on their own: only touch Arcade's static tree
    // when the body/shape world transform or the enabled shape changed.
    const staticSyncKey = this.isStaticBody
      ? `${shapeNode.runtimeId}:${shapeNode.get_global_transform_revision()}:${this.get_global_transform_revision()}`
      : undefined;
    if (staticSyncKey !== undefined && this.initialized && body.enable && staticSyncKey === this.staticSyncKey) return;
    const shape = shapeNode.worldShape();
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
    const bodyCenter = geometricCenter(body);
    if (!this.initialized || Math.abs(bodyCenter.x - center.x) > 1e-7 || Math.abs(bodyCenter.y - center.y) > 1e-7) {
      physicsGameObject.setPosition(center.x, center.y);
      if (this.isStaticBody) (body as Phaser.Physics.Arcade.StaticBody).updateFromGameObject();
      else placeDynamicBody(body as Phaser.Physics.Arcade.Body, center);
      this.initialized = true;
    }
    // Keep the backend object's public transform at the authored node anchor.
    // Arcade owns its body center independently during the manual physics step.
    physicsGameObject.setPosition(anchor.x, anchor.y);
    body.enable = true;
    this.staticSyncKey = staticSyncKey;
    this.onSynchronizeDynamicBody(body);
  }

  private readAuthoritativeState(): void {
    const body = this.body();
    if (!body || !body.enable || !this.initialized) return;
    if (this.isStaticBody) {
      // Arcade never moves a static body, so there is no authoritative
      // position to read back (and rewriting it would force a static resync).
      this.completedBlockingContacts = this.currentBlockingContacts.map((contact) => ({ ...contact }));
      return;
    }
    const transform = this.get_global_transform();
    const bodyCenter = geometricCenter(body);
    const next: Transform2D = { ...transform, position: { x: bodyCenter.x - this.centerOffset.x, y: bodyCenter.y - this.centerOffset.y } };
    this.set_global_transform(next);
    this.physicsGameObject?.setPosition(next.position.x, next.position.y);
    this.onReadDynamicBody(body);
    this.completedBlockingContacts = this.currentBlockingContacts.map((contact) => ({ ...contact }));
  }
}
