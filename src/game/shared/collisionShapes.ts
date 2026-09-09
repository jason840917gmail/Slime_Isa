/** Collision primitives supported by authored gameplay geometry. */
export type CollisionShape = 'rectangle' | 'circle' | 'ellipse';

export interface CollisionShapeDocument {
  readonly shape?: CollisionShape;
  readonly width: number;
  readonly height: number;
  readonly radius?: number;
  readonly radiusX?: number;
  readonly radiusY?: number;
  readonly centerOffsetX?: number;
  readonly centerOffsetY?: number;
}

export interface ArcadeBodyLike {
  setSize(width: number, height: number, center?: boolean): unknown;
  setCircle(radius: number, offsetX?: number, offsetY?: number): unknown;
  setOffset(offsetX: number, offsetY: number): unknown;
}

export interface ResolvedCollisionShape {
  readonly shape: CollisionShape;
  readonly centerX: number;
  readonly centerY: number;
  readonly width: number;
  readonly height: number;
  readonly radius?: number;
  readonly radiusX?: number;
  readonly radiusY?: number;
}

export interface EffectiveArcadeBodyBounds {
  readonly minX: number;
  readonly minY: number;
  readonly maxX: number;
  readonly maxY: number;
  readonly width: number;
  readonly height: number;
}

/** Conservative Arcade body bounds relative to the entity anchor. */
export function resolveEffectiveArcadeBodyBoundsRelativeToAnchor(document: CollisionShapeDocument): EffectiveArcadeBodyBounds {
  const resolved = resolveCollisionShapeDimensions(document);
  const centerOffsetX = document.centerOffsetX ?? 0;
  const centerOffsetY = document.centerOffsetY ?? 0;
  return { minX: centerOffsetX - resolved.width / 2, minY: centerOffsetY - resolved.height / 2, maxX: centerOffsetX + resolved.width / 2, maxY: centerOffsetY + resolved.height / 2, width: resolved.width, height: resolved.height };
}

export function normalizeCollisionShape(shape: CollisionShape | undefined): CollisionShape {
  return shape === 'circle' || shape === 'ellipse' ? shape : 'rectangle';
}

export function resolveCollisionShapeDimensions(document: CollisionShapeDocument): Pick<ResolvedCollisionShape, 'shape' | 'width' | 'height' | 'radius' | 'radiusX' | 'radiusY'> {
  const shape = normalizeCollisionShape(document.shape);
  if (shape === 'circle') {
    const radius = document.radius ?? Math.min(document.width, document.height) / 2;
    return { shape, width: radius * 2, height: radius * 2, radius };
  }
  if (shape === 'ellipse') {
    const radiusX = document.radiusX ?? document.width / 2;
    const radiusY = document.radiusY ?? document.height / 2;
    return { shape, width: radiusX * 2, height: radiusY * 2, radiusX, radiusY };
  }
  return { shape, width: document.width, height: document.height };
}

/**
 * Applies the closest Arcade Physics representation. Arcade has native
 * rectangles and circles; ellipses deliberately use their authored bounds
 * as a conservative rectangle for world/tile movement collision.
 */
export function applyArcadeBodyGeometry(
  body: ArcadeBodyLike,
  displayOriginX: number,
  displayOriginY: number,
  document: CollisionShapeDocument,
): CollisionShape {
  const resolved = resolveCollisionShapeDimensions(document);
  const bounds = resolveEffectiveArcadeBodyBoundsRelativeToAnchor(document);
  if (resolved.shape === 'circle') {
    const radius = resolved.radius ?? Math.min(document.width, document.height) / 2;
    body.setCircle(
      radius,
      displayOriginX + bounds.minX,
      displayOriginY + bounds.minY,
    );
    return resolved.shape;
  }

  body.setSize(bounds.width, bounds.height, false);
  body.setOffset(displayOriginX + bounds.minX, displayOriginY + bounds.minY);
  return resolved.shape;
}
