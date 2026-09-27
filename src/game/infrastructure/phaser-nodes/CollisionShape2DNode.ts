import type { CollisionShapeResourceDocument, CollisionShapeValue } from '../../content/scenes/resources/types';
import type { ResourceId, RuntimeNodeId } from '../../content/scenes/identifiers';
import { Node2D, type Node2DOptions } from '../../runtime/scene/Node2D';
import type { SensorShape } from '../../runtime/scene/physics/SensorGeometry';
import type { PhaserNodeContext } from '../scenes/PhaserNodeContext';

export interface CollisionShapeOwner {
  registerCollisionShape(shape: CollisionShape2DNode): () => void;
}

export interface CollisionShape2DNodeOptions extends Node2DOptions {
  readonly context: PhaserNodeContext;
  readonly shape: ResourceId;
  readonly disabled?: boolean;
  readonly angleRad?: number;
}

interface CachedWorldShape {
  readonly transformRevision: number;
  readonly resource: CollisionShapeResourceDocument;
  readonly angleRad: number | undefined;
  readonly shape: SensorShape;
}

function shapeOwner(value: unknown): value is CollisionShapeOwner {
  return typeof (value as Partial<CollisionShapeOwner> | undefined)?.registerCollisionShape === 'function';
}

export class CollisionShape2DNode extends Node2D {
  private _disabled: boolean;
  private _angleRad?: number;
  private cachedWorldShape?: CachedWorldShape;

  constructor(private readonly shapeOptions: CollisionShape2DNodeOptions) {
    super(shapeOptions);
    this._disabled = shapeOptions.disabled ?? false;
    this._angleRad = shapeOptions.angleRad;
    if (this._angleRad !== undefined && !Number.isFinite(this._angleRad)) throw new Error('Collision shape angle must be finite');
  }

  get disabled(): boolean { return this._disabled; }
  set disabled(value: boolean) { this._disabled = value; }
  get angleRad(): number | undefined { return this._angleRad; }
  set angleRad(value: number | undefined) { if (value !== undefined && !Number.isFinite(value)) throw new Error('Collision shape angle must be finite'); this._angleRad = value; }

  override _enter_tree(): void {
    const parent = this.get_parent();
    if (!shapeOwner(parent)) throw new Error(`CollisionShape2D '${this.name}' requires a PhysicsBody2D or Area2D parent`);
    this.resource();
    this.entryDisposables.add(parent.registerCollisionShape(this));
  }

  /**
   * World-space geometry, recomputed only when this node's global transform
   * revision (which covers every ancestor), backing resource, or angle changes.
   * Physics queries this for every participant each fixed step.
   */
  worldShape(): SensorShape {
    const resource = this.resource();
    const transformRevision = this.get_global_transform_revision();
    const cached = this.cachedWorldShape;
    if (cached && cached.transformRevision === transformRevision && cached.resource === resource && cached.angleRad === this._angleRad) return cached.shape;
    const shape = this.computeWorldShape(resource.value);
    this.cachedWorldShape = { transformRevision, resource, angleRad: this._angleRad, shape };
    return shape;
  }

  private computeWorldShape(geometry: CollisionShapeValue): SensorShape {
    const transform = this.get_global_transform();
    this.validateTransform(geometry);
    if (geometry.shape === 'rectangle') return {
      shapeId: this.runtimeId, shape: 'rectangle', x: transform.position.x - geometry.width * transform.scale.x / 2,
      y: transform.position.y - geometry.height * transform.scale.y / 2, width: geometry.width * transform.scale.x, height: geometry.height * transform.scale.y,
    };
    if (geometry.shape === 'circle') return { shapeId: this.runtimeId, shape: 'circle', centerX: transform.position.x, centerY: transform.position.y, radius: geometry.radius * transform.scale.x };
    if (geometry.shape === 'ellipse') return { shapeId: this.runtimeId, shape: 'ellipse', centerX: transform.position.x, centerY: transform.position.y, radiusX: geometry.radiusX * transform.scale.x, radiusY: geometry.radiusY * transform.scale.y };
    return {
      shapeId: this.runtimeId, shape: 'sector', originX: transform.position.x, originY: transform.position.y,
      angleRad: this._angleRad ?? geometry.angleRad, arcWidthRad: geometry.arcWidthRad,
      innerRadius: geometry.innerRadius * transform.scale.x, outerRadius: geometry.outerRadius * transform.scale.x,
    };
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): CollisionShape2DNode {
    return new CollisionShape2DNode({ ...this.shapeOptions, runtimeId, name: this.name, position: this.position, rotation: this.rotation, scale: this.scale, visible: this.visible, disabled: this.disabled, angleRad: this.angleRad });
  }

  private resource(): CollisionShapeResourceDocument {
    const resource = this.shapeOptions.context.resource(this.shapeOptions.shape);
    if (resource.kind !== 'collision-shape') throw new Error(`Resource '${resource.resourceId}' cannot back CollisionShape2D`);
    return resource;
  }

  private validateTransform(geometry: CollisionShapeValue): void {
    let current: Node2D | undefined = this;
    while (current) {
      if (Math.abs(current.rotation) > 1e-9) throw new Error(`Collision shape '${this.name}' does not support rotated node or ancestor transforms`);
      const parent = current.get_parent();
      current = parent instanceof Node2D ? parent : undefined;
    }
    const scale = this.get_global_transform().scale;
    if (scale.x <= 0 || scale.y <= 0) throw new Error(`Collision shape '${this.name}' requires positive world scale`);
    if ((geometry.shape === 'circle' || geometry.shape === 'sector') && Math.abs(scale.x - scale.y) > 1e-9) {
      throw new Error(`${geometry.shape} collision shape '${this.name}' requires uniform world scale`);
    }
  }
}
