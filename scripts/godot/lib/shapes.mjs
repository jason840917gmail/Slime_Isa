/**
 * `collision-shape` resources → Shape2D sub-resources.
 *
 * Rectangles and circles map directly. Arcade has no ellipse body, so an
 * ellipse under a physics body blocks as its bounding rectangle; under an
 * Area2D it overlaps as the true ellipse (32-point convex polygon). Sectors
 * (basic sword hitboxes) become convex polygons built at angle 0; the
 * effective angle goes to the shape node's `rotation`.
 */
import { gd } from './tscn.mjs';

const ELLIPSE_SEGMENTS = 32;

const round = (value) => Math.round(value * 1e4) / 1e4;

function ellipsePoints(radiusX, radiusY) {
  const points = [];
  for (let index = 0; index < ELLIPSE_SEGMENTS; index += 1) {
    const angle = (index / ELLIPSE_SEGMENTS) * Math.PI * 2;
    points.push([round(radiusX * Math.cos(angle)), round(radiusY * Math.sin(angle))]);
  }
  return points;
}

/** Sector outline at angle 0: apex (or inner arc), then the outer arc. */
function sectorPoints({ arcWidthRad, innerRadius = 0, outerRadius }) {
  const steps = Math.max(8, Math.ceil((96 * arcWidthRad) / (Math.PI * 2)));
  const arc = (radius) => Array.from({ length: steps + 1 }, (_, index) => {
    const angle = -arcWidthRad / 2 + (arcWidthRad * index) / steps;
    return [round(radius * Math.cos(angle)), round(radius * Math.sin(angle))];
  });
  if (innerRadius > 0) return [...arc(outerRadius), ...arc(innerRadius).reverse()];
  return [[0, 0], ...arc(outerRadius)];
}

/**
 * Converts a shape resource for a CollisionShape2D whose parent has
 * `parentType`. Returns { shape, rotation?, concave? }.
 */
export function convertShape(resource, parentType, angleOverride) {
  const value = resource.value;
  const key = (variant) => `${resource.resourceId}:${variant}`;
  switch (value.shape) {
    case 'rectangle':
      return { shape: gd.sub('RectangleShape2D', key('rect'), [['size', gd.vec2(value.width, value.height)]]) };
    case 'circle':
      return { shape: gd.sub('CircleShape2D', key('circle'), [['radius', gd.float(value.radius)]]) };
    case 'ellipse':
      if (parentType !== 'Area2D') {
        return { shape: gd.sub('RectangleShape2D', key('ellipse-box'), [['size', gd.vec2(value.radiusX * 2, value.radiusY * 2)]]) };
      }
      return { shape: gd.sub('ConvexPolygonShape2D', key('ellipse'), [['points', gd.packedVector2(ellipsePoints(value.radiusX, value.radiusY))]]) };
    case 'sector': {
      const concave = value.arcWidthRad > Math.PI || (value.innerRadius ?? 0) > 0;
      const type = concave ? 'ConcavePolygonShape2D' : 'ConvexPolygonShape2D';
      const points = sectorPoints(value);
      const props = concave
        ? [['segments', gd.packedVector2(points.flatMap((point, index) => [point, points[(index + 1) % points.length]]))]]
        : [['points', gd.packedVector2(points)]];
      return { shape: gd.sub(type, key('sector'), props), rotation: angleOverride ?? value.angleRad ?? 0, concave };
    }
    default:
      throw new Error(`Collision shape '${resource.resourceId}' has unknown kind '${value.shape}'`);
  }
}
