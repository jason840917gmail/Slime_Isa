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
  visible: boolean;

  constructor(options: Node2DOptions) {
    super(options);
    this.localPosition = options.position ?? { x: 0, y: 0 };
    this.localRotation = options.rotation ?? 0;
    this.localScale = options.scale ?? { x: 1, y: 1 };
    this.visible = options.visible ?? true;
    finiteVector(this.localPosition, 'Position');
    finiteVector(this.localScale, 'Scale');
    if (this.localScale.x <= 0 || this.localScale.y <= 0) throw new Error('Scale must be positive');
    if (!Number.isFinite(this.localRotation)) throw new Error('Rotation must be finite');
  }

  get position(): Vector2 { return { ...this.localPosition }; }
  set position(value: Vector2) { finiteVector(value, 'Position'); this.localPosition = { ...value }; }
  get rotation(): number { return this.localRotation; }
  set rotation(value: number) { if (!Number.isFinite(value)) throw new Error('Rotation must be finite'); this.localRotation = value; }
  get scale(): Vector2 { return { ...this.localScale }; }
  set scale(value: Vector2) { finiteVector(value, 'Scale'); if (value.x <= 0 || value.y <= 0) throw new Error('Scale must be positive'); this.localScale = { ...value }; }

  get_global_transform(): Transform2D {
    const parent = this.transformParent();
    if (!parent) return { position: this.position, rotation: this.rotation, scale: this.scale };
    const parentTransform = parent.get_global_transform();
    const scaled = { x: this.localPosition.x * parentTransform.scale.x, y: this.localPosition.y * parentTransform.scale.y };
    const offset = rotate(scaled, parentTransform.rotation);
    return {
      position: { x: parentTransform.position.x + offset.x, y: parentTransform.position.y + offset.y },
      rotation: parentTransform.rotation + this.localRotation,
      scale: { x: parentTransform.scale.x * this.localScale.x, y: parentTransform.scale.y * this.localScale.y },
    };
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
    return new Node2D({ runtimeId, name: this.name, position: this.position, rotation: this.rotation, scale: this.scale, visible: this.visible });
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
