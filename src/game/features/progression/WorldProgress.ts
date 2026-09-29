import { saveRepository } from '../../infrastructure/persistence/SaveRepository';
import { isPlacedFurniture } from '../../infrastructure/persistence/SaveSchema';
import type { BossCampProgressData, ChestProgressData, CollectibleProgressStateData, InventoryWorldDropProgressData, MapRuntimeStateData, PlacedFurnitureData, ResourceProgressStateData, RespawnPointData, WorldProgressData } from '../../infrastructure/persistence/SaveSchema';
import type { AreaId } from '../../world/Area';
import { gameEvents } from '../../core/EventBus';

export type ResourceProgressStage = 'node' | 'destroyed' | 'depleted';
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
  readonly sourceInventoryDropId?: string;
}

export type InventoryWorldDropProgress = InventoryWorldDropProgressData;

function emptyMapState(): MapRuntimeStateData {
  return {
    resources: {},
    collectibles: {},
    inventoryDrops: {},
    nextInventoryDropSequence: 1,
    bossCamps: {},
    chests: {},
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
    ...(state.sourceInventoryDropId ? { sourceInventoryDropId: state.sourceInventoryDropId } : {}),
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
    inventoryDrops: Object.fromEntries(
      Object.entries(state.inventoryDrops ?? {}).map(([id, drop]) => [id, { ...drop }]),
    ),
    nextInventoryDropSequence: state.nextInventoryDropSequence ?? 1,
    ...(state.placedFurniture && Object.keys(state.placedFurniture).length > 0 ? {
      placedFurniture: Object.fromEntries(
        Object.entries(state.placedFurniture).map(([id, furniture]) => [id, { ...furniture }]),
      ),
      nextPlacedFurnitureSequence: state.nextPlacedFurnitureSequence ?? 1,
    } : {}),
    bossCamps: Object.fromEntries(
      Object.entries(state.bossCamps ?? {}).map(([id, bossCamp]) => [id, { ...bossCamp }]),
    ),
    chests: Object.fromEntries(
      Object.entries(state.chests ?? {}).map(([id, chest]) => [id, { remaining: { ...chest.remaining } }]),
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
  private respawn?: RespawnPointData;
  private loaded = false;

  load(data: WorldProgressData): void {
    this.discoveredAreas = new Set(data.discoveredAreas ?? []);
    this.defeatedBossIds = new Set(data.defeatedBossIds ?? []);
    this.completedDungeonIds = new Set(data.completedDungeonIds ?? []);
    this.respawn = data.respawnPoint ? { ...data.respawnPoint } : undefined;
    this.mapStates = new Map();
    for (const [mapId, state] of Object.entries(data.maps ?? {})) {
      if (!state || typeof state !== 'object') continue;
      const candidate = state as Partial<MapRuntimeStateData>;
      const resources = candidate.resources && typeof candidate.resources === 'object'
        ? Object.fromEntries(
            Object.entries(candidate.resources).flatMap(([instanceId, resource]) => (
              resource && typeof resource === 'object'
                && ['node', 'destroyed', 'depleted'].includes((resource as ResourceProgressStateData).stage)
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
      const inventoryDrops = candidate.inventoryDrops && typeof candidate.inventoryDrops === 'object'
        ? Object.fromEntries(Object.entries(candidate.inventoryDrops).flatMap(([id, drop]) => (
            drop && typeof drop === 'object'
              && typeof (drop as InventoryWorldDropProgressData).itemId === 'string'
              && Number.isInteger((drop as InventoryWorldDropProgressData).amount)
              && (drop as InventoryWorldDropProgressData).amount > 0
              && Number.isFinite((drop as InventoryWorldDropProgressData).x)
              && Number.isFinite((drop as InventoryWorldDropProgressData).y)
              ? [[id, { ...(drop as InventoryWorldDropProgressData), id }]]
              : []
          )))
        : {};
      const inferredInventoryDropSequence = Math.max(1, ...Object.keys(inventoryDrops).map((id) => {
        const match = /^inventory-drop-(\d+)$/.exec(id);
        return match ? Number(match[1]) + 1 : 1;
      }));
      const placedFurniture = candidate.placedFurniture && typeof candidate.placedFurniture === 'object'
        ? Object.fromEntries(Object.entries(candidate.placedFurniture).flatMap(([id, furniture]) => (
            isPlacedFurniture(furniture) ? [[id, { ...furniture, id }]] : []
          )))
        : {};
      const inferredFurnitureSequence = Math.max(1, ...Object.keys(placedFurniture).map((id) => {
        const match = /^placed-furniture-(\d+)$/.exec(id);
        return match ? Number(match[1]) + 1 : 1;
      }));
      const bossCamps = candidate.bossCamps && typeof candidate.bossCamps === 'object'
        ? Object.fromEntries(Object.entries(candidate.bossCamps).flatMap(([id, bossCamp]) => (
            bossCamp && typeof bossCamp === 'object'
              && Number.isFinite((bossCamp as BossCampProgressData).respawnReadyAtEpochMs)
              && (bossCamp as BossCampProgressData).respawnReadyAtEpochMs >= 0
              ? [[id, { respawnReadyAtEpochMs: (bossCamp as BossCampProgressData).respawnReadyAtEpochMs }]]
              : []
          )))
        : {};
      const chests = candidate.chests && typeof candidate.chests === 'object'
        ? Object.fromEntries(Object.entries(candidate.chests).flatMap(([id, chest]) => {
            if (!chest || typeof chest !== 'object' || !('remaining' in chest)
              || !(chest as ChestProgressData).remaining || typeof (chest as ChestProgressData).remaining !== 'object') return [];
            const remaining = Object.fromEntries(Object.entries((chest as ChestProgressData).remaining).filter((entry): entry is [string, number] => (
              Number.isInteger(entry[1]) && (entry[1] as number) > 0
            )));
            return [[id, { remaining }]];
          }))
        : {};
      this.mapStates.set(mapId, {
        resources,
        collectibles,
        inventoryDrops,
        nextInventoryDropSequence: Math.max(
          inferredInventoryDropSequence,
          Number.isInteger(candidate.nextInventoryDropSequence)
            && (candidate.nextInventoryDropSequence ?? 0) >= 1
            ? candidate.nextInventoryDropSequence ?? 1
            : 1,
        ),
        ...(Object.keys(placedFurniture).length > 0 ? {
          placedFurniture,
          nextPlacedFurnitureSequence: Math.max(
            inferredFurnitureSequence,
            Number.isInteger(candidate.nextPlacedFurnitureSequence) && (candidate.nextPlacedFurnitureSequence ?? 0) >= 1
              ? candidate.nextPlacedFurnitureSequence ?? 1
              : 1,
          ),
        } : {}),
        bossCamps,
        chests,
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
      if (!state || !['node', 'destroyed', 'depleted'].includes(state.stage)) continue;
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
      ...(this.respawn ? { respawnPoint: { ...this.respawn } } : {}),
    };
  }

  /** The last bed slept in, where defeat returns the player. */
  get respawnPoint(): RespawnPointData | undefined {
    this.ensureLoaded();
    return this.respawn ? { ...this.respawn } : undefined;
  }

  setRespawnPoint(point: RespawnPointData): void {
    this.ensureLoaded();
    const current = this.respawn;
    if (current && current.mapId === point.mapId && current.x === point.x && current.y === point.y) return;
    this.respawn = { ...point };
    gameEvents.emit('world.progress.changed', {});
  }

  captureTransactionSnapshot(): WorldProgressData {
    return this.serialize();
  }

  prepareChestRemainingSnapshot(
    mapId: string,
    instanceId: string,
    remaining: Readonly<Record<string, number>>,
  ): WorldProgressData {
    const snapshot = this.serialize();
    const mapState = cloneMapState(snapshot.maps?.[mapId] ?? emptyMapState());
    const nextMapState: MapRuntimeStateData = {
      ...mapState,
      chests: {
        ...(mapState.chests ?? {}),
        [instanceId]: {
          remaining: Object.fromEntries(Object.entries(remaining).filter((entry): entry is [string, number] => (
            Number.isSafeInteger(entry[1]) && entry[1] > 0
          ))),
        },
      },
    };
    return { ...snapshot, maps: { ...(snapshot.maps ?? {}), [mapId]: nextMapState } };
  }

  prepareCollectibleRemainingSnapshot(
    mapId: string,
    instanceId: string,
    state: CollectibleProgressState,
  ): WorldProgressData {
    const snapshot = this.serialize();
    const mapState = cloneMapState(snapshot.maps?.[mapId] ?? emptyMapState());
    const nextMapState: MapRuntimeStateData = {
      ...mapState,
      collectibles: {
        ...(mapState.collectibles ?? {}),
        [instanceId]: cloneCollectibleState(state),
      },
    };
    return { ...snapshot, maps: { ...(snapshot.maps ?? {}), [mapId]: nextMapState } };
  }

  prepareGateUnlockSnapshot(mapId: string, gateId: string): WorldProgressData {
    const snapshot = this.serialize();
    const mapState = cloneMapState(snapshot.maps?.[mapId] ?? emptyMapState());
    const nextMapState = mapState.unlockedGateIds.includes(gateId)
      ? mapState
      : { ...mapState, unlockedGateIds: [...mapState.unlockedGateIds, gateId] };
    return { ...snapshot, maps: { ...(snapshot.maps ?? {}), [mapId]: nextMapState } };
  }

  installTransactionSnapshot(snapshot: WorldProgressData): void {
    this.load(snapshot);
  }

  emitTransactionChanged(): void {
    gameEvents.emit('world.progress.changed', {});
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

  inventoryDrops(mapId: string): readonly InventoryWorldDropProgress[] {
    this.ensureLoaded();
    return Object.values(this.mapStates.get(mapId)?.inventoryDrops ?? {}).map((drop) => ({ ...drop }));
  }

  createInventoryDrop(
    mapId: string,
    drop: Omit<InventoryWorldDropProgress, 'id'>,
  ): InventoryWorldDropProgress {
    this.ensureLoaded();
    const mapState = this.mapStates.get(mapId) ?? emptyMapState();
    const sequence = mapState.nextInventoryDropSequence ?? 1;
    const id = `inventory-drop-${sequence}`;
    const record = { ...drop, id };
    this.mapStates.set(mapId, {
      ...mapState,
      inventoryDrops: { ...(mapState.inventoryDrops ?? {}), [id]: record },
      nextInventoryDropSequence: sequence + 1,
    });
    gameEvents.emit('world.progress.changed', {});
    return { ...record };
  }

  setInventoryDropAmount(mapId: string, instanceId: string, amount: number): void {
    this.ensureLoaded();
    if (!Number.isFinite(amount)) return;
    const normalizedAmount = Math.max(0, Math.floor(amount));
    const mapState = this.mapStates.get(mapId);
    const current = mapState?.inventoryDrops?.[instanceId];
    if (!mapState || !current) return;
    const inventoryDrops = { ...(mapState.inventoryDrops ?? {}) };
    if (normalizedAmount > 0) inventoryDrops[instanceId] = { ...current, amount: normalizedAmount };
    else delete inventoryDrops[instanceId];
    this.mapStates.set(mapId, { ...mapState, inventoryDrops });
    gameEvents.emit('world.progress.changed', {});
  }

  placedFurniture(mapId: string): readonly PlacedFurnitureData[] {
    this.ensureLoaded();
    return Object.values(this.mapStates.get(mapId)?.placedFurniture ?? {}).map((furniture) => ({ ...furniture }));
  }

  placeFurniture(mapId: string, furniture: Omit<PlacedFurnitureData, 'id'>): PlacedFurnitureData {
    this.ensureLoaded();
    const mapState = this.mapStates.get(mapId) ?? emptyMapState();
    const sequence = mapState.nextPlacedFurnitureSequence ?? 1;
    const record: PlacedFurnitureData = { ...furniture, id: `placed-furniture-${sequence}` };
    this.mapStates.set(mapId, {
      ...mapState,
      placedFurniture: { ...(mapState.placedFurniture ?? {}), [record.id]: record },
      nextPlacedFurnitureSequence: sequence + 1,
    });
    gameEvents.emit('world.progress.changed', {});
    return { ...record };
  }

  removePlacedFurniture(mapId: string, placementId: string): PlacedFurnitureData | undefined {
    this.ensureLoaded();
    const mapState = this.mapStates.get(mapId);
    const current = mapState?.placedFurniture?.[placementId];
    if (!mapState || !current) return undefined;
    const placedFurniture = { ...(mapState.placedFurniture ?? {}) };
    delete placedFurniture[placementId];
    this.mapStates.set(mapId, { ...mapState, placedFurniture });
    gameEvents.emit('world.progress.changed', {});
    return { ...current };
  }

  clearRespawnPoint(): void {
    this.ensureLoaded();
    if (!this.respawn) return;
    this.respawn = undefined;
    gameEvents.emit('world.progress.changed', {});
  }

  bossCampRespawnReadyAt(mapId: string, campId: string): number | undefined {
    this.ensureLoaded();
    return this.mapStates.get(mapId)?.bossCamps?.[campId]?.respawnReadyAtEpochMs;
  }

  setBossCampRespawnReadyAt(mapId: string, campId: string, epochMs: number | undefined): void {
    this.ensureLoaded();
    const mapState = this.mapStates.get(mapId) ?? emptyMapState();
    const bossCamps = { ...(mapState.bossCamps ?? {}) };
    if (epochMs === undefined) delete bossCamps[campId];
    else if (Number.isFinite(epochMs) && epochMs >= 0) bossCamps[campId] = { respawnReadyAtEpochMs: epochMs };
    else return;
    this.mapStates.set(mapId, { ...mapState, bossCamps });
    gameEvents.emit('world.progress.changed', {});
  }

  chestState(mapId: string, instanceId: string): ChestProgressData | undefined {
    this.ensureLoaded();
    const state = this.mapStates.get(mapId)?.chests?.[instanceId];
    return state ? { remaining: { ...state.remaining } } : undefined;
  }

  ensureChestInitialized(mapId: string, instanceId: string, contents: Readonly<Record<string, number>>): ChestProgressData {
    this.ensureLoaded();
    const current = this.chestState(mapId, instanceId);
    if (current) return current;
    const remaining = Object.fromEntries(Object.entries(contents).filter((entry): entry is [string, number] => (
      Number.isInteger(entry[1]) && entry[1] > 0
    )));
    this.setChestRemaining(mapId, instanceId, remaining);
    return { remaining };
  }

  setChestRemaining(mapId: string, instanceId: string, remaining: Readonly<Record<string, number>>): void {
    this.ensureLoaded();
    const mapState = this.mapStates.get(mapId) ?? emptyMapState();
    const chests = { ...(mapState.chests ?? {}) };
    chests[instanceId] = {
      remaining: Object.fromEntries(Object.entries(remaining).filter((entry): entry is [string, number] => (
        Number.isInteger(entry[1]) && entry[1] > 0
      ))),
    };
    this.mapStates.set(mapId, { ...mapState, chests });
    gameEvents.emit('world.progress.changed', {});
  }

  isGateUnlocked(mapId: string, gateId: string): boolean {
    this.ensureLoaded();
    return this.mapStates.get(mapId)?.unlockedGateIds.includes(gateId) ?? false;
  }

  unlockGate(mapId: string, gateId: string): void {
    this.ensureLoaded();
    const mapState = this.mapStates.get(mapId) ?? emptyMapState();
    if (mapState.unlockedGateIds.includes(gateId)) return;
    this.mapStates.set(mapId, { ...mapState, unlockedGateIds: [...mapState.unlockedGateIds, gateId] });
    gameEvents.emit('world.progress.changed', {});
  }

  private ensureLoaded(): void {
    if (this.loaded) return;
    const saved = saveRepository.readRecovery();
    this.load(saved?.world ?? saveRepository.readLegacyWorld());
  }
}

export const worldProgress = new WorldProgress();
