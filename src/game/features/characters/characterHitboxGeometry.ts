import type { CharacterHitboxDocument } from '../../content/characters/types';
import { normalizeCollisionShape, resolveCollisionShapeDimensions, type CollisionShape } from '../../shared/collisionShapes';

export interface CharacterHitboxRectangle {
  readonly shape?: 'rectangle';
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

export interface CharacterHitboxCircle {
  readonly shape: 'circle';
  readonly centerX: number;
  readonly centerY: number;
  readonly radius: number;
  readonly width: number;
  readonly height: number;
}

export interface CharacterHitboxEllipse {
  readonly shape: 'ellipse';
  readonly centerX: number;
  readonly centerY: number;
  readonly radiusX: number;
  readonly radiusY: number;
  readonly width: number;
  readonly height: number;
}

export type CharacterHitboxGeometry = CharacterHitboxRectangle | CharacterHitboxCircle | CharacterHitboxEllipse;

export interface CharacterHitboxAnchor {
  readonly x: number;
  readonly y: number;
}

export function resolveCharacterHitboxGeometry(
  hitbox: CharacterHitboxDocument,
  anchor: CharacterHitboxAnchor,
  facingX: 1 | -1,
): CharacterHitboxGeometry {
  const centerX = anchor.x + (hitbox.mirrorX ? hitbox.offsetX * facingX : hitbox.offsetX);
  const centerY = anchor.y + hitbox.offsetY;
  const dimensions = resolveCollisionShapeDimensions(hitbox);
  if (dimensions.shape === 'circle') {
    return {
      shape: 'circle',
      centerX,
      centerY,
      radius: dimensions.radius ?? Math.min(hitbox.width, hitbox.height) / 2,
      width: dimensions.width,
      height: dimensions.height,
    };
  }
  if (dimensions.shape === 'ellipse') {
    return {
      shape: 'ellipse',
      centerX,
      centerY,
      radiusX: dimensions.radiusX ?? hitbox.width / 2,
      radiusY: dimensions.radiusY ?? hitbox.height / 2,
      width: dimensions.width,
      height: dimensions.height,
    };
  }
  return {
    shape: 'rectangle',
    x: centerX - dimensions.width / 2,
    y: centerY - dimensions.height / 2,
    width: dimensions.width,
    height: dimensions.height,
  };
}

/** Resolve an authored hitbox into world-space top-left rectangle coordinates. */
export function resolveCharacterHitboxRectangle(
  hitbox: CharacterHitboxDocument,
  anchor: CharacterHitboxAnchor,
  facingX: 1 | -1,
): CharacterHitboxRectangle {
  const geometry = resolveCharacterHitboxGeometry(hitbox, anchor, facingX);
  return geometryToRectangle(geometry);
}

export function geometryToRectangle(geometry: CharacterHitboxGeometry): CharacterHitboxRectangle {
  if (geometry.shape === 'circle' || geometry.shape === 'ellipse') {
    return {
      x: geometry.centerX - geometry.width / 2,
      y: geometry.centerY - geometry.height / 2,
      width: geometry.width,
      height: geometry.height,
    };
  }
  return { x: geometry.x, y: geometry.y, width: geometry.width, height: geometry.height };
}

/** Match Arcade's strict overlap behavior: edge-touching shapes do not overlap. */
export function characterHitboxesIntersect(
  first: CharacterHitboxGeometry | CharacterHitboxRectangle,
  second: CharacterHitboxGeometry | CharacterHitboxRectangle,
): boolean {
  const firstShape = inferShape(first);
  const secondShape = inferShape(second);
  if (firstShape.shape === 'rectangle' && secondShape.shape === 'rectangle') return rectanglesIntersect(firstShape, secondShape);
  if (firstShape.shape === 'circle' && secondShape.shape === 'circle') return circlesIntersect(firstShape, secondShape);
  if (firstShape.shape === 'ellipse' && secondShape.shape === 'ellipse') return ellipsesIntersect(firstShape, secondShape);
  if (firstShape.shape === 'circle' && secondShape.shape === 'rectangle') return circleRectangleIntersect(firstShape, secondShape);
  if (firstShape.shape === 'rectangle' && secondShape.shape === 'circle') return circleRectangleIntersect(secondShape, firstShape);
  if (firstShape.shape === 'ellipse' && secondShape.shape === 'rectangle') return ellipseRectangleIntersect(firstShape, secondShape);
  if (firstShape.shape === 'rectangle' && secondShape.shape === 'ellipse') return ellipseRectangleIntersect(secondShape, firstShape);
  if (firstShape.shape === 'circle' && secondShape.shape === 'ellipse') return circleEllipseIntersect(firstShape, secondShape);
  return circleEllipseIntersect(secondShape as CharacterHitboxCircle, firstShape as CharacterHitboxEllipse);
}

function inferShape(value: CharacterHitboxGeometry | CharacterHitboxRectangle): CharacterHitboxGeometry {
  if (value.shape === 'circle' || value.shape === 'ellipse') return value;
  return {
    shape: 'rectangle',
    x: value.x,
    y: value.y,
    width: value.width,
    height: value.height,
  };
}

function rectanglesIntersect(first: CharacterHitboxRectangle, second: CharacterHitboxRectangle): boolean {
  return first.x < second.x + second.width
    && first.x + first.width > second.x
    && first.y < second.y + second.height
    && first.y + first.height > second.y;
}

function circlesIntersect(first: CharacterHitboxCircle, second: CharacterHitboxCircle): boolean {
  const dx = first.centerX - second.centerX;
  const dy = first.centerY - second.centerY;
  const radius = first.radius + second.radius;
  return dx * dx + dy * dy < radius * radius;
}

function circleRectangleIntersect(circle: CharacterHitboxCircle, rectangle: CharacterHitboxRectangle): boolean {
  const closestX = Math.max(rectangle.x, Math.min(circle.centerX, rectangle.x + rectangle.width));
  const closestY = Math.max(rectangle.y, Math.min(circle.centerY, rectangle.y + rectangle.height));
  const dx = circle.centerX - closestX;
  const dy = circle.centerY - closestY;
  return dx * dx + dy * dy < circle.radius * circle.radius;
}

function ellipseRectangleIntersect(ellipse: CharacterHitboxEllipse, rectangle: CharacterHitboxRectangle): boolean {
  if (ellipse.centerX > rectangle.x && ellipse.centerX < rectangle.x + rectangle.width && ellipse.centerY > rectangle.y && ellipse.centerY < rectangle.y + rectangle.height) return true;
  const closestX = Math.max(rectangle.x, Math.min(ellipse.centerX, rectangle.x + rectangle.width));
  const closestY = Math.max(rectangle.y, Math.min(ellipse.centerY, rectangle.y + rectangle.height));
  const dx = (ellipse.centerX - closestX) / ellipse.radiusX;
  const dy = (ellipse.centerY - closestY) / ellipse.radiusY;
  return dx * dx + dy * dy < 1;
}

function ellipsesIntersect(first: CharacterHitboxEllipse, second: CharacterHitboxEllipse): boolean {
  const dx = (first.centerX - second.centerX) / (first.radiusX + second.radiusX);
  const dy = (first.centerY - second.centerY) / (first.radiusY + second.radiusY);
  return dx * dx + dy * dy < 1;
}

/** Conservative ellipse-vs-circle approximation using the ellipse's narrow axis. */
function circleEllipseIntersect(circle: CharacterHitboxCircle, ellipse: CharacterHitboxEllipse): boolean {
  const dx = (circle.centerX - ellipse.centerX) / ellipse.radiusX;
  const dy = (circle.centerY - ellipse.centerY) / ellipse.radiusY;
  const padding = circle.radius / Math.min(ellipse.radiusX, ellipse.radiusY);
  return dx * dx + dy * dy < (1 + padding) * (1 + padding);
}

export function collisionShapeLabel(shape: CollisionShape | undefined): string {
  const normalized = normalizeCollisionShape(shape);
  return normalized === 'ellipse' ? 'Ellipse' : normalized === 'circle' ? 'Circle' : 'Rectangle';
}
