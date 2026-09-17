import type { MapBossCamp, MapObjectInstance } from '../../../content/maps/mapFormat';
import type { SceneInstantiationPropertyOverride } from '../../../runtime/scene/resolution/SceneInstantiator';
import { resolveLegacyBossCampScene, resolveLegacyMapObjectScene } from './LegacyMapPlacementMapping';

export interface SceneEnabledPlacement {
  readonly placementId: string;
  readonly sceneId: string;
  readonly x: number;
  readonly y: number;
  readonly persistenceKey: string;
  readonly npcDefinitionId?: string;
  readonly propertyOverrides?: readonly SceneInstantiationPropertyOverride[];
}

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
      const sceneId = resolveLegacyBossCampScene(camp.id);
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
      || (this.objectSceneId(instance) !== undefined && this.sceneOwnedIds.has(instance.instanceId));
  }

  shouldSuppressLegacyBossCamp(camp: MapBossCamp): boolean {
    return this.sceneOwnedIds.has(camp.id);
  }

  standaloneObjectPlacement(instance: MapObjectInstance): SceneEnabledPlacement | undefined {
    const mapping = resolveLegacyMapObjectScene(instance);
    if (!mapping || this.sceneOwnedIds.has(instance.instanceId)) return undefined;
    this.sceneOwnedIds.add(instance.instanceId);
    return {
      placementId: instance.instanceId,
      sceneId: mapping.sceneId,
      x: instance.x,
      y: instance.y,
      persistenceKey: `${this.mapId}.${instance.instanceId}`,
      ...(mapping.npcDefinitionId ? { npcDefinitionId: mapping.npcDefinitionId } : {}),
      ...(mapping.scriptNodeId ? {
        propertyOverrides: [
          { nodeId: mapping.scriptNodeId, property: 'mapId', value: this.mapId },
          { nodeId: mapping.scriptNodeId, property: 'instanceId', value: instance.instanceId },
        ],
      } : {}),
    };
  }

  private objectSceneId(instance: MapObjectInstance): string | undefined {
    return resolveLegacyMapObjectScene(instance)?.sceneId;
  }
}
