import type Phaser from 'phaser';

import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import { Node2D, type Node2DOptions } from '../../runtime/scene/Node2D';
import type { ContactParticipant } from '../../runtime/scene/physics/ContactRouter';
import { validateCollisionBits, type PhysicsContact } from '../../runtime/scene/physics/PhysicsContact';
import { unionSensorBounds, type SensorBounds, type SensorShape } from '../../runtime/scene/physics/SensorGeometry';
import { Signal } from '../../runtime/scene/Signal';
import type { PhaserNodeContext } from '../scenes/PhaserNodeContext';
import type { CollisionShape2DNode, CollisionShapeOwner } from './CollisionShape2DNode';

export interface Area2DNodeOptions extends Node2DOptions {
  readonly context: PhaserNodeContext;
  readonly collisionLayer?: number;
  readonly collisionMask?: number;
  readonly monitoring?: boolean;
  readonly monitorable?: boolean;
}

export class Area2DNode extends Node2D implements CollisionShapeOwner, ContactParticipant {
  readonly kind = 'area' as const;
  readonly body_entered: Signal<PhysicsContact>;
  readonly body_exited: Signal<PhysicsContact>;
  readonly area_entered: Signal<PhysicsContact>;
  readonly area_exited: Signal<PhysicsContact>;
  private readonly shapes = new Set<CollisionShape2DNode>();
  private zone?: Phaser.GameObjects.Zone;
  private broadphaseBounds?: SensorBounds;
  private _collisionLayer: number;
  private _collisionMask: number;
  private _monitoring: boolean;
  private _monitorable: boolean;

  constructor(private readonly areaOptions: Area2DNodeOptions) {
    super(areaOptions);
    this._collisionLayer = validateCollisionBits(areaOptions.collisionLayer ?? 1, 'Collision layer');
    this._collisionMask = validateCollisionBits(areaOptions.collisionMask ?? 0xffff_ffff, 'Collision mask');
    this._monitoring = areaOptions.monitoring ?? true;
    this._monitorable = areaOptions.monitorable ?? true;
    this.body_entered = this.createSignal('body_entered');
    this.body_exited = this.createSignal('body_exited');
    this.area_entered = this.createSignal('area_entered');
    this.area_exited = this.createSignal('area_exited');
  }

  get collisionLayer(): number { return this._collisionLayer; }
  set collisionLayer(value: number) { this._collisionLayer = validateCollisionBits(value, 'Collision layer'); }
  get collisionMask(): number { return this._collisionMask; }
  set collisionMask(value: number) { this._collisionMask = validateCollisionBits(value, 'Collision mask'); }
  get monitoring(): boolean { return this._monitoring; }
  set monitoring(value: boolean) { this._monitoring = value; }
  get monitorable(): boolean { return this._monitorable; }
  set monitorable(value: boolean) { this._monitorable = value; }
  get contactActive(): boolean { return this.is_inside_tree() && !this.is_freed() && (this._monitoring || this._monitorable); }
  get node(): Node2D { return this; }
  get currentContacts(): readonly PhysicsContact[] { return this.areaOptions.context.contactRouter.currentContacts(this.runtimeId); }

  override _enter_tree(): void {
    this.broadphaseBounds = undefined;
    const zone = this.areaOptions.context.scene.add.zone(0, 0, 1, 1).setName(this.runtimeId).setVisible(false);
    this.areaOptions.context.scene.physics.add.existing(zone, true);
    this.zone = zone;
    const body = zone.body as Phaser.Physics.Arcade.StaticBody | null;
    if (body) { body.enable = false; body.checkCollision.none = true; }
    this.entryDisposables.add(() => { zone.destroy(); if (this.zone === zone) this.zone = undefined; this.broadphaseBounds = undefined; });
    this.entryDisposables.add(this.areaOptions.context.registerContactParticipant(this, body ?? undefined));
    this.entryDisposables.add(this.areaOptions.context.registerCallback('contacts', () => this.synchronizeBroadphaseBody()));
  }

  registerCollisionShape(shape: CollisionShape2DNode): () => void {
    this.shapes.add(shape);
    let active = true;
    return () => { if (!active) return; active = false; this.shapes.delete(shape); };
  }

  contactShapes(): readonly SensorShape[] { return this.contactActive ? [...this.shapes].filter((shape) => !shape.disabled).map((shape) => shape.worldShape()) : []; }
  contactBounds(): SensorBounds | undefined { return unionSensorBounds(this.contactShapes()); }
  contactEntered(contact: PhysicsContact): void { (contact.otherKind === 'area' ? this.area_entered : this.body_entered).emit(contact); }
  contactExited(contact: PhysicsContact): void { (contact.otherKind === 'area' ? this.area_exited : this.body_exited).emit(contact); }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): Area2DNode {
    return new Area2DNode({ ...this.areaOptions, runtimeId, name: this.name, position: this.position, rotation: this.rotation, scale: this.scale, visible: this.visible, collisionLayer: this.collisionLayer, collisionMask: this.collisionMask, monitoring: this.monitoring, monitorable: this.monitorable });
  }

  private synchronizeBroadphaseBody(): void {
    const body = this.zone?.body as Phaser.Physics.Arcade.StaticBody | null | undefined;
    const bounds = this.contactBounds();
    if (!body || !this.zone || !bounds) { if (body) body.enable = false; this.broadphaseBounds = undefined; return; }
    const previous = this.broadphaseBounds;
    if (body.enable && previous && previous.x === bounds.x && previous.y === bounds.y
      && previous.width === bounds.width && previous.height === bounds.height) return;
    this.zone.setPosition(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2).setSize(bounds.width, bounds.height);
    body.setSize(bounds.width, bounds.height);
    body.updateFromGameObject();
    body.checkCollision.none = true;
    body.enable = true;
    this.broadphaseBounds = bounds;
  }
}
