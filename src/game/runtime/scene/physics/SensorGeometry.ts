import { attackIntersectsCombatBody, type CombatAttackGeometrySource, type CombatBodyGeometry } from '../../../combat/CombatBodyGeometry';
import type { RuntimeNodeId } from '../../../content/scenes/identifiers';

export interface SensorBounds {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

interface SensorShapeBase {
  readonly shapeId: RuntimeNodeId;
}

export interface RectangleSensorShape extends SensorShapeBase, SensorBounds {
  readonly shape: 'rectangle';
}

export interface CircleSensorShape extends SensorShapeBase {
  readonly shape: 'circle';
  readonly centerX: number;
  readonly centerY: number;
  readonly radius: number;
}

export interface EllipseSensorShape extends SensorShapeBase {
  readonly shape: 'ellipse';
  readonly centerX: number;
  readonly centerY: number;
  readonly radiusX: number;
  readonly radiusY: number;
}

export interface SectorSensorShape extends SensorShapeBase {
  readonly shape: 'sector';
  readonly originX: number;
  readonly originY: number;
  readonly angleRad: number;
  readonly arcWidthRad: number;
  readonly innerRadius: number;
  readonly outerRadius: number;
}

export type SensorShape = RectangleSensorShape | CircleSensorShape | EllipseSensorShape | SectorSensorShape;

const EPSILON = 1e-9;
const CURVE_SEGMENTS = 96;

function finite(...values: readonly number[]): boolean { return values.every(Number.isFinite); }
function squaredDistance(ax: number, ay: number, bx: number, by: number): number { const x = ax - bx; const y = ay - by; return x * x + y * y; }
function clamp(value: number, minimum: number, maximum: number): number { return Math.max(minimum, Math.min(maximum, value)); }

export function validateSensorShape(shape: SensorShape): void {
  if (shape.shape === 'rectangle') {
    if (!finite(shape.x, shape.y, shape.width, shape.height) || shape.width <= 0 || shape.height <= 0) throw new Error(`Rectangle shape '${shape.shapeId}' requires finite positive dimensions`);
  } else if (shape.shape === 'circle') {
    if (!finite(shape.centerX, shape.centerY, shape.radius) || shape.radius <= 0) throw new Error(`Circle shape '${shape.shapeId}' requires a finite positive radius`);
  } else if (shape.shape === 'ellipse') {
    if (!finite(shape.centerX, shape.centerY, shape.radiusX, shape.radiusY) || shape.radiusX <= 0 || shape.radiusY <= 0) throw new Error(`Ellipse shape '${shape.shapeId}' requires finite positive radii`);
  } else if (!finite(shape.originX, shape.originY, shape.angleRad, shape.arcWidthRad, shape.innerRadius, shape.outerRadius)
    || shape.arcWidthRad <= 0 || shape.arcWidthRad > Math.PI * 2 || shape.innerRadius < 0 || shape.innerRadius >= shape.outerRadius) {
    throw new Error(`Sector shape '${shape.shapeId}' requires finite angle/radii, 0 < arc <= 2π, and 0 <= inner < outer`);
  }
}

export function sensorShapeBounds(shape: SensorShape): SensorBounds {
  validateSensorShape(shape);
  if (shape.shape === 'rectangle') return { x: shape.x, y: shape.y, width: shape.width, height: shape.height };
  if (shape.shape === 'circle') return { x: shape.centerX - shape.radius, y: shape.centerY - shape.radius, width: shape.radius * 2, height: shape.radius * 2 };
  if (shape.shape === 'ellipse') return { x: shape.centerX - shape.radiusX, y: shape.centerY - shape.radiusY, width: shape.radiusX * 2, height: shape.radiusY * 2 };
  return { x: shape.originX - shape.outerRadius, y: shape.originY - shape.outerRadius, width: shape.outerRadius * 2, height: shape.outerRadius * 2 };
}

export function unionSensorBounds(shapes: readonly SensorShape[]): SensorBounds | undefined {
  if (shapes.length === 0) return undefined;
  const bounds = shapes.map(sensorShapeBounds);
  const minX = Math.min(...bounds.map((entry) => entry.x));
  const minY = Math.min(...bounds.map((entry) => entry.y));
  const maxX = Math.max(...bounds.map((entry) => entry.x + entry.width));
  const maxY = Math.max(...bounds.map((entry) => entry.y + entry.height));
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

export function sensorBoundsIntersect(first: SensorBounds, second: SensorBounds): boolean {
  return first.x <= second.x + second.width + EPSILON && first.x + first.width + EPSILON >= second.x
    && first.y <= second.y + second.height + EPSILON && first.y + first.height + EPSILON >= second.y;
}

function bodyGeometry(shape: RectangleSensorShape | CircleSensorShape): CombatBodyGeometry {
  return shape.shape === 'rectangle'
    ? { shape: 'rectangle', x: shape.x, y: shape.y, width: shape.width, height: shape.height }
    : { shape: 'circle', x: shape.centerX - shape.radius, y: shape.centerY - shape.radius, width: shape.radius * 2, height: shape.radius * 2, centerX: shape.centerX, centerY: shape.centerY, radius: shape.radius };
}

function attackGeometry(shape: SensorShape): CombatAttackGeometrySource {
  if (shape.shape === 'rectangle') return { shape: 'rect', x: shape.x + shape.width / 2, y: shape.y + shape.height / 2, width: shape.width, height: shape.height };
  if (shape.shape === 'circle') return { shape: 'circle', x: shape.centerX, y: shape.centerY, width: shape.radius * 2, height: shape.radius * 2, radiusX: shape.radius, radiusY: shape.radius };
  if (shape.shape === 'ellipse') return { shape: 'ellipse', x: shape.centerX, y: shape.centerY, width: shape.radiusX * 2, height: shape.radiusY * 2, radiusX: shape.radiusX, radiusY: shape.radiusY };
  return { shape: 'sector', x: shape.originX, y: shape.originY, width: shape.outerRadius * 2, height: shape.outerRadius * 2, originX: shape.originX, originY: shape.originY, angle: shape.angleRad, arcWidth: shape.arcWidthRad, innerRadius: shape.innerRadius, outerRadius: shape.outerRadius };
}

function wrappedAngle(value: number): number { return Math.atan2(Math.sin(value), Math.cos(value)); }
function pointInSector(x: number, y: number, sector: SectorSensorShape): boolean {
  const dx = x - sector.originX;
  const dy = y - sector.originY;
  const distance = Math.hypot(dx, dy);
  if (distance < sector.innerRadius - EPSILON || distance > sector.outerRadius + EPSILON) return false;
  if (sector.arcWidthRad >= Math.PI * 2 - EPSILON) return true;
  return Math.abs(wrappedAngle(Math.atan2(dy, dx) - sector.angleRad)) <= sector.arcWidthRad / 2 + EPSILON;
}

function pointInShape(x: number, y: number, shape: SensorShape): boolean {
  if (shape.shape === 'rectangle') return x >= shape.x - EPSILON && x <= shape.x + shape.width + EPSILON && y >= shape.y - EPSILON && y <= shape.y + shape.height + EPSILON;
  if (shape.shape === 'circle') return squaredDistance(x, y, shape.centerX, shape.centerY) <= shape.radius * shape.radius + EPSILON;
  if (shape.shape === 'ellipse') { const dx = (x - shape.centerX) / shape.radiusX; const dy = (y - shape.centerY) / shape.radiusY; return dx * dx + dy * dy <= 1 + EPSILON; }
  return pointInSector(x, y, shape);
}

function boundaryPoints(shape: SensorShape): readonly Readonly<{ x: number; y: number }>[] {
  if (shape.shape === 'rectangle') return [
    { x: shape.x, y: shape.y }, { x: shape.x + shape.width, y: shape.y },
    { x: shape.x + shape.width, y: shape.y + shape.height }, { x: shape.x, y: shape.y + shape.height },
  ];
  if (shape.shape === 'circle' || shape.shape === 'ellipse') {
    const radiusX = shape.shape === 'circle' ? shape.radius : shape.radiusX;
    const radiusY = shape.shape === 'circle' ? shape.radius : shape.radiusY;
    const centerX = shape.shape === 'circle' ? shape.centerX : shape.centerX;
    const centerY = shape.shape === 'circle' ? shape.centerY : shape.centerY;
    return Array.from({ length: CURVE_SEGMENTS }, (_, index) => {
      const angle = index / CURVE_SEGMENTS * Math.PI * 2;
      return { x: centerX + Math.cos(angle) * radiusX, y: centerY + Math.sin(angle) * radiusY };
    });
  }
  const full = shape.arcWidthRad >= Math.PI * 2 - EPSILON;
  const steps = full ? CURVE_SEGMENTS : Math.max(8, Math.ceil(CURVE_SEGMENTS * shape.arcWidthRad / (Math.PI * 2)));
  const start = full ? -Math.PI : shape.angleRad - shape.arcWidthRad / 2;
  const width = full ? Math.PI * 2 : shape.arcWidthRad;
  const outer = Array.from({ length: steps + 1 }, (_, index) => { const angle = start + width * index / steps; return { x: shape.originX + Math.cos(angle) * shape.outerRadius, y: shape.originY + Math.sin(angle) * shape.outerRadius }; });
  const innerRadius = shape.innerRadius;
  if (innerRadius <= EPSILON) return full ? outer : [...outer, { x: shape.originX, y: shape.originY }];
  const inner = Array.from({ length: steps + 1 }, (_, index) => { const angle = start + width * (steps - index) / steps; return { x: shape.originX + Math.cos(angle) * innerRadius, y: shape.originY + Math.sin(angle) * innerRadius }; });
  return [...outer, ...inner];
}

function orientation(a: Readonly<{ x: number; y: number }>, b: Readonly<{ x: number; y: number }>, c: Readonly<{ x: number; y: number }>): number {
  return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

function onSegment(point: Readonly<{ x: number; y: number }>, start: Readonly<{ x: number; y: number }>, end: Readonly<{ x: number; y: number }>): boolean {
  return Math.abs(orientation(start, end, point)) <= EPSILON && point.x >= Math.min(start.x, end.x) - EPSILON && point.x <= Math.max(start.x, end.x) + EPSILON && point.y >= Math.min(start.y, end.y) - EPSILON && point.y <= Math.max(start.y, end.y) + EPSILON;
}

function segmentsIntersect(a: Readonly<{ x: number; y: number }>, b: Readonly<{ x: number; y: number }>, c: Readonly<{ x: number; y: number }>, d: Readonly<{ x: number; y: number }>): boolean {
  const abC = orientation(a, b, c); const abD = orientation(a, b, d); const cdA = orientation(c, d, a); const cdB = orientation(c, d, b);
  if (((abC > EPSILON && abD < -EPSILON) || (abC < -EPSILON && abD > EPSILON)) && ((cdA > EPSILON && cdB < -EPSILON) || (cdA < -EPSILON && cdB > EPSILON))) return true;
  return onSegment(c, a, b) || onSegment(d, a, b) || onSegment(a, c, d) || onSegment(b, c, d);
}

function sampledCurvesIntersect(first: SensorShape, second: SensorShape): boolean {
  const firstPoints = boundaryPoints(first);
  const secondPoints = boundaryPoints(second);
  if (firstPoints.some((point) => pointInShape(point.x, point.y, second)) || secondPoints.some((point) => pointInShape(point.x, point.y, first))) return true;
  for (let a = 0; a < firstPoints.length; a += 1) {
    const aStart = firstPoints[a]; const aEnd = firstPoints[(a + 1) % firstPoints.length];
    for (let b = 0; b < secondPoints.length; b += 1) {
      if (segmentsIntersect(aStart, aEnd, secondPoints[b], secondPoints[(b + 1) % secondPoints.length])) return true;
    }
  }
  return false;
}

export function sensorShapesIntersect(first: SensorShape, second: SensorShape): boolean {
  validateSensorShape(first); validateSensorShape(second);
  if (!sensorBoundsIntersect(sensorShapeBounds(first), sensorShapeBounds(second))) return false;
  if (second.shape === 'rectangle' || second.shape === 'circle') return attackIntersectsCombatBody(attackGeometry(first), bodyGeometry(second));
  if (first.shape === 'rectangle' || first.shape === 'circle') return attackIntersectsCombatBody(attackGeometry(second), bodyGeometry(first));
  if (first.shape === 'ellipse' && second.shape === 'ellipse') {
    const dx = (first.centerX - second.centerX) / (first.radiusX + second.radiusX);
    const dy = (first.centerY - second.centerY) / (first.radiusY + second.radiusY);
    return dx * dx + dy * dy <= 1 + EPSILON;
  }
  return sampledCurvesIntersect(first, second);
}

export function closestPointOnBounds(bounds: SensorBounds, x: number, y: number): Readonly<{ x: number; y: number }> {
  return { x: clamp(x, bounds.x, bounds.x + bounds.width), y: clamp(y, bounds.y, bounds.y + bounds.height) };
}
