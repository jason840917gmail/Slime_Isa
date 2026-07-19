import { gameState } from '../../core/GameState';
import { STORAGE_KEYS } from '../../infrastructure/persistence/storageKeys';
import { playerInventory } from '../../systems/Inventory';
import { getAreaDefinition, type AreaDef, type AreaId, type Direction } from '../../world/Area';

export interface AreaNavigationRequest {
  areaId?: AreaId;
  entryEdge?: Direction;
}

export interface ResolvedAreaRequest {
  area: AreaDef;
  entryEdge?: Direction;
  respawnHome: boolean;
}

export function resolveAreaRequest(data: AreaNavigationRequest): ResolvedAreaRequest {
  const params = new URLSearchParams(window.location.search);
  const queryArea = params.get('area');
  const queryEntry = params.get('entry');
  const areaId = data.areaId
    ?? (queryArea && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(queryArea) ? queryArea : 'icege');

  return {
    area: getAreaDefinition(areaId),
    entryEdge: data.entryEdge ?? (isDirection(queryEntry) ? queryEntry : undefined),
    respawnHome: params.get('respawn') === 'home',
  };
}

export function restoreAreaTransition(): { restored: boolean; respawnHome: boolean } {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEYS.areaTransition);
    if (!raw) return { restored: false, respawnHome: false };
    sessionStorage.removeItem(STORAGE_KEYS.areaTransition);
    const parsed = JSON.parse(raw) as {
      gameState?: ReturnType<typeof gameState.serialize>;
      inventory?: ReturnType<typeof playerInventory.serialize>;
      respawnHome?: boolean;
    };
    if (parsed.gameState) gameState.load(parsed.gameState);
    if (parsed.inventory) playerInventory.load(parsed.inventory);
    return { restored: true, respawnHome: parsed.respawnHome === true };
  } catch {
    return { restored: false, respawnHome: false };
  }
}

export function navigateToArea(areaId: AreaId, entryEdge?: Direction, respawnHome = false): void {
  try {
    sessionStorage.setItem(STORAGE_KEYS.areaTransition, JSON.stringify({
      gameState: gameState.serialize(),
      inventory: playerInventory.serialize(),
      respawnHome,
    }));
  } catch {
    // Navigation still works if session storage is unavailable.
  }

  const nextUrl = new URL(window.location.href);
  nextUrl.searchParams.set('area', areaId);
  if (entryEdge) nextUrl.searchParams.set('entry', entryEdge);
  else nextUrl.searchParams.delete('entry');
  if (respawnHome) nextUrl.searchParams.set('respawn', 'home');
  else nextUrl.searchParams.delete('respawn');
  nextUrl.searchParams.set('t', `${Date.now()}`);
  window.location.assign(nextUrl.toString());
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
