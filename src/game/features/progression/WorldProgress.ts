import { saveRepository } from '../../infrastructure/persistence/SaveRepository';
import type { WorldProgressData } from '../../infrastructure/persistence/SaveSchema';
import type { AreaId } from '../../world/Area';
import { gameEvents } from '../../core/EventBus';

class WorldProgress {
  private discoveredAreas = new Set<AreaId>();
  private defeatedBossIds = new Set<string>();
  private completedDungeonIds = new Set<string>();
  private loaded = false;

  load(data: WorldProgressData): void {
    this.discoveredAreas = new Set(data.discoveredAreas);
    this.defeatedBossIds = new Set(data.defeatedBossIds);
    this.completedDungeonIds = new Set(data.completedDungeonIds);
    this.loaded = true;
  }

  serialize(): WorldProgressData {
    this.ensureLoaded();
    return {
      discoveredAreas: [...this.discoveredAreas],
      defeatedBossIds: [...this.defeatedBossIds],
      completedDungeonIds: [...this.completedDungeonIds],
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

  private ensureLoaded(): void {
    if (this.loaded) return;
    const saved = saveRepository.read();
    this.load(saved?.data.world ?? saveRepository.readLegacyWorld());
  }
}

export const worldProgress = new WorldProgress();
