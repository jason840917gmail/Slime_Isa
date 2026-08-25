import { saveRepository } from '../../infrastructure/persistence/SaveRepository';
import type { CollectibleProgressStateData, MapRuntimeStateData, ResourceProgressStateData, WorldProgressData } from '../../infrastructure/persistence/SaveSchema';
import type { AreaId } from '../../world/Area';
import { gameEvents } from '../../core/EventBus';
import { migrateLegacyCollectibleMapState } from '../collectibles/CollectibleProgressMigration';

export type ResourceProgressStage = 'node' | 'pile' | 'destroyed' | 'depleted';
export interface ResourcePileProgress {
  readonly id: string;
  readonly cellX: number;
  readonly cellY: number;
  readonly amount: number;
  readonly offsetX?: number;
  readonly offsetY?: number;
  readonly objectId?: string;
  readonly visualId?: string;
}
export interface ResourceProgressState {
  readonly stage: ResourceProgressStage;
  readonly value: number;
  readonly piles?: readonly ResourcePileProgress[];
}

export interface CollectibleProgressState {
  readonly remaining: number;
  readonly sourceResourceInstanceId?: string;
}

function emptyMapState(): MapRuntimeStateData {
  return {
    resources: {},
    collectibles: {},
    completedEncounterIds: [],
    openedRewardIds: [],
    unlockedGateIds: [],
    objectStates: {},
  };
}

function cloneResourceState(state: ResourceProgressStateData): ResourceProgressState {
  return {
    stage: state.stage,
    value: Math.max(0, state.value),
    ...(state.piles && state.piles.length > 0
      ? { piles: state.piles.map((pile) => ({ ...pile, amount: Math.max(0, pile.amount) })) }
      : {}),
  };
}

function cloneCollectibleState(state: CollectibleProgressStateData): CollectibleProgressState {
  return {
    remaining: Math.max(0, Math.floor(state.remaining)),
    ...(state.sourceResourceInstanceId ? { sourceResourceInstanceId: state.sourceResourceInstanceId } : {}),
  };
}

function cloneMapState(state: MapRuntimeStateData): MapRuntimeStateData {
  return {
    resources: Object.fromEntries(
      Object.entries(state.resources).flatMap(([instanceId, resource]) => (
        resource && typeof resource === 'object' ? [[instanceId, cloneResourceState(resource)]] : []
      )),
    ),
    collectibles: Object.fromEntries(
      Object.entries(state.collectibles ?? {}).flatMap(([instanceId, collectible]) => (
        collectible && typeof collectible === 'object' ? [[instanceId, cloneCollectibleState(collectible)]] : []
      )),
    ),
    completedEncounterIds: [...state.completedEncounterIds],
    openedRewardIds: [...state.openedRewardIds],
    unlockedGateIds: [...state.unlockedGateIds],
    objectStates: Object.fromEntries(
      Object.entries(state.objectStates).map(([instanceId, value]) => [instanceId, structuredClone(value)]),
    ),
  };
}

export class WorldProgress {
  private discoveredAreas = new Set<AreaId>();
  private defeatedBossIds = new Set<string>();
  private completedDungeonIds = new Set<string>();
  private mapStates = new Map<string, MapRuntimeStateData>();
  private loaded = false;

  load(data: WorldProgressData): void {
    this.discoveredAreas = new Set(data.discoveredAreas ?? []);
    this.defeatedBossIds = new Set(data.defeatedBossIds ?? []);
    this.completedDungeonIds = new Set(data.completedDungeonIds ?? []);
    this.mapStates = new Map();
    for (const [mapId, state] of Object.entries(data.maps ?? {})) {
      if (!state || typeof state !== 'object') continue;
      const candidate = state as Partial<MapRuntimeStateData>;
      const resources = candidate.resources && typeof candidate.resources === 'object'
        ? Object.fromEntries(
            Object.entries(candidate.resources).flatMap(([instanceId, resource]) => (
              resource && typeof resource === 'object'
                && ['node', 'pile', 'destroyed', 'depleted'].includes((resource as ResourceProgressStateData).stage)
                && typeof (resource as ResourceProgressStateData).value === 'number'
                && Number.isFinite((resource as ResourceProgressStateData).value)
                ? [[instanceId, cloneResourceState(resource as ResourceProgressStateData)]]
                : []
            )),
          )
        : {};
      const collectibles = candidate.collectibles && typeof candidate.collectibles === 'object'
        ? Object.fromEntries(
            Object.entries(candidate.collectibles).flatMap(([instanceId, collectible]) => (
              collectible && typeof collectible === 'object'
                && typeof (collectible as CollectibleProgressStateData).remaining === 'number'
                && Number.isFinite((collectible as CollectibleProgressStateData).remaining)
                && Number.isInteger((collectible as CollectibleProgressStateData).remaining)
                ? [[instanceId, cloneCollectibleState(collectible as CollectibleProgressStateData)]]
                : []
            )),
          )
        : {};
      this.mapStates.set(mapId, {
        resources,
        collectibles,
        completedEncounterIds: Array.isArray(candidate.completedEncounterIds)
          ? candidate.completedEncounterIds.filter((id): id is string => typeof id === 'string') : [],
        openedRewardIds: Array.isArray(candidate.openedRewardIds)
          ? candidate.openedRewardIds.filter((id): id is string => typeof id === 'string') : [],
        unlockedGateIds: Array.isArray(candidate.unlockedGateIds)
          ? candidate.unlockedGateIds.filter((id): id is string => typeof id === 'string') : [],
        objectStates: candidate.objectStates && typeof candidate.objectStates === 'object'
          ? Object.fromEntries(Object.entries(candidate.objectStates).map(([id, value]) => [id, structuredClone(value)]))
          : {},
      });
    }

    // v4 stored composite resource keys. Keep this one migration at the
    // progress boundary so every future feature can use map-scoped state.
    for (const [key, state] of Object.entries(data.resourceStates ?? {})) {
      const separator = key.indexOf(':');
      if (separator <= 0 || separator === key.length - 1) continue;
      const mapId = key.slice(0, separator);
      const instanceId = key.slice(separator + 1);
      if (!state || !['node', 'pile', 'destroyed', 'depleted'].includes(state.stage)) continue;
      const mapState = this.mapStates.get(mapId) ?? emptyMapState();
      mapState.resources[instanceId] = cloneResourceState(state);
      this.mapStates.set(mapId, mapState);
    }
    this.loaded = true;
  }

