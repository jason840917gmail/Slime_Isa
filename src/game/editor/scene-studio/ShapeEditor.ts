import type { CollisionShapeResourceDocument, CollisionShapeValue } from '../../content/scenes/resources/types';

export interface ShapeGuide {
  readonly authored: CollisionShapeValue;
  readonly effective: CollisionShapeValue;
  readonly differs: boolean;
}

export function validateCollisionShape(shape: CollisionShapeValue): readonly string[] {
  const positive = (value: number): boolean => Number.isFinite(value) && value > 0;
  if (shape.shape === 'rectangle') return positive(shape.width) && positive(shape.height) ? [] : ['Rectangle width and height must be positive'];
  if (shape.shape === 'circle') return positive(shape.radius) ? [] : ['Circle radius must be positive'];
  if (shape.shape === 'ellipse') return positive(shape.radiusX) && positive(shape.radiusY) ? [] : ['Ellipse radii must be positive'];
  const issues: string[] = [];
  if (!positive(shape.outerRadius)) issues.push('Sector outer radius must be positive');
  if (!Number.isFinite(shape.innerRadius) || shape.innerRadius < 0 || shape.innerRadius >= shape.outerRadius) issues.push('Sector inner radius must be non-negative and smaller than outer radius');
  if (!Number.isFinite(shape.arcWidthRad) || shape.arcWidthRad <= 0 || shape.arcWidthRad > Math.PI * 2) issues.push('Sector arc must be inside 0..2π');
  if (!Number.isFinite(shape.angleRad)) issues.push('Sector angle must be finite');
  return issues;
}

export function editCollisionShape(resource: CollisionShapeResourceDocument, value: CollisionShapeValue): CollisionShapeResourceDocument {
  const issues = validateCollisionShape(value);
  if (issues.length > 0) throw new Error(issues.join('\n'));
  return { ...resource, value: structuredClone(value) };
}

export function collisionShapeGuide(authored: CollisionShapeValue, effective: CollisionShapeValue = authored): ShapeGuide {
  return { authored, effective, differs: JSON.stringify(authored) !== JSON.stringify(effective) };
}
