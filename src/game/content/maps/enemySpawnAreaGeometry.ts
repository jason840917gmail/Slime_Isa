import type { MapEnemySpawnArea } from './mapFormat';
import {
  closestPointInPerimeter,
  insetPerimeter,
  perimeterBounds,
  perimeterContains,
  perimeterContainsPerimeter,
  perimeterInsideMap,
  randomPointInPerimeter,
  translatePerimeter,
  type PerimeterBounds,
} from './agentAreaGeometry';

// Compatibility facade: enemy systems keep their existing imports while the
// shared agent-area geometry remains the single implementation authority.
export {
  closestPointInPerimeter,
  insetPerimeter,
  perimeterBounds,
  perimeterContains,
  perimeterContainsPerimeter,
  perimeterInsideMap,
  randomPointInPerimeter,
  translatePerimeter,
};
export type { PerimeterBounds };

export function enemySpawnAreaContainsPlayer(area: MapEnemySpawnArea, x: number, y: number): boolean {
  return perimeterContains(area.pursuePerimeter, x, y);
}
