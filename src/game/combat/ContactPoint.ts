import type { EffectDirection } from '../content/effects/types';

export interface AxisAlignedBounds { readonly x: number; readonly y: number; readonly width: number; readonly height: number }
export interface ContactVector { readonly x: number; readonly y: number }
export interface ContactPoint { readonly x: number; readonly y: number }

function finiteBounds(bounds: AxisAlignedBounds): boolean {
  return Number.isFinite(bounds.x) && Number.isFinite(bounds.y) && Number.isFinite(bounds.width) && Number.isFinite(bounds.height) && bounds.width >= 0 && bounds.height >= 0;
}

export function quantizeContactDirection(vector: ContactVector): EffectDirection {
  if (!Number.isFinite(vector.x) || !Number.isFinite(vector.y) || (vector.x === 0 && vector.y === 0)) return 'right';
  if (Math.abs(vector.x) >= Math.abs(vector.y)) return vector.x < 0 ? 'left' : 'right';
  return vector.y < 0 ? 'up' : 'down';
}

export function cardinalContactVector(direction: EffectDirection): ContactVector {
  if (direction === 'left') return { x: -1, y: 0 };
  if (direction === 'up') return { x: 0, y: -1 };
  if (direction === 'down') return { x: 0, y: 1 };
  return { x: 1, y: 0 };
}

/** Near edge of the target opposite the incoming attack direction. */
export function contactPointAtTargetEdge(bounds: AxisAlignedBounds, incoming: ContactVector): ContactPoint {
  const center = { x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2 };
  if (!finiteBounds(bounds)) return { x: Number.isFinite(center.x) ? center.x : 0, y: Number.isFinite(center.y) ? center.y : 0 };
  const direction = quantizeContactDirection(incoming);
  if (direction === 'right') return { x: bounds.x, y: center.y };
  if (direction === 'left') return { x: bounds.x + bounds.width, y: center.y };
  if (direction === 'down') return { x: center.x, y: bounds.y };
  return { x: center.x, y: bounds.y + bounds.height };
}
