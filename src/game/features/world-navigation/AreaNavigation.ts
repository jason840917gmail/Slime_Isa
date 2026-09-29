import { gameState } from '../../core/GameState';
import { playerInventory } from '../../systems/Inventory';
import { questTracker } from '../../quests/QuestTracker';
import { worldProgress } from '../progression/WorldProgress';
import { getAreaDefinition, type AreaDef, type AreaId, type Direction } from '../../world/Area';
import type { GameSaveData } from '../../infrastructure/persistence/SaveSchema';
import {
  consumeRunNavigation,
  peekRunNavigation,
  restoreRunNavigation,
  writeRunNavigation,
  type RunNavigationHandoff,
  type RunNavigationKind,
} from '../../infrastructure/persistence/RunNavigationStore';

export { peekRunNavigation };
export type { RunNavigationHandoff, RunNavigationKind };

/** Where the player appears in the target world: a map-edge entry or a linked door. */
export interface AreaEntry {
  readonly entryEdge?: Direction;
  readonly entryDoor?: string;
}

export interface AreaNavigationRequest extends AreaEntry {
  areaId?: AreaId;
}

export interface ResolvedAreaRequest extends AreaEntry {
  area: AreaDef;
  respawnHome: boolean;
}

export function resolveAreaRequest(data: AreaNavigationRequest): ResolvedAreaRequest {
  const params = new URLSearchParams(window.location.search);
  const pending = peekRunNavigation();
  const queryArea = params.get('area');
  const queryEntry = params.get('entry');
  const queryDoor = params.get('door');
  const areaId = data.areaId
    ?? pending?.mapId
    ?? (queryArea && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(queryArea) ? queryArea : 'level-1');

  return {
    area: getAreaDefinition(areaId),
    entryEdge: data.entryEdge ?? pending?.entryEdge ?? (isDirection(queryEntry) ? queryEntry : undefined),
    entryDoor: data.entryDoor ?? pending?.entryDoor ?? (queryDoor || undefined),
    respawnHome: pending?.respawnHome === true || params.get('respawn') === 'home',
  };
}

export function restoreAreaTransition(): {
  restored: boolean;
  respawnHome: boolean;
  kind?: RunNavigationKind;
  data?: GameSaveData;
} {
  const pending = consumeRunNavigation();
  if (!pending) return { restored: false, respawnHome: false };
  return {
    restored: true,
    respawnHome: pending.respawnHome === true,
    kind: pending.kind,
    data: pending.data,
  };
}

export function queueRunNavigation(
  kind: RunNavigationKind,
  data: GameSaveData,
  mapId: string,
  entry: AreaEntry = {},
  respawnHome = false,
): void {
  const { entryEdge, entryDoor } = entry;
  const handoff: RunNavigationHandoff = {
    version: 1,
    kind,
    mapId,
    ...(entryEdge ? { entryEdge } : {}),
    ...(entryDoor ? { entryDoor } : {}),
    ...(respawnHome ? { respawnHome: true } : {}),
    data,
  };
  const previousHandoff = writeRunNavigation(handoff);
  const nextUrl = new URL(window.location.href);
  nextUrl.searchParams.set('area', mapId);
  if (entryEdge) nextUrl.searchParams.set('entry', entryEdge);
  else nextUrl.searchParams.delete('entry');
  if (entryDoor) nextUrl.searchParams.set('door', entryDoor);
  else nextUrl.searchParams.delete('door');
  if (respawnHome) nextUrl.searchParams.set('respawn', 'home');
  else nextUrl.searchParams.delete('respawn');
  nextUrl.searchParams.set('t', `${Date.now()}`);
  try {
    window.location.assign(nextUrl.toString());
  } catch (error) {
    restoreRunNavigation(previousHandoff);
    throw error;
  }
}

export function navigateToArea(
  areaId: AreaId,
  entry: AreaEntry = {},
  respawnHome = false,
  data?: GameSaveData,
): void {
  const handoffData = data ?? {
    player: gameState.serialize(),
    inventory: playerInventory.serialize(),
    quests: questTracker.serialize(),
    location: {
      areaId,
      mapId: areaId,
      x: 0,
      y: 0,
      facing: 'down' as const,
    },
    world: worldProgress.serialize(),
    playTimeMs: 0,
  };
  queueRunNavigation('area', handoffData, areaId, entry, respawnHome);
}

export function clearOneShotNavigationParams(): void {
  const url = new URL(window.location.href);
  if (!['entry', 'door', 'respawn', 't'].some((key) => url.searchParams.has(key))) return;
  url.searchParams.delete('entry');
  url.searchParams.delete('door');
  url.searchParams.delete('respawn');
  url.searchParams.delete('t');
  window.history.replaceState({}, '', url.toString());
}

function isDirection(value: string | null): value is Direction {
  return value === 'north' || value === 'east' || value === 'south' || value === 'west';
}
