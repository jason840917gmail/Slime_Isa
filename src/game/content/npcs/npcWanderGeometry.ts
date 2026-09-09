import type { CollisionShapeDocument } from '../../shared/collisionShapes';
import { resolveEffectiveArcadeBodyBoundsRelativeToAnchor } from '../../shared/collisionShapes';
import type { MapAgentAreaPerimeter, MapPoint } from '../maps/mapFormat';
import { perimeterBounds, perimeterContains, randomPointInPerimeter } from '../maps/agentAreaGeometry';

export const NPC_WANDER_MARGIN = 8;

export function npcAnchorDomain(perimeter: MapAgentAreaPerimeter, body: CollisionShapeDocument, margin = NPC_WANDER_MARGIN): MapAgentAreaPerimeter | undefined {
  const bounds = resolveEffectiveArcadeBodyBoundsRelativeToAnchor(body);
  if (perimeter.shape === 'circle') {
    const bodyRadius = Math.max(
      Math.hypot(bounds.minX, bounds.minY),
      Math.hypot(bounds.minX, bounds.maxY),
      Math.hypot(bounds.maxX, bounds.minY),
      Math.hypot(bounds.maxX, bounds.maxY),
    );
    const radius = perimeter.radius - bodyRadius - margin;
    return radius > 0 ? { shape: 'circle', x: perimeter.x, y: perimeter.y, radius } : undefined;
  }
  const left = margin - bounds.minX;
  const right = margin + bounds.maxX;
  const top = margin - bounds.minY;
  const bottom = margin + bounds.maxY;
  const w = perimeter.w - left - right;
  const h = perimeter.h - top - bottom;
  return w > 0 && h > 0 ? { shape: 'rectangle', x: perimeter.x + left, y: perimeter.y + top, w, h } : undefined;
}

export function npcAnchorInsideDomain(point: MapPoint, domain: MapAgentAreaPerimeter): boolean { return perimeterContains(domain, point.x, point.y); }

export function randomNpcAnchor(perimeter: MapAgentAreaPerimeter, body: CollisionShapeDocument, random = Math.random): MapPoint | undefined {
  const domain = npcAnchorDomain(perimeter, body);
  if (!domain) return undefined;
  const point = randomPointInPerimeter(domain, random);
  const bounds = perimeterBounds(domain);
  return Number.isFinite(point.x) && Number.isFinite(point.y) && bounds.minX <= point.x && bounds.maxX >= point.x && bounds.minY <= point.y && bounds.maxY >= point.y ? point : undefined;
}
