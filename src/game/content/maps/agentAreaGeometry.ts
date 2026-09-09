import type { MapAgentAreaPerimeter } from './mapFormat';

export interface PerimeterBounds { readonly minX: number; readonly minY: number; readonly maxX: number; readonly maxY: number; }

export function perimeterBounds(perimeter: MapAgentAreaPerimeter): PerimeterBounds {
  return perimeter.shape === 'circle'
    ? { minX: perimeter.x - perimeter.radius, minY: perimeter.y - perimeter.radius, maxX: perimeter.x + perimeter.radius, maxY: perimeter.y + perimeter.radius }
    : { minX: perimeter.x, minY: perimeter.y, maxX: perimeter.x + perimeter.w, maxY: perimeter.y + perimeter.h };
}
export function perimeterContains(perimeter: MapAgentAreaPerimeter, x: number, y: number): boolean {
  if (perimeter.shape === 'circle') return Math.hypot(x - perimeter.x, y - perimeter.y) <= perimeter.radius;
  return x >= perimeter.x && x <= perimeter.x + perimeter.w && y >= perimeter.y && y <= perimeter.y + perimeter.h;
}
export function closestPointInPerimeter(perimeter: MapAgentAreaPerimeter, x: number, y: number): { x: number; y: number } {
  if (perimeter.shape === 'rectangle') return { x: Math.max(perimeter.x, Math.min(perimeter.x + perimeter.w, x)), y: Math.max(perimeter.y, Math.min(perimeter.y + perimeter.h, y)) };
  const dx = x - perimeter.x; const dy = y - perimeter.y; const distance = Math.hypot(dx, dy);
  if (distance <= perimeter.radius || distance === 0) return { x, y };
  const scale = perimeter.radius / distance;
  return { x: perimeter.x + dx * scale, y: perimeter.y + dy * scale };
}
export function insetPerimeter(perimeter: MapAgentAreaPerimeter, amount: number): MapAgentAreaPerimeter {
  const inset = Math.max(0, amount);
  if (perimeter.shape === 'circle') return { ...perimeter, radius: Math.max(1, perimeter.radius - inset) };
  const xInset = Math.min(inset, Math.max(0, (perimeter.w - 1) / 2)); const yInset = Math.min(inset, Math.max(0, (perimeter.h - 1) / 2));
  return { shape: 'rectangle', x: perimeter.x + xInset, y: perimeter.y + yInset, w: Math.max(1, perimeter.w - xInset * 2), h: Math.max(1, perimeter.h - yInset * 2) };
}
export function translatePerimeter(perimeter: MapAgentAreaPerimeter, dx: number, dy: number): MapAgentAreaPerimeter { return { ...perimeter, x: Math.round(perimeter.x + dx), y: Math.round(perimeter.y + dy) }; }
export function perimeterContainsPerimeter(outer: MapAgentAreaPerimeter, inner: MapAgentAreaPerimeter): boolean {
  if (outer.shape !== inner.shape) return false;
  if (outer.shape === 'circle' && inner.shape === 'circle') return Math.hypot(inner.x - outer.x, inner.y - outer.y) + inner.radius <= outer.radius;
  const outerBounds = perimeterBounds(outer); const innerBounds = perimeterBounds(inner);
  return innerBounds.minX >= outerBounds.minX && innerBounds.minY >= outerBounds.minY && innerBounds.maxX <= outerBounds.maxX && innerBounds.maxY <= outerBounds.maxY;
}
export function perimeterInsideMap(perimeter: MapAgentAreaPerimeter, width: number, height: number): boolean { const bounds = perimeterBounds(perimeter); return bounds.minX >= 0 && bounds.minY >= 0 && bounds.maxX <= width && bounds.maxY <= height; }
export function randomPointInPerimeter(perimeter: MapAgentAreaPerimeter, random: () => number = Math.random): { x: number; y: number } {
  if (perimeter.shape === 'circle') { const angle = random() * Math.PI * 2; const distance = Math.sqrt(random()) * perimeter.radius; return { x: perimeter.x + Math.cos(angle) * distance, y: perimeter.y + Math.sin(angle) * distance }; }
  return { x: perimeter.x + random() * perimeter.w, y: perimeter.y + random() * perimeter.h };
}
