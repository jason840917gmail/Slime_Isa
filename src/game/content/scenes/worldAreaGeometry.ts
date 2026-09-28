import type { MapEnemyAreaPerimeter } from '../maps/mapFormat';
import type { CollisionShapeValue } from './resources/types';

/**
 * World areas (enemy safe zones, enemy spawn areas, NPC wander areas) take
 * their perimeters from authored CollisionShape2D nodes so Scene Studio's
 * shape handles are the single source of truth for their geometry.
 */

export interface WorldAreaTransform {
  readonly position: readonly [number, number];
  readonly rotation: number;
  readonly scale: readonly [number, number];
}

export type PerimeterResult =
  | { readonly perimeter: MapEnemyAreaPerimeter; readonly issue?: undefined }
  | { readonly perimeter?: undefined; readonly issue: string };

const ANGLE_EPSILON = 1e-6;

/** 0° or 180°: an axis-aligned rectangle keeps its width and height. */
function unrotated(rotation: number): boolean {
  return Math.abs(Math.sin(rotation)) < ANGLE_EPSILON;
}

/**
 * World-space perimeter of a collision shape placed at a global transform,
 * snapped to whole pixels (the map format stores integer coordinates, while
 * viewport drags can leave half-pixel sizes and centres).
 */
export function perimeterFromCollisionShape(value: CollisionShapeValue, transform: WorldAreaTransform): PerimeterResult {
  const [x, y] = transform.position;
  const scaleX = Math.abs(transform.scale[0]);
  const scaleY = Math.abs(transform.scale[1]);
  if (value.shape === 'circle') {
    if (Math.abs(scaleX - scaleY) > ANGLE_EPSILON) return { issue: 'circle areas need a uniform scale' };
    return { perimeter: { shape: 'circle', x: Math.round(x), y: Math.round(y), radius: Math.max(1, Math.round(value.radius * scaleX)) } };
  }
  if (value.shape === 'rectangle') {
    if (!unrotated(transform.rotation)) return { issue: 'rectangle areas cannot be rotated' };
    const w = value.width * scaleX;
    const h = value.height * scaleY;
    // Snap both edges so the rectangle never grows or shrinks by more than half a pixel per side.
    const left = Math.round(x - w / 2);
    const top = Math.round(y - h / 2);
    const right = Math.max(left + 1, Math.round(x + w / 2));
    const bottom = Math.max(top + 1, Math.round(y + h / 2));
    return { perimeter: { shape: 'rectangle', x: left, y: top, w: right - left, h: bottom - top } };
  }
  return { issue: `${value.shape} shapes are not supported for world areas; use a rectangle or circle` };
}

/** The spawn-area rule the enemy AI relies on: same shape, stay fully inside pursue. */
export function enemySpawnPerimeterIssues(stay: MapEnemyAreaPerimeter, pursue: MapEnemyAreaPerimeter): readonly string[] {
  if (stay.shape !== pursue.shape) return ['stay and pursue shapes must both be rectangles or both be circles'];
  if (stay.shape === 'circle' && pursue.shape === 'circle') {
    return Math.hypot(stay.x - pursue.x, stay.y - pursue.y) + stay.radius > pursue.radius + ANGLE_EPSILON
      ? ['the stay circle must fit inside the pursue circle'] : [];
  }
  if (stay.shape === 'rectangle' && pursue.shape === 'rectangle') {
    return stay.x < pursue.x || stay.y < pursue.y || stay.x + stay.w > pursue.x + pursue.w || stay.y + stay.h > pursue.y + pursue.h
      ? ['the stay rectangle must fit inside the pursue rectangle'] : [];
  }
  return [];
}

export function describePerimeter(perimeter: MapEnemyAreaPerimeter): string {
  const round = (value: number): number => Math.round(value * 10) / 10;
  return perimeter.shape === 'circle'
    ? `circle r${round(perimeter.radius)} at ${round(perimeter.x)}, ${round(perimeter.y)}`
    : `${round(perimeter.w)}×${round(perimeter.h)} at ${round(perimeter.x)}, ${round(perimeter.y)}`;
}
