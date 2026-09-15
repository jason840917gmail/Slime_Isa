import type { MapBossCamp, MapObjectInstance } from '../../../content/maps/mapFormat';

export interface SceneEnabledPlacement {
  readonly placementId: string;
  readonly sceneId: string;
  readonly x: number;
  readonly y: number;
  readonly persistenceKey: string;
}

const CAMP_SCENES: Readonly<Record<string, string>> = {
  'level-1-fatty-one-eye-camp': 'encounter.level-1-fatty-camp',
};

const OBJECT_SCENES: Readonly<Record<string, string>> = {
  'chest.wooden': 'object.chest-wooden',
};

export class LegacyMapPlacementBridge {
  private readonly sceneOwnedIds = new Set<string>();
  private placements?: readonly SceneEnabledPlacement[];

  constructor(
    private readonly mapId: string,
    private readonly objects: readonly MapObjectInstance[],
    private readonly camps: readonly MapBossCamp[],
  ) {}

  scenePlacements(): readonly SceneEnabledPlacement[] {
    if (this.placements) return this.placements;
    const placements: SceneEnabledPlacement[] = [];
    for (const camp of this.camps) {
      const sceneId = CAMP_SCENES[camp.id];
      if (!sceneId) continue;
      this.sceneOwnedIds.add(camp.id);
      if (camp.guardedChestInstanceId) this.sceneOwnedIds.add(camp.guardedChestInstanceId);
      placements.push({
        placementId: camp.id,
        sceneId,
        x: camp.activationPerimeter.x,
        y: camp.activationPerimeter.y,
        persistenceKey: camp.id,
      });
    }
    for (const instance of this.objects) {
      const placement = this.standaloneObjectPlacement(instance);
      if (placement) placements.push(placement);
    }
    this.placements = Object.freeze(placements);
    return this.placements;
  }

  shouldSuppressLegacyObject(instance: MapObjectInstance): boolean {
    return this.sceneOwnedIds.has(instance.instanceId)
      || (OBJECT_SCENES[instance.objectId] !== undefined && this.sceneOwnedIds.has(instance.instanceId));
  }

  shouldSuppressLegacyBossCamp(camp: MapBossCamp): boolean {
    return this.sceneOwnedIds.has(camp.id);
  }

  standaloneObjectPlacement(instance: MapObjectInstance): SceneEnabledPlacement | undefined {
    const sceneId = OBJECT_SCENES[instance.objectId];
    if (!sceneId || this.sceneOwnedIds.has(instance.instanceId)) return undefined;
    this.sceneOwnedIds.add(instance.instanceId);
    return {
      placementId: instance.instanceId,
      sceneId,
      x: instance.x,
      y: instance.y,
      persistenceKey: `${this.mapId}.${instance.instanceId}`,
    };
  }
}
