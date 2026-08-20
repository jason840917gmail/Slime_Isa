import { saveRepository } from '../../infrastructure/persistence/SaveRepository';
import type { WorldProgressData } from '../../infrastructure/persistence/SaveSchema';
import type { AreaId } from '../../world/Area';
import { gameEvents } from '../../core/EventBus';

export type ResourceProgressStage = 'node' | 'pile' | 'destroyed' | 'depleted';
export interface ResourcePileProgress {
  readonly id: string;
  readonly cellX: number;
  readonly cellY: number;
  readonly amount: number;
}
export interface ResourceProgressState {
  readonly stage: ResourceProgressStage;
  readonly value: number;
  readonly piles?: readonly ResourcePileProgress[];
}

class WorldProgress {
  private discoveredAreas = new Set<AreaId>();
  private defeatedBossIds = new Set<string>();
  private completedDungeonIds = new Set<string>();
  private resourceStates = new Map<string, ResourceProgressState>();
  private loaded = false;

  load(data: WorldProgressData): void {
    this.discoveredAreas = new Set(data.discoveredAreas);
    this.defeatedBossIds = new Set(data.defeatedBossIds);
    this.completedDungeonIds = new Set(data.completedDungeonIds);
    this.resourceStates = new Map();
    for (const [key, state] of Object.entries(data.resourceStates ?? {})) {
      if (!state || typeof state !== 'object') continue;
      if (
        state.stage !== 'node'
        && state.stage !== 'pile'
        && state.stage !== 'destroyed'
        && state.stage !== 'depleted'
      ) continue;
      if (typeof state.value !== 'number' || !Number.isFinite(state.value) || state.value < 0) continue;
      const piles = Array.isArray(state.piles)
        ? state.piles.flatMap((pile) => {
            if (!pile || typeof pile !== 'object') return [];
            if (
              typeof pile.id !== 'string'
              || !pile.id
              || !Number.isInteger(pile.cellX)
              || !Number.isInteger(pile.cellY)
              || typeof pile.amount !== 'number'
              || !Number.isFinite(pile.amount)
              || pile.amount < 0
            ) return [];
            return [{
              id: pile.id,
              cellX: pile.cellX,
              cellY: pile.cellY,
              amount: Math.max(0, pile.amount),
            }];
          })
        : undefined;
      this.resourceStates.set(key, {
        stage: state.stage,
        value: Math.max(0, state.value),
        ...(piles && piles.length > 0 ? { piles } : {}),
      });
    }
    this.loaded = true;
  }

  serialize(): WorldProgressData {
    this.ensureLoaded();
    return {
      discoveredAreas: [...this.discoveredAreas],
      defeatedBossIds: [...this.defeatedBossIds],
      completedDungeonIds: [...this.completedDungeonIds],
      resourceStates: Object.fromEntries(
        [...this.resourceStates.entries()].map(([key, state]) => [key, {
          stage: state.stage,
          value: state.value,
          ...(state.piles ? { piles: state.piles.map((pile) => ({ ...pile })) } : {}),
        }]),
      ),
    };
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
    return this.resourceStates.get(`${mapId}:${instanceId}`);
  }

  setResourceState(mapId: string, instanceId: string, state: ResourceProgressState): void {
    this.ensureLoaded();
    const key = `${mapId}:${instanceId}`;
    const previous = this.resourceStates.get(key);
    const normalized: ResourceProgressState = {
      stage: state.stage,
      value: Math.max(0, state.value),
      ...(state.piles && state.piles.length > 0
        ? { piles: state.piles.map((pile) => ({ ...pile, amount: Math.max(0, pile.amount) })) }
        : {}),
    };
    if (JSON.stringify(previous) === JSON.stringify(normalized)) return;
    this.resourceStates.set(key, normalized);
    gameEvents.emit('world.progress.changed', {});
  }

  private ensureLoaded(): void {
    if (this.loaded) return;
    const saved = saveRepository.read();
    this.load(saved?.data.world ?? saveRepository.readLegacyWorld());
  }
}

export const worldProgress = new WorldProgress();
