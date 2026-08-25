import { gameState } from '../../core/GameState';
import { playerInventory } from '../../systems/Inventory';
import { questTracker } from '../../quests/QuestTracker';
import { worldProgress } from '../progression/WorldProgress';
import { getAreaDefinition, type AreaDef, type AreaId, type Direction } from '../../world/Area';
import type { GameSaveData } from '../../infrastructure/persistence/SaveSchema';
import { STORAGE_KEYS } from '../../infrastructure/persistence/storageKeys';

export type RunNavigationKind = 'area' | 'load' | 'reset';

export interface RunNavigationHandoff {
  readonly version: 1;
  readonly kind: RunNavigationKind;
  readonly mapId: string;
  readonly entryEdge?: Direction;
  readonly respawnHome?: boolean;
  readonly data: GameSaveData;
}

export interface AreaNavigationRequest {
  areaId?: AreaId;
  entryEdge?: Direction;
}

export interface ResolvedAreaRequest {
  area: AreaDef;
  entryEdge?: Direction;
  respawnHome: boolean;
}

export function peekRunNavigation(): RunNavigationHandoff | null {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEYS.areaTransition);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<RunNavigationHandoff>;
    if (parsed.version !== 1 || !parsed.data || typeof parsed.mapId !== 'string') return null;
    if (parsed.kind !== 'area' && parsed.kind !== 'load' && parsed.kind !== 'reset') return null;
    return parsed as RunNavigationHandoff;
  } catch {
    return null;
  }
}

export function resolveAreaRequest(data: AreaNavigationRequest): ResolvedAreaRequest {
  const params = new URLSearchParams(window.location.search);
  const pending = peekRunNavigation();
  const queryArea = params.get('area');
  const queryEntry = params.get('entry');
  const areaId = data.areaId
    ?? pending?.mapId
    ?? (queryArea && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(queryArea) ? queryArea : 'level-1');

  return {
    area: getAreaDefinition(areaId),
    entryEdge: data.entryEdge ?? pending?.entryEdge ?? (isDirection(queryEntry) ? queryEntry : undefined),
    respawnHome: pending?.respawnHome === true || params.get('respawn') === 'home',
  };
}

export function restoreAreaTransition(): {
  restored: boolean;
  respawnHome: boolean;
  kind?: RunNavigationKind;
  data?: GameSaveData;
} {
  const pending = peekRunNavigation();
  if (!pending) return { restored: false, respawnHome: false };
  try {
    sessionStorage.removeItem(STORAGE_KEYS.areaTransition);
  } catch {
    // The handoff remains in memory for this scene even if cleanup fails.
  }
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
  entryEdge?: Direction,
  respawnHome = false,
): void {
  const handoff: RunNavigationHandoff = {
    version: 1,
    kind,
    mapId,
    ...(entryEdge ? { entryEdge } : {}),
    ...(respawnHome ? { respawnHome: true } : {}),
    data,
  };
  const previousHandoff = sessionStorage.getItem(STORAGE_KEYS.areaTransition);
  sessionStorage.setItem(STORAGE_KEYS.areaTransition, JSON.stringify(handoff));
  const nextUrl = new URL(window.location.href);
  nextUrl.searchParams.set('area', mapId);
  if (entryEdge) nextUrl.searchParams.set('entry', entryEdge);
  else nextUrl.searchParams.delete('entry');
  if (respawnHome) nextUrl.searchParams.set('respawn', 'home');
  else nextUrl.searchParams.delete('respawn');
  nextUrl.searchParams.set('t', `${Date.now()}`);
  try {
    window.location.assign(nextUrl.toString());
  } catch (error) {
    try {
      if (previousHandoff === null) sessionStorage.removeItem(STORAGE_KEYS.areaTransition);
      else sessionStorage.setItem(STORAGE_KEYS.areaTransition, previousHandoff);
    } catch {
      // Preserve the navigation error; handoff rollback is best effort.
    }
    throw error;
  }
}

export function navigateToArea(
  areaId: AreaId,
  entryEdge?: Direction,
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
  queueRunNavigation('area', handoffData, areaId, entryEdge, respawnHome);
}

export function clearOneShotNavigationParams(): void {
  const url = new URL(window.location.href);
  if (!url.searchParams.has('entry') && !url.searchParams.has('respawn') && !url.searchParams.has('t')) return;
  url.searchParams.delete('entry');
  url.searchParams.delete('respawn');
  url.searchParams.delete('t');
  window.history.replaceState({}, '', url.toString());
}

function isDirection(value: string | null): value is Direction {
  return value === 'north' || value === 'east' || value === 'south' || value === 'west';
}
