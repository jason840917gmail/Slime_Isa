import type { MapBossCamp, MapObjectInstance } from '../../../content/maps/mapFormat';
import type { SceneInstantiationPropertyOverride } from '../../../runtime/scene/resolution/SceneInstantiator';

export interface SceneEnabledPlacement {
  readonly placementId: string;
  readonly sceneId: string;
  readonly x: number;
  readonly y: number;
  readonly persistenceKey: string;
  readonly npcDefinitionId?: string;
  readonly propertyOverrides?: readonly SceneInstantiationPropertyOverride[];
}

const CAMP_SCENES: Readonly<Record<string, string>> = {
  'level-1-fatty-one-eye-camp': 'encounter.level-1-fatty-camp',
};

const OBJECT_SCENES: Readonly<Record<string, string>> = {
  'chest.wooden': 'object.chest-wooden',
};

const OBJECT_VISUAL_SCENES: Readonly<Record<string, Readonly<Record<string, string>>>> = {
  'resource.stone-node': {
    'stone-node': 'object.resource-stone-node',
    'big.stone.mine': 'object.resource-stone-node.big-stone-mine',
  },
};

const NPC_SCENES: Readonly<Record<string, Readonly<{ sceneId: string; npcDefinitionId: string }>>> = {
  'npc.world': { sceneId: 'character.village-elder-plop', npcDefinitionId: 'village-elder-plop' },
  'npc.world-scout': { sceneId: 'character.mossy-scout', npcDefinitionId: 'level-1-spider-giver' },
  'npc.lili': { sceneId: 'character.lili', npcDefinitionId: 'lili' },
  'npc.red-slime-boy': { sceneId: 'character.red-slime-boy', npcDefinitionId: 'red-slime-boy' },
  'npc.yellow-blond-slime-girl': { sceneId: 'character.yellow-blond-slime-girl', npcDefinitionId: 'yellow-blond-slime-girl' },
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
      || (this.objectSceneId(instance) !== undefined && this.sceneOwnedIds.has(instance.instanceId));
  }

  shouldSuppressLegacyBossCamp(camp: MapBossCamp): boolean {
    return this.sceneOwnedIds.has(camp.id);
  }

  standaloneObjectPlacement(instance: MapObjectInstance): SceneEnabledPlacement | undefined {
    const npc = NPC_SCENES[instance.objectId];
    const sceneId = npc?.sceneId ?? this.objectSceneId(instance);
    if (!sceneId || this.sceneOwnedIds.has(instance.instanceId)) return undefined;
    this.sceneOwnedIds.add(instance.instanceId);
    return {
      placementId: instance.instanceId,
      sceneId,
      x: instance.x,
      y: instance.y,
      persistenceKey: `${this.mapId}.${instance.instanceId}`,
      ...(npc ? { npcDefinitionId: npc.npcDefinitionId } : {}),
      ...(!npc && instance.objectId === 'resource.stone-node' ? {
        propertyOverrides: [
          { nodeId: 'script', property: 'mapId', value: this.mapId },
          { nodeId: 'script', property: 'instanceId', value: instance.instanceId },
        ],
      } : {}),
    };
  }

  private objectSceneId(instance: MapObjectInstance): string | undefined {
    return OBJECT_VISUAL_SCENES[instance.objectId]?.[instance.visualId] ?? OBJECT_SCENES[instance.objectId];
  }
}
