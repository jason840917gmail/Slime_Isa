import type { MapDirection, MapExit, MapPoint, MapZone } from '../content/maps/mapFormat';
import type { EditableMap } from './MapEditorState';

export const MAP_DIRECTIONS: readonly MapDirection[] = ['north', 'east', 'south', 'west'];

export const OPPOSITE_DIRECTION: Readonly<Record<MapDirection, MapDirection>> = {
  north: 'south',
  east: 'west',
  south: 'north',
  west: 'east',
};

export function edgeExitZone(direction: MapDirection, map: Pick<EditableMap, 'size' | 'tileSize'>): MapZone {
  const width = map.size.columns * map.tileSize;
  const height = map.size.rows * map.tileSize;
  const lane = Math.min(32, map.tileSize / 2);
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

export function exitDirection(exit: Pick<MapExit, 'zone'>, map: Pick<EditableMap, 'size' | 'tileSize'>): MapDirection | undefined {
  const width = map.size.columns * map.tileSize;
  const height = map.size.rows * map.tileSize;
  const epsilon = 1;
  if (exit.zone.x <= epsilon && exit.zone.h >= height - epsilon) return 'west';
  if (exit.zone.x + exit.zone.w >= width - epsilon && exit.zone.h >= height - epsilon) return 'east';
  if (exit.zone.y <= epsilon && exit.zone.w >= width - epsilon) return 'north';
  if (exit.zone.y + exit.zone.h >= height - epsilon && exit.zone.w >= width - epsilon) return 'south';
  return undefined;
}

export function connectionAt(direction: MapDirection, map: EditableMap): EditableMap['exits'][number] | undefined {
  return map.exits.find((exit) => exitDirection(exit, map) === direction);
}
