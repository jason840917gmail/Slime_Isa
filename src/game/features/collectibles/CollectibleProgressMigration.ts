import type { CollectibleProgressStateData, MapRuntimeStateData } from '../../infrastructure/persistence/SaveSchema';

export interface CollectibleMigrationResult {
  readonly mapState: MapRuntimeStateData;
  readonly state?: CollectibleProgressStateData;
  readonly changed: boolean;
}

export function migrateLegacyCollectibleMapState(
  mapState: MapRuntimeStateData,
  instanceId: string,
): CollectibleMigrationResult {
  const current = mapState.collectibles?.[instanceId];
  const legacy = mapState.resources[instanceId];
  if (legacy?.stage !== 'pile' && legacy?.stage !== 'depleted') {
    return { mapState, ...(current ? { state: { ...current } } : {}), changed: false };
  }
  const state = current ?? { remaining: legacy.stage === 'pile' ? Math.max(0, Math.floor(legacy.value)) : 0 };
  const resources = { ...mapState.resources };
  delete resources[instanceId];
  return {
    mapState: {
      ...mapState,
      resources,
      collectibles: { ...(mapState.collectibles ?? {}), [instanceId]: { ...state } },
    },
    state: { ...state },
    changed: true,
  };
}
