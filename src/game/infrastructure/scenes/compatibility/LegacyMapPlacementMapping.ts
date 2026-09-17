import type { MapObjectInstance } from '../../../content/maps/mapFormat';

export interface LegacyMapObjectSceneMapping {
  readonly sceneId: string;
  readonly rootNodeId: 'body' | 'root';
  readonly scriptNodeId?: 'script';
  readonly npcDefinitionId?: string;
}

const CAMP_SCENES: Readonly<Record<string, string>> = {
  'level-1-fatty-one-eye-camp': 'encounter.level-1-fatty-camp',
};

const OBJECT_SCENES: Readonly<Record<string, LegacyMapObjectSceneMapping>> = {
  'chest.wooden': { sceneId: 'object.chest-wooden', rootNodeId: 'body', scriptNodeId: 'script' },
  'rock.amber-ore.mineable': { sceneId: 'object.rock-amber-ore-mineable', rootNodeId: 'body', scriptNodeId: 'script' },
};

const OBJECT_VISUAL_SCENES: Readonly<Record<string, Readonly<Record<string, LegacyMapObjectSceneMapping>>>> = {
  'resource.stone-node': {
    'stone-node': { sceneId: 'object.resource-stone-node', rootNodeId: 'body', scriptNodeId: 'script' },
    'big.stone.mine': { sceneId: 'object.resource-stone-node.big-stone-mine', rootNodeId: 'body', scriptNodeId: 'script' },
  },
};

const PASSIVE_OBJECTS: Readonly<Record<string, Readonly<{ baseVisual: string; rootNodeId: 'body' | 'root' }>>> = {
  'decoration.world.floor': { baseVisual: 'sewer-grate', rootNodeId: 'root' },
  'decoration.world.solid': { baseVisual: 'wood-fence', rootNodeId: 'body' },
  'house.world.solid': { baseVisual: 'barn-red', rootNodeId: 'body' },
  'rock.world-wall.decorative': { baseVisual: 'large-01', rootNodeId: 'root' },
  'rock.world-wall.solid': { baseVisual: 'large-01', rootNodeId: 'body' },
  'wall.stone.solid': { baseVisual: 'horizontal-01', rootNodeId: 'body' },
};

const NPC_SCENES: Readonly<Record<string, LegacyMapObjectSceneMapping>> = {
  'npc.world': { sceneId: 'character.village-elder-plop', rootNodeId: 'body', npcDefinitionId: 'village-elder-plop' },
  'npc.world-scout': { sceneId: 'character.mossy-scout', rootNodeId: 'body', npcDefinitionId: 'level-1-spider-giver' },
  'npc.lili': { sceneId: 'character.lili', rootNodeId: 'body', npcDefinitionId: 'lili' },
  'npc.red-slime-boy': { sceneId: 'character.red-slime-boy', rootNodeId: 'body', npcDefinitionId: 'red-slime-boy' },
  'npc.yellow-blond-slime-girl': { sceneId: 'character.yellow-blond-slime-girl', rootNodeId: 'body', npcDefinitionId: 'yellow-blond-slime-girl' },
};

export function legacyPlacementSlug(value: string): string {
  return value.replaceAll('.', '-').replace(/[^a-z0-9-]+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
}

export function resolveLegacyBossCampScene(campId: string): string | undefined {
  return CAMP_SCENES[campId];
}

export function resolveLegacyMapObjectScene(instance: MapObjectInstance): LegacyMapObjectSceneMapping | undefined {
  const npc = NPC_SCENES[instance.objectId];
  if (npc) return npc;
  if (instance.objectId.startsWith('collectible.')) {
    return { sceneId: `object.${legacyPlacementSlug(instance.objectId)}`, rootNodeId: 'root', scriptNodeId: 'script' };
  }
  if (instance.objectId === 'tree.world.solid') {
    return {
      sceneId: instance.visualId === 'shadow-pine-01'
        ? 'object.tree-world-solid'
        : `object.tree-world-solid.${legacyPlacementSlug(instance.visualId)}`,
      rootNodeId: 'body',
      scriptNodeId: 'script',
    };
  }
  const passive = PASSIVE_OBJECTS[instance.objectId];
  if (passive) {
    const baseSceneId = `object.${legacyPlacementSlug(instance.objectId)}`;
    return {
      sceneId: instance.visualId === passive.baseVisual
        ? baseSceneId
        : `${baseSceneId}.${legacyPlacementSlug(instance.visualId)}`,
      rootNodeId: passive.rootNodeId,
    };
  }
  return OBJECT_VISUAL_SCENES[instance.objectId]?.[instance.visualId] ?? OBJECT_SCENES[instance.objectId];
}
