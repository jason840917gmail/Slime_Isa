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
  private contactGeometry: { readonly shapes: readonly SensorShape[]; readonly bounds: SensorBounds | undefined } = { shapes: [], bounds: undefined };
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
    this.entryDisposables.add(this.areaOptions.context.registerContactParticipant(this));
  }

  registerCollisionShape(shape: CollisionShape2DNode): () => void {
    this.shapes.add(shape);
    let active = true;
    return () => { if (!active) return; active = false; this.shapes.delete(shape); };
  }

  contactShapes(): readonly SensorShape[] { return this.resolveContactGeometry().shapes; }
  contactBounds(): SensorBounds | undefined { return this.resolveContactGeometry().bounds; }
  contactEntered(contact: PhysicsContact): void { (contact.otherKind === 'area' ? this.area_entered : this.body_entered).emit(contact); }
  contactExited(contact: PhysicsContact): void { (contact.otherKind === 'area' ? this.area_exited : this.body_exited).emit(contact); }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): Area2DNode {
    return new Area2DNode({ ...this.areaOptions, runtimeId, name: this.name, position: this.position, rotation: this.rotation, scale: this.scale, visible: this.visible, collisionLayer: this.collisionLayer, collisionMask: this.collisionMask, monitoring: this.monitoring, monitorable: this.monitorable });
  }

  /**
   * Reuses the previous shape list and union bounds while every enabled
   * shape still returns its identical cached world shape.
   */
  private resolveContactGeometry(): { readonly shapes: readonly SensorShape[]; readonly bounds: SensorBounds | undefined } {
    const shapes: SensorShape[] = [];
    if (this.contactActive) for (const shape of this.shapes) if (!shape.disabled) shapes.push(shape.worldShape());
    const previous = this.contactGeometry;
    if (shapes.length === previous.shapes.length && shapes.every((shape, index) => shape === previous.shapes[index])) return previous;
    this.contactGeometry = { shapes, bounds: unionSensorBounds(shapes) };
    return this.contactGeometry;
  }
}
