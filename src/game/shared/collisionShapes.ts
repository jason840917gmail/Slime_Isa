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
  if (resolved.shape === 'circle') {
    const radius = resolved.radius ?? Math.min(document.width, document.height) / 2;
    body.setCircle(
      radius,
      displayOriginX - radius + (document.centerOffsetX ?? 0),
      displayOriginY - radius + (document.centerOffsetY ?? 0),
    );
    return resolved.shape;
  }

  body.setSize(resolved.width, resolved.height, false);
  body.setOffset(
    displayOriginX - resolved.width / 2 + (document.centerOffsetX ?? 0),
    displayOriginY - resolved.height / 2 + (document.centerOffsetY ?? 0),
  );
  return resolved.shape;
}
