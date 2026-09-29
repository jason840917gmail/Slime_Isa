import type { Direction } from '../../world/Area';
import type { GameSaveData } from './SaveSchema';
import { STORAGE_KEYS } from './storageKeys';

export type RunNavigationKind = 'area' | 'load' | 'reset';

export interface RunNavigationHandoff {
  readonly version: 1;
  readonly kind: RunNavigationKind;
  readonly mapId: string;
  readonly entryEdge?: Direction;
  /** Door ID in the target world whose arrival point the player appears at. */
  readonly entryDoor?: string;
  readonly respawnHome?: boolean;
  readonly data: GameSaveData;
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

export function consumeRunNavigation(): RunNavigationHandoff | null {
  const pending = peekRunNavigation();
  if (!pending) return null;
  try {
    sessionStorage.removeItem(STORAGE_KEYS.areaTransition);
  } catch {
    // The handoff remains available to the current scene if cleanup fails.
  }
  return pending;
}

export function writeRunNavigation(handoff: RunNavigationHandoff): string | null {
  const previous = sessionStorage.getItem(STORAGE_KEYS.areaTransition);
  sessionStorage.setItem(STORAGE_KEYS.areaTransition, JSON.stringify(handoff));
  return previous;
}

export function restoreRunNavigation(previous: string | null): void {
  try {
    if (previous === null) sessionStorage.removeItem(STORAGE_KEYS.areaTransition);
    else sessionStorage.setItem(STORAGE_KEYS.areaTransition, previous);
  } catch {
    // Preserve the original navigation failure; rollback is best effort.
  }
}
