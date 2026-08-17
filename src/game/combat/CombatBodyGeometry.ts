export interface AxisAlignedCombatBounds {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

export interface RectangleCombatBodyGeometry extends AxisAlignedCombatBounds {
  readonly shape: 'rectangle';
}

export interface CircleCombatBodyGeometry extends AxisAlignedCombatBounds {
  readonly shape: 'circle';
  readonly centerX: number;
  readonly centerY: number;
  readonly radius: number;
}

export type CombatBodyGeometry = RectangleCombatBodyGeometry | CircleCombatBodyGeometry;

interface ArcadeBodyGeometrySource {
  readonly enable: boolean;
  readonly isCircle?: boolean;
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
  readonly halfWidth?: number;
  readonly center?: { readonly x: number; readonly y: number };
}

export interface CombatBodyTargetSource {
  readonly active?: boolean;
  readonly body?: ArcadeBodyGeometrySource | null;
}

export interface CombatAttackGeometrySource {
  readonly shape?: 'rect' | 'circle' | 'ellipse' | 'sector';
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
  readonly radiusX?: number;
  readonly radiusY?: number;
  readonly originX?: number;
  readonly originY?: number;
  readonly angle?: number;
  readonly arcWidth?: number;
  readonly innerRadius?: number;
  readonly outerRadius?: number;
}

interface Point {
  readonly x: number;
  readonly y: number;
}

interface Circle {
  readonly centerX: number;
  readonly centerY: number;
  readonly radius: number;
}

interface Ellipse {
  readonly centerX: number;
  readonly centerY: number;
  readonly radiusX: number;
  readonly radiusY: number;
}

interface Sector {
  readonly originX: number;
  readonly originY: number;
  readonly angle: number;
  readonly halfArc: number;
  readonly innerRadius: number;
  readonly outerRadius: number;
  readonly full: boolean;
}

const EPSILON = 1e-9;
const TAU = Math.PI * 2;

function finite(...values: readonly number[]): boolean {
  return values.every(Number.isFinite);
}

export function resolveCombatBodyGeometry(
  target: CombatBodyTargetSource | null | undefined,
): CombatBodyGeometry | null {
  if (!target || target.active === false) return null;
  const body = target.body;
  if (!body || body.enable !== true) return null;
  if (!finite(body.x, body.y, body.width, body.height) || body.width <= 0 || body.height <= 0) return null;

  if (!body.isCircle) {
    return {
      shape: 'rectangle',
      x: body.x,
      y: body.y,
      width: body.width,
      height: body.height,
    };
  }

  const radius = body.halfWidth ?? body.width / 2;
  const centerX = body.center?.x ?? body.x + body.width / 2;
  const centerY = body.center?.y ?? body.y + body.height / 2;
  if (!finite(radius, centerX, centerY) || radius <= 0) return null;

  return {
    shape: 'circle',
    x: centerX - radius,
    y: centerY - radius,
    width: radius * 2,
    height: radius * 2,
    centerX,
    centerY,
    radius,
  };
}

export function attackIntersectsCombatBody(
  attack: CombatAttackGeometrySource,
  target: CombatBodyGeometry | null | undefined,
): boolean {
  if (!target) return false;

  if (attack.shape === 'sector') {
    const sector = resolveSector(attack);
    if (!sector) return false;
    return target.shape === 'circle'
      ? circleIntersectsSector(target, sector)
      : sectorIntersectsRectangle(sector, target);
  }

  if (attack.shape === 'circle' || attack.shape === 'ellipse') {
    const ellipse = resolveEllipse(attack);
    if (!ellipse) return false;
    return target.shape === 'circle'
      ? ellipseIntersectsCircle(ellipse, target)
      : ellipseIntersectsRectangle(ellipse, target);
  }

  const rectangle = resolveAttackRectangle(attack);
  if (!rectangle) return false;
  return target.shape === 'circle'
    ? rectangleIntersectsCircle(rectangle, target)
    : rectanglesIntersect(rectangle, target);
}

function resolveAttackRectangle(attack: CombatAttackGeometrySource): AxisAlignedCombatBounds | null {
  if (!finite(attack.x, attack.y, attack.width, attack.height) || attack.width <= 0 || attack.height <= 0) return null;
  return {
    x: attack.x - attack.width / 2,
    y: attack.y - attack.height / 2,
    width: attack.width,
    height: attack.height,
  };
}

function resolveEllipse(attack: CombatAttackGeometrySource): Ellipse | null {
  const radiusX = attack.radiusX ?? attack.width / 2;
  const radiusY = attack.shape === 'circle'
    ? attack.radiusY ?? radiusX
    : attack.radiusY ?? attack.height / 2;
  if (!finite(attack.x, attack.y, radiusX, radiusY) || radiusX <= 0 || radiusY <= 0) return null;
  return { centerX: attack.x, centerY: attack.y, radiusX, radiusY };
}

function resolveSector(attack: CombatAttackGeometrySource): Sector | null {
  const originX = attack.originX ?? attack.x;
  const originY = attack.originY ?? attack.y;
  const angle = attack.angle ?? 0;
  const arcWidth = attack.arcWidth ?? Math.PI / 2;
  const innerRadius = attack.innerRadius ?? 0;
  const outerRadius = attack.outerRadius ?? Math.max(attack.width, attack.height) / 2;
  if (!finite(originX, originY, angle, arcWidth, innerRadius, outerRadius)) return null;
  if (arcWidth < 0 || innerRadius < 0 || outerRadius <= innerRadius) return null;
  const full = arcWidth >= TAU - EPSILON;
  return {
    originX,
    originY,
    angle,
    halfArc: full ? Math.PI : arcWidth / 2,
    innerRadius,
    outerRadius,
    full,
  };
}

function rectanglesIntersect(a: AxisAlignedCombatBounds, b: AxisAlignedCombatBounds): boolean {
  return a.x <= b.x + b.width + EPSILON
    && a.x + a.width + EPSILON >= b.x
    && a.y <= b.y + b.height + EPSILON
    && a.y + a.height + EPSILON >= b.y;
}

function rectangleIntersectsCircle(rectangle: AxisAlignedCombatBounds, circle: Circle): boolean {
  const closestX = clamp(circle.centerX, rectangle.x, rectangle.x + rectangle.width);
  const closestY = clamp(circle.centerY, rectangle.y, rectangle.y + rectangle.height);
  return squaredDistance(circle.centerX, circle.centerY, closestX, closestY)
    <= circle.radius * circle.radius + EPSILON;
}

function ellipseIntersectsRectangle(ellipse: Ellipse, rectangle: AxisAlignedCombatBounds): boolean {
  const closestX = clamp(ellipse.centerX, rectangle.x, rectangle.x + rectangle.width);
  const closestY = clamp(ellipse.centerY, rectangle.y, rectangle.y + rectangle.height);
  const normalizedX = (closestX - ellipse.centerX) / ellipse.radiusX;
  const normalizedY = (closestY - ellipse.centerY) / ellipse.radiusY;
  return normalizedX * normalizedX + normalizedY * normalizedY <= 1 + EPSILON;
}

function ellipseIntersectsCircle(ellipse: Ellipse, circle: Circle): boolean {
  return distanceFromPointToEllipse(circle.centerX, circle.centerY, ellipse) <= circle.radius + EPSILON;
}

function distanceFromPointToEllipse(x: number, y: number, ellipse: Ellipse): number {
  const pointX = Math.abs(x - ellipse.centerX);
  const pointY = Math.abs(y - ellipse.centerY);
  const radiusXSquared = ellipse.radiusX * ellipse.radiusX;
  const radiusYSquared = ellipse.radiusY * ellipse.radiusY;
  const normalized = pointX * pointX / radiusXSquared + pointY * pointY / radiusYSquared;
  if (normalized <= 1 + EPSILON) return 0;

  const equation = (t: number) => {
    const xTerm = ellipse.radiusX * pointX / (t + radiusXSquared);
    const yTerm = ellipse.radiusY * pointY / (t + radiusYSquared);
    return xTerm * xTerm + yTerm * yTerm - 1;
  };

  let low = 0;
  let high = Math.max(radiusXSquared, radiusYSquared, 1);
  while (equation(high) > 0) high *= 2;
  for (let iteration = 0; iteration < 64; iteration += 1) {
    const midpoint = (low + high) / 2;
    if (equation(midpoint) > 0) low = midpoint;
    else high = midpoint;
  }

  const parameter = (low + high) / 2;
  const closestX = radiusXSquared * pointX / (parameter + radiusXSquared);
  const closestY = radiusYSquared * pointY / (parameter + radiusYSquared);
  return Math.hypot(pointX - closestX, pointY - closestY);
}

function circleIntersectsSector(circle: Circle, sector: Sector): boolean {
  return distanceFromPointToSector(circle.centerX, circle.centerY, sector) <= circle.radius + EPSILON;
}

function distanceFromPointToSector(x: number, y: number, sector: Sector): number {
  const dx = x - sector.originX;
  const dy = y - sector.originY;
  const distance = Math.hypot(dx, dy);

  if (sector.full) return radialDistance(distance, sector.innerRadius, sector.outerRadius);
  if (distance <= EPSILON && sector.innerRadius <= EPSILON) return 0;

  const pointAngle = Math.atan2(dy, dx);
  if (angleWithinSector(pointAngle, sector)) {
    return radialDistance(distance, sector.innerRadius, sector.outerRadius);
  }

  const firstBoundary = radialSegment(sector, sector.angle - sector.halfArc);
  const secondBoundary = radialSegment(sector, sector.angle + sector.halfArc);
  return Math.min(
    distanceFromPointToSegment(x, y, firstBoundary[0], firstBoundary[1]),
    distanceFromPointToSegment(x, y, secondBoundary[0], secondBoundary[1]),
  );
}

function sectorIntersectsRectangle(sector: Sector, rectangle: AxisAlignedCombatBounds): boolean {
  const corners = rectangleCorners(rectangle);
  if (corners.some((point) => pointWithinSector(point, sector))) return true;

  const sampleRadius = (sector.innerRadius + sector.outerRadius) / 2;
  const sectorSample = pointAt(sector.originX, sector.originY, sector.angle, sampleRadius);
  if (rectangleContainsPoint(rectangle, sectorSample)) return true;

  const edges = rectangleEdges(corners);
  if (!sector.full) {
    const firstBoundary = radialSegment(sector, sector.angle - sector.halfArc);
    const secondBoundary = radialSegment(sector, sector.angle + sector.halfArc);
    if (edges.some(([start, end]) => (
      segmentsIntersect(start, end, firstBoundary[0], firstBoundary[1])
      || segmentsIntersect(start, end, secondBoundary[0], secondBoundary[1])
    ))) return true;
  }

  return edges.some(([start, end]) => (
    segmentIntersectsArc(start, end, sector.outerRadius, sector)
    || (sector.innerRadius > EPSILON && segmentIntersectsArc(start, end, sector.innerRadius, sector))
  ));
}

function pointWithinSector(point: Point, sector: Sector): boolean {
  const dx = point.x - sector.originX;
  const dy = point.y - sector.originY;
  const distance = Math.hypot(dx, dy);
  if (distance < sector.innerRadius - EPSILON || distance > sector.outerRadius + EPSILON) return false;
  if (sector.full) return true;
  if (distance <= EPSILON) return sector.innerRadius <= EPSILON;
  return angleWithinSector(Math.atan2(dy, dx), sector);
}

function angleWithinSector(angle: number, sector: Sector): boolean {
  if (sector.full) return true;
  return Math.abs(wrappedAngle(angle - sector.angle)) <= sector.halfArc + EPSILON;
}

function segmentIntersectsArc(start: Point, end: Point, radius: number, sector: Sector): boolean {
  const dx = end.x - start.x;
  const dy = end.y - start.y;
  const relativeX = start.x - sector.originX;
  const relativeY = start.y - sector.originY;
  const a = dx * dx + dy * dy;
  if (a <= EPSILON) {
    const onCircle = Math.abs(Math.hypot(relativeX, relativeY) - radius) <= EPSILON;
    return onCircle && angleWithinSector(Math.atan2(relativeY, relativeX), sector);
  }

  const b = 2 * (relativeX * dx + relativeY * dy);
  const c = relativeX * relativeX + relativeY * relativeY - radius * radius;
  const discriminant = b * b - 4 * a * c;
  if (discriminant < -EPSILON) return false;
  const root = Math.sqrt(Math.max(0, discriminant));
  const denominator = 2 * a;
  return [(-b - root) / denominator, (-b + root) / denominator].some((parameter) => {
    if (parameter < -EPSILON || parameter > 1 + EPSILON) return false;
    const x = start.x + dx * parameter - sector.originX;
    const y = start.y + dy * parameter - sector.originY;
    return angleWithinSector(Math.atan2(y, x), sector);
  });
}

function radialSegment(sector: Sector, angle: number): readonly [Point, Point] {
  return [
    pointAt(sector.originX, sector.originY, angle, sector.innerRadius),
    pointAt(sector.originX, sector.originY, angle, sector.outerRadius),
  ];
}

function pointAt(originX: number, originY: number, angle: number, distance: number): Point {
  return {
    x: originX + Math.cos(angle) * distance,
    y: originY + Math.sin(angle) * distance,
  };
}

function rectangleCorners(rectangle: AxisAlignedCombatBounds): readonly [Point, Point, Point, Point] {
  const right = rectangle.x + rectangle.width;
  const bottom = rectangle.y + rectangle.height;
  return [
    { x: rectangle.x, y: rectangle.y },
    { x: right, y: rectangle.y },
    { x: right, y: bottom },
    { x: rectangle.x, y: bottom },
  ];
}

function rectangleEdges(corners: readonly [Point, Point, Point, Point]): readonly (readonly [Point, Point])[] {
  return [
    [corners[0], corners[1]],
    [corners[1], corners[2]],
    [corners[2], corners[3]],
    [corners[3], corners[0]],
  ];
}

function rectangleContainsPoint(rectangle: AxisAlignedCombatBounds, point: Point): boolean {
  return point.x >= rectangle.x - EPSILON
    && point.x <= rectangle.x + rectangle.width + EPSILON
    && point.y >= rectangle.y - EPSILON
    && point.y <= rectangle.y + rectangle.height + EPSILON;
}

function segmentsIntersect(a: Point, b: Point, c: Point, d: Point): boolean {
  const abC = cross(a, b, c);
  const abD = cross(a, b, d);
  const cdA = cross(c, d, a);
  const cdB = cross(c, d, b);

  if (((abC > EPSILON && abD < -EPSILON) || (abC < -EPSILON && abD > EPSILON))
    && ((cdA > EPSILON && cdB < -EPSILON) || (cdA < -EPSILON && cdB > EPSILON))) return true;
  if (Math.abs(abC) <= EPSILON && pointOnSegment(c, a, b)) return true;
  if (Math.abs(abD) <= EPSILON && pointOnSegment(d, a, b)) return true;
  if (Math.abs(cdA) <= EPSILON && pointOnSegment(a, c, d)) return true;
  return Math.abs(cdB) <= EPSILON && pointOnSegment(b, c, d);
}

function cross(a: Point, b: Point, c: Point): number {
  return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

function pointOnSegment(point: Point, start: Point, end: Point): boolean {
  return point.x >= Math.min(start.x, end.x) - EPSILON
    && point.x <= Math.max(start.x, end.x) + EPSILON
    && point.y >= Math.min(start.y, end.y) - EPSILON
    && point.y <= Math.max(start.y, end.y) + EPSILON;
}

function distanceFromPointToSegment(x: number, y: number, start: Point, end: Point): number {
  const dx = end.x - start.x;
  const dy = end.y - start.y;
  const lengthSquared = dx * dx + dy * dy;
  if (lengthSquared <= EPSILON) return Math.hypot(x - start.x, y - start.y);
  const projection = clamp(((x - start.x) * dx + (y - start.y) * dy) / lengthSquared, 0, 1);
  return Math.hypot(x - (start.x + dx * projection), y - (start.y + dy * projection));
}

function radialDistance(distance: number, innerRadius: number, outerRadius: number): number {
  if (distance < innerRadius) return innerRadius - distance;
  if (distance > outerRadius) return distance - outerRadius;
  return 0;
}

function wrappedAngle(angle: number): number {
  return Math.atan2(Math.sin(angle), Math.cos(angle));
}

function squaredDistance(x1: number, y1: number, x2: number, y2: number): number {
  const dx = x1 - x2;
  const dy = y1 - y2;
  return dx * dx + dy * dy;
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.max(minimum, Math.min(maximum, value));
}
