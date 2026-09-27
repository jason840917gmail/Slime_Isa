import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import { Node, type NodeOptions } from './Node';

export interface Vector2 {
  readonly x: number;
  readonly y: number;
}

export interface Transform2D {
  readonly position: Vector2;
  readonly rotation: number;
  readonly scale: Vector2;
}

export interface Node2DOptions extends NodeOptions {
  readonly position?: Vector2;
  readonly rotation?: number;
  readonly scale?: Vector2;
  readonly visible?: boolean;
  /**
   * Local ground point used for depth sorting. A node with a depth anchor is a
   * depth source for descendants rendered with parent-relative depth.
   */
  readonly depthAnchor?: Vector2;
}

function finiteVector(value: Vector2, label: string): void {
  if (!Number.isFinite(value.x) || !Number.isFinite(value.y)) throw new Error(`${label} must contain finite coordinates`);
}

function rotate(value: Vector2, radians: number): Vector2 {
  const cosine = Math.cos(radians);
  const sine = Math.sin(radians);
  return { x: value.x * cosine - value.y * sine, y: value.x * sine + value.y * cosine };
}

export class Node2D extends Node {
  private localPosition: Vector2;
  private localRotation: number;
  private localScale: Vector2;
  private localTransformRevision = 0;
  private worldTransformRevision = 0;
  private cachedWorldTransform?: Transform2D;
  private cachedLocalRevision = -1;
  private cachedParent?: Node2D;
  private cachedParentRevision = -1;
  /**
   * Set when this node or an ancestor changed transform or ancestry since the
   * cached world transform was validated. A stale node's Node2D descendants are
   * always stale too, because reading any descendant revalidates its ancestors.
   */
  private worldTransformStale = true;
  private readonly localDepthAnchor?: Vector2;
  /**
   * Runtime-only absolute base depth. When set, this node is a depth source
   * whose descendants with relative depth draw at this depth plus their offset.
   */
  depthOverride?: number;
  visible: boolean;

  constructor(options: Node2DOptions) {
    super(options);
    this.localPosition = options.position ?? { x: 0, y: 0 };
    this.localRotation = options.rotation ?? 0;
    this.localScale = options.scale ?? { x: 1, y: 1 };
    this.visible = options.visible ?? true;
    if (options.depthAnchor) {
      finiteVector(options.depthAnchor, 'Depth anchor');
      this.localDepthAnchor = { ...options.depthAnchor };
    }
    finiteVector(this.localPosition, 'Position');
    finiteVector(this.localScale, 'Scale');
    if (this.localScale.x <= 0 || this.localScale.y <= 0) throw new Error('Scale must be positive');
    if (!Number.isFinite(this.localRotation)) throw new Error('Rotation must be finite');
  }

  get position(): Vector2 { return { ...this.localPosition }; }
  set position(value: Vector2) {
    finiteVector(value, 'Position');
    if (value.x === this.localPosition.x && value.y === this.localPosition.y) return;
    this.localPosition = { ...value };
    this.localTransformRevision += 1;
    this._invalidateGlobalTransformInternal();
  }
  get rotation(): number { return this.localRotation; }
  set rotation(value: number) {
    if (!Number.isFinite(value)) throw new Error('Rotation must be finite');
    if (value === this.localRotation) return;
    this.localRotation = value;
    this.localTransformRevision += 1;
    this._invalidateGlobalTransformInternal();
  }
  get scale(): Vector2 { return { ...this.localScale }; }
  set scale(value: Vector2) {
    finiteVector(value, 'Scale');
    if (value.x <= 0 || value.y <= 0) throw new Error('Scale must be positive');
    if (value.x === this.localScale.x && value.y === this.localScale.y) return;
    this.localScale = { ...value };
    this.localTransformRevision += 1;
    this._invalidateGlobalTransformInternal();
  }

  get depthAnchor(): Vector2 | undefined { return this.localDepthAnchor ? { ...this.localDepthAnchor } : undefined; }

  /** True when descendants with relative depth should anchor to this node. */
  get isDepthSource(): boolean {
    return this.localDepthAnchor !== undefined || this.depthOverride !== undefined;
  }