  serialize(): WorldProgressData {
    this.ensureLoaded();
    return {
      discoveredAreas: [...this.discoveredAreas],
      defeatedBossIds: [...this.defeatedBossIds],
      completedDungeonIds: [...this.completedDungeonIds],
      maps: Object.fromEntries(
        [...this.mapStates.entries()].map(([mapId, state]) => [mapId, cloneMapState(state)]),
      ),
    };
  }

  stateForMap(mapId: string): Readonly<MapRuntimeStateData> {
    this.ensureLoaded();
    return cloneMapState(this.mapStates.get(mapId) ?? emptyMapState());
  }

  serializeMaps(): Record<string, MapRuntimeStateData> {
    this.ensureLoaded();
    return Object.fromEntries(
      [...this.mapStates.entries()].map(([mapId, state]) => [mapId, cloneMapState(state)]),
    );
  }

  clearMap(mapId: string): void {
    this.ensureLoaded();
    if (!this.mapStates.delete(mapId)) return;
    gameEvents.emit('world.progress.changed', {});
  }

  resetAllMaps(): void {
    this.ensureLoaded();
    if (this.mapStates.size === 0) return;
    this.mapStates.clear();
    gameEvents.emit('world.progress.changed', {});
  }

  discoverArea(areaId: AreaId): void {
    this.ensureLoaded();
    if (this.discoveredAreas.has(areaId)) return;
    this.discoveredAreas.add(areaId);
    gameEvents.emit('world.progress.changed', {});
  }

  discovered(): ReadonlySet<AreaId> {
    this.ensureLoaded();
    return this.discoveredAreas;
  }

  defeatBoss(bossId: string): void {
    this.ensureLoaded();
    if (this.defeatedBossIds.has(bossId)) return;
    this.defeatedBossIds.add(bossId);
    gameEvents.emit('world.progress.changed', {});
  }

  isBossDefeated(bossId: string): boolean {
    this.ensureLoaded();
    return this.defeatedBossIds.has(bossId);
  }

  completeDungeon(dungeonId: string): void {
    this.ensureLoaded();
    if (this.completedDungeonIds.has(dungeonId)) return;
    this.completedDungeonIds.add(dungeonId);
    gameEvents.emit('world.progress.changed', {});
  }

  isDungeonCompleted(dungeonId: string): boolean {
    this.ensureLoaded();
    return this.completedDungeonIds.has(dungeonId);
  }

  resourceState(mapId: string, instanceId: string): ResourceProgressState | undefined {
    this.ensureLoaded();
    const state = this.mapStates.get(mapId)?.resources[instanceId];
    return state ? cloneResourceState(state) : undefined;
  }

  setResourceState(mapId: string, instanceId: string, state: ResourceProgressState): void {
    this.ensureLoaded();
    const mapState = this.mapStates.get(mapId) ?? emptyMapState();
    const previous = mapState.resources[instanceId];
    const normalized = cloneResourceState(state);
    if (JSON.stringify(previous) === JSON.stringify(normalized)) return;
    mapState.resources[instanceId] = normalized;
    this.mapStates.set(mapId, mapState);
    gameEvents.emit('world.progress.changed', {});
  }

  collectibleState(mapId: string, instanceId: string): CollectibleProgressState | undefined {
    this.ensureLoaded();
    const state = this.mapStates.get(mapId)?.collectibles?.[instanceId];
    return state ? cloneCollectibleState(state) : undefined;
  }

  /**
   * Converts the old authored resource-pile state in place when the same map
   * instance is now backed by a collectible archetype. Generated resource
   * drops remain owned by their source node and never pass through this path.
   */
  migrateLegacyCollectibleState(mapId: string, instanceId: string): CollectibleProgressState | undefined {
    this.ensureLoaded();
    const mapState = this.mapStates.get(mapId);
    if (!mapState) return undefined;
    const migration = migrateLegacyCollectibleMapState(mapState, instanceId);
    if (migration.changed) {
      this.mapStates.set(mapId, migration.mapState);
      gameEvents.emit('world.progress.changed', {});
    }
    return migration.state ? cloneCollectibleState(migration.state) : undefined;
  }

  setCollectibleState(mapId: string, instanceId: string, state: CollectibleProgressState): void {
    this.ensureLoaded();
    const mapState = this.mapStates.get(mapId) ?? emptyMapState();
    const collectibles = mapState.collectibles ?? {};
    const normalized = cloneCollectibleState(state);
    if (JSON.stringify(collectibles[instanceId]) === JSON.stringify(normalized)) return;
    collectibles[instanceId] = normalized;
    this.mapStates.set(mapId, { ...mapState, collectibles });
    gameEvents.emit('world.progress.changed', {});
  }

  private ensureLoaded(): void {
    if (this.loaded) return;
    const saved = saveRepository.readRecovery();
    this.load(saved?.world ?? saveRepository.readLegacyWorld());
  }
}

export const worldProgress = new WorldProgress();
