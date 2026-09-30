import type { SceneDocument } from '../../content/scenes/types';
import type { PlacedFurnitureData, RespawnPointData } from '../../infrastructure/persistence/SaveSchema';

const BED_SCRIPT_ID = 'game.bed';
const PLACED_BED_PREFIX = 'placed-furniture:';
/** Nested instances deeper than this are not searched for beds. */
const MAX_INSTANCE_DEPTH = 4;

/** A bed placed from the inventory is identified by its placement record. */
export function placedBedId(placementId: string): string {
  return `${PLACED_BED_PREFIX}${placementId}`;
}

export interface BedLookup {
  scene(sceneId: string): SceneDocument | undefined;
  placedFurniture(mapId: string): readonly PlacedFurnitureData[];
}

/**
 * True when the world `mapId` still exists and, if `bedId` is given, still
 * contains that bed: an authored instance (matched by persistence key or
 * instance ID) or a placed-furniture record whose scene has a bed script.
 */
export function worldHasBed(lookup: BedLookup, mapId: string, bedId: string | undefined): boolean {
  const world = lookup.scene(`world.${mapId}`);
  if (!world) return false;
  if (bedId === undefined) return true;
  if (bedId.startsWith(PLACED_BED_PREFIX)) {
    const placementId = bedId.slice(PLACED_BED_PREFIX.length);
    const record = lookup.placedFurniture(mapId).find((placed) => placed.id === placementId);
    return record !== undefined && sceneHasBed(lookup, record.sceneId, 0);
  }
  return instancesContainBed(lookup, world, bedId, 0);
}

function instancesContainBed(lookup: BedLookup, scene: SceneDocument, bedId: string, depth: number): boolean {
  if (depth > MAX_INSTANCE_DEPTH) return false;
  for (const instance of scene.instances) {
    if ((instance.persistenceKey === bedId || instance.instanceId === bedId) && sceneHasBed(lookup, instance.sceneId, depth + 1)) return true;
    const nested = lookup.scene(instance.sceneId);
    if (nested && instancesContainBed(lookup, nested, bedId, depth + 1)) return true;
  }
  return false;
}

function sceneHasBed(lookup: BedLookup, sceneId: string, depth: number): boolean {
  if (depth > MAX_INSTANCE_DEPTH) return false;
  const scene = lookup.scene(sceneId);
  if (!scene) return false;
  return scene.nodes.some((node) => node.scriptId === BED_SCRIPT_ID)
    || scene.instances.some((instance) => sceneHasBed(lookup, instance.sceneId, depth + 1));
}

export type RespawnPlan =
  /** Wake at the saved bed (on this map or another). */
  | { readonly kind: 'bed'; readonly point: RespawnPointData }
  /** No usable bed: wake at the starting area's spawn. `staleBed` means a saved bed was lost. */
  | { readonly kind: 'start'; readonly staleBed: boolean };

/** Home is the last bed slept in, as long as its world still has it; otherwise the start. */
export function planRespawn(
  point: RespawnPointData | undefined,
  bedExists: (mapId: string, bedId: string | undefined) => boolean,
): RespawnPlan {
  if (point && bedExists(point.mapId, point.bedId)) return { kind: 'bed', point };
  return { kind: 'start', staleBed: point !== undefined };
}