  /** World-space Y of this node's depth anchor, or its origin when it has none. */
  get_global_depth_anchor_y(): number {
    const transform = this.readWorldTransform();
    const anchor = this.localDepthAnchor;
    if (!anchor) return transform.position.y;
    const offset = rotate({ x: anchor.x * transform.scale.x, y: anchor.y * transform.scale.y }, transform.rotation);
    return transform.position.y + offset.y;
  }

  /** Nearest Node2D ancestor that is a depth source. */
  find_depth_source(): Node2D | undefined {
    let current = this.transformParent();
    while (current) {
      if (current.isDepthSource) return current;
      current = current.transformParent();
    }
    return undefined;
  }

  get_global_transform(): Transform2D {
    const transform = this.readWorldTransform();
    return {
      position: { ...transform.position },
      rotation: transform.rotation,
      scale: { ...transform.scale },
    };
  }

  /** Changes whenever this node or a transform ancestor changes. */
  get_global_transform_revision(): number {
    this.readWorldTransform();
    return this.worldTransformRevision;
  }

  /** @internal */
  override _invalidateGlobalTransformInternal(): void {
    if (this.worldTransformStale) return;
    this.worldTransformStale = true;
    super._invalidateGlobalTransformInternal();
  }

  private readWorldTransform(): Transform2D {
    if (!this.worldTransformStale && this.cachedWorldTransform) return this.cachedWorldTransform;
    this.worldTransformStale = false;
    const parent = this.transformParent();
    const parentTransform = parent?.readWorldTransform();
    const parentRevision = parent?.worldTransformRevision ?? 0;
    if (this.cachedWorldTransform
      && this.cachedLocalRevision === this.localTransformRevision
      && this.cachedParent === parent
      && this.cachedParentRevision === parentRevision) return this.cachedWorldTransform;
    if (!parentTransform) {
      this.cachedWorldTransform = {
        position: { ...this.localPosition },
        rotation: this.localRotation,
        scale: { ...this.localScale },
      };
    } else {
      const scaled = { x: this.localPosition.x * parentTransform.scale.x, y: this.localPosition.y * parentTransform.scale.y };
      const offset = rotate(scaled, parentTransform.rotation);
      this.cachedWorldTransform = {
        position: { x: parentTransform.position.x + offset.x, y: parentTransform.position.y + offset.y },
        rotation: parentTransform.rotation + this.localRotation,
        scale: { x: parentTransform.scale.x * this.localScale.x, y: parentTransform.scale.y * this.localScale.y },
      };
    }
    this.cachedLocalRevision = this.localTransformRevision;
    this.cachedParent = parent;
    this.cachedParentRevision = parentRevision;
    this.worldTransformRevision += 1;
    return this.cachedWorldTransform;
  }

  set_global_transform(transform: Transform2D): void {
    finiteVector(transform.position, 'Global position');
    finiteVector(transform.scale, 'Global scale');
    if (transform.scale.x <= 0 || transform.scale.y <= 0 || !Number.isFinite(transform.rotation)) throw new Error('Global transform is invalid');
    const parent = this.transformParent();
    if (!parent) {
      this.position = transform.position;
      this.rotation = transform.rotation;
      this.scale = transform.scale;
      return;
    }
    const parentTransform = parent.get_global_transform();
    const delta = rotate({ x: transform.position.x - parentTransform.position.x, y: transform.position.y - parentTransform.position.y }, -parentTransform.rotation);
    this.position = { x: delta.x / parentTransform.scale.x, y: delta.y / parentTransform.scale.y };
    this.rotation = transform.rotation - parentTransform.rotation;
    this.scale = { x: transform.scale.x / parentTransform.scale.x, y: transform.scale.y / parentTransform.scale.y };
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): Node {
    return new Node2D({ runtimeId, name: this.name, position: this.position, rotation: this.rotation, scale: this.scale, visible: this.visible, depthAnchor: this.depthAnchor });
  }

  private transformParent(): Node2D | undefined {
    let current = this.get_parent();
    while (current) {
      if (current instanceof Node2D) return current;
      current = current.get_parent();
    }
    return undefined;
  }
}
