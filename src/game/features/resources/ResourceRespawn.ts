import type { ResourceProgressStateData } from '../../infrastructure/persistence/SaveSchema';

export interface ResourceRespawnResolution {
  /** The state to keep; `undefined` means the node grows back as authored. */
  readonly state: ResourceProgressStateData | undefined;
  /** True when the saved state must be rewritten (timer started, or node regrown). */
  readonly changed: boolean;
}

/**
 * Harvested resource nodes come back `respawnMs` after they were depleted,
 * the next time their map loads. A node regrows only once every pile it
 * dropped is collected (stage `depleted`), so new drops never collide with
 * old ones. Nodes depleted before timers existed start their timer now, so
 * nothing ever returns early.
 */
export function resolveResourceRespawn(
  state: ResourceProgressStateData | undefined,
  nowEpochMs: number,
  respawnMs: number,
): ResourceRespawnResolution {
  if (!state || state.stage === 'node') return { state, changed: false };
  if (state.respawnReadyAtEpochMs === undefined) {
    return { state: { ...state, respawnReadyAtEpochMs: nowEpochMs + respawnMs }, changed: true };
  }
  if (state.stage === 'depleted' && nowEpochMs >= state.respawnReadyAtEpochMs) return { state: undefined, changed: true };
  return { state, changed: false };
}
