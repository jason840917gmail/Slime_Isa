import type { MapDirection, MapExit, MapPoint, MapZone } from '../content/maps/mapFormat';
import type { EditableMap } from './MapEditorState';

export const MAP_DIRECTIONS: readonly MapDirection[] = ['north', 'east', 'south', 'west'];

export const OPPOSITE_DIRECTION: Readonly<Record<MapDirection, MapDirection>> = {
  north: 'south',
  east: 'west',
  south: 'north',
  west: 'east',
};

export function isMapDirection(value: unknown): value is MapDirection {
  return typeof value === 'string' && MAP_DIRECTIONS.includes(value as MapDirection);
}

/**
 * Reports the direction implied by a zone's geometry alone. This is useful
 * for diagnostics, but saved connections must use their entry field as the
 * authoritative direction because older maps may contain stale geometry.
 */
export function edgeDirectionForZone(
  zone: MapZone,
  map: Pick<EditableMap, 'size' | 'tileSize'>,
): MapDirection | undefined {
  const width = map.size.columns * map.tileSize;
  const height = map.size.rows * map.tileSize;
  const epsilon = 1;
  const touchesWest = zone.x <= epsilon;
  const touchesEast = zone.x + zone.w >= width - epsilon;
  const touchesNorth = zone.y <= epsilon;
  const touchesSouth = zone.y + zone.h >= height - epsilon;
  const spansHeight = zone.h >= height - epsilon;
  const spansWidth = zone.w >= width - epsilon;

  if (spansHeight && touchesWest && !touchesEast) return 'west';
  if (spansHeight && touchesEast && !touchesWest) return 'east';
  if (spansWidth && touchesNorth && !touchesSouth) return 'north';
  if (spansWidth && touchesSouth && !touchesNorth) return 'south';

  const touched = [
    touchesNorth ? 'north' : undefined,
    touchesEast ? 'east' : undefined,
    touchesSouth ? 'south' : undefined,
    touchesWest ? 'west' : undefined,
  ].filter((direction): direction is MapDirection => direction !== undefined);
  return touched.length === 1 ? touched[0] : undefined;
}

export function edgeExitZone(direction: MapDirection, map: Pick<EditableMap, 'size' | 'tileSize'>): MapZone {
  const width = map.size.columns * map.tileSize;
  const height = map.size.rows * map.tileSize;
  const lane = Math.max(1, Math.min(32, Math.floor(map.tileSize / 2)));
  if (direction === 'west') return { x: 0, y: 0, w: lane, h: height };
  if (direction === 'east') return { x: width - lane, y: 0, w: lane, h: height };
  if (direction === 'north') return { x: 0, y: 0, w: width, h: lane };
  return { x: 0, y: height - lane, w: width, h: lane };
}

export function edgeEntryPoint(direction: MapDirection, map: Pick<EditableMap, 'size' | 'tileSize'>): MapPoint {
  const width = map.size.columns * map.tileSize;
  const height = map.size.rows * map.tileSize;
  const inset = Math.min(map.tileSize * 4, Math.min(width, height) / 3);
  if (direction === 'west') return { x: inset, y: height / 2 };
  if (direction === 'east') return { x: width - inset, y: height / 2 };
  if (direction === 'north') return { x: width / 2, y: inset };
  return { x: width / 2, y: height - inset };
}

export function exitDirection(
  exit: Pick<MapExit, 'entry'>,
  _map: Pick<EditableMap, 'size' | 'tileSize'>,
): MapDirection | undefined {
  if (!isMapDirection(exit.entry)) return undefined;
  return OPPOSITE_DIRECTION[exit.entry];
}

export function connectionAt(direction: MapDirection, map: EditableMap): EditableMap['exits'][number] | undefined {
  return map.exits.find((exit) => exitDirection(exit, map) === direction);
}
