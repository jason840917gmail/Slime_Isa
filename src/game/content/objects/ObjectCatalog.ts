import type { AssetId } from '../../infrastructure/assets/manifest';
import type { CollisionShape } from '../../shared/collisionShapes';
import amberOreMineableJson from './rocks/rock-amber-ore-mineable.json';
import worldWallDecorativeJson from './rocks/rock-world-wall-decorative.json';
import worldWallSolidJson from './rocks/rock-world-wall-solid.json';
import purpleBerryJson from './collectibles/collectible-purple-berry.json';
import charcoalPileJson from './collectibles/collectible-charcoal-pile.json';
import ironOrePileJson from './collectibles/collectible-iron-ore-pile.json';
import hpPotionJson from './collectibles/collectible-hp-potion.json';
import berryBasketJson from './collectibles/collectible-berry-basket.json';
import energyPotionJson from './collectibles/collectible-energy-potion.json';
import silkClumpJson from './collectibles/collectible-silk-clump.json';
import crystalShardJson from './collectibles/collectible-crystal-shard.json';
import greenKeyJson from './collectibles/collectible-green-key.json';
import smallStonePileJson from './collectibles/collectible-small-stone-pile.json';
import smallWoodPileJson from './collectibles/collectible-small-wood-pile.json';
import decorationWorldFloorJson from './decorations/decoration-world-floor.json';
import decorationWorldSolidJson from './decorations/decoration-world-solid.json';
import houseWorldSolidJson from './houses/house-world-solid.json';
import treeWorldSolidJson from './trees/tree-world-solid.json';
import woodPileJson from './collectibles/collectible-wood-pile.json';
import stoneNodeJson from './resources/resource-stone-node.json';
import stonePileJson from './collectibles/collectible-stone-pile.json';
import wallStoneSolidJson from './walls/wall-stone-solid.json';
import npcWorldJson from './npcs/npc-world.json';
import npcWorldScoutJson from './npcs/npc-world-scout.json';
import npcLiliJson from './npcs/npc-lili.json';
import npcRedSlimeBoyJson from './npcs/npc-red-slime-boy.json';
import npcYellowBlondSlimeGirlJson from './npcs/npc-yellow-blond-slime-girl.json';
import chestWoodenJson from './chests/chest-wooden.json';

export interface ColliderBounds {
  readonly shape?: CollisionShape;
  readonly width: number;
  readonly height: number;
  readonly radius?: number;
  readonly radiusX?: number;
  readonly radiusY?: number;
  readonly offsetX: number;
  readonly offsetY: number;
}

export interface OcclusionBounds {
  readonly width: number;
  readonly height: number;
  readonly offsetX: number;
  readonly offsetY: number;
}

/** Source-frame rectangle whose lower edge supplies the object's sort anchor. */
export interface DepthBounds {
  readonly width: number;
  readonly height: number;
  readonly offsetX: number;
  readonly offsetY: number;
}

export interface VisualOffset {
  readonly x: number;
  readonly y: number;
}

export interface ObjectFrameVariant {
  readonly visualId: string;
  readonly displayName?: string;
  readonly frame: number;
  /** Uniform world scale applied to the visual and its authored geometry. */
  readonly scale?: number;
  readonly idleAnimationId?: string;
  readonly onHitAnimationId?: string;
  readonly visualOffset?: VisualOffset;
  readonly collider?: ColliderBounds;
  readonly occlusionBounds?: OcclusionBounds;
  readonly depthBounds?: DepthBounds;
}

export interface ObjectVariantGroup {
  readonly assetId: AssetId;
  readonly frames: readonly ObjectFrameVariant[];
}

export interface ObjectArchetypeDefinition {
  readonly objectId: ObjectArchetypeId;
  readonly selection: 'authored';
  readonly variants?: readonly ObjectVariantGroup[];
  readonly physics: null | { readonly body: 'static' };
  readonly behavior?: string;
  readonly collectible?: {
    readonly itemId: string;
    readonly quantity: number;
  };
  readonly destructible?: {
    readonly health: number;
    readonly drops: readonly string[];
  };
  readonly resourceNode?: {
    readonly health: number;
    readonly drop: {
      readonly objectId: string;
      readonly visualId: string;
      readonly pieces: number;
    };
    /** Optional material-oriented feedback package played after positive damage. */
    readonly hitEffectId?: string;
    readonly persistHealth?: boolean;
    readonly depletionMessage?: string;
    readonly harvestRequirement?: {
      readonly targetTag: string;
      readonly minimumTier: number;
      readonly failureMessage: string;
    };
  };
  /** Reusable authored container. Instance contents live in map initialState. */
  readonly chest?: true;
  /** Optional authored quest/dialogue identity for interactable NPC objects. */
  readonly npc?: {
    readonly definitionId: string;
    readonly placementVisualId: string;
  };
  readonly tags: readonly string[];
}

const OBJECT_FILES = {
  'chest.wooden': chestWoodenJson,
  'collectible.charcoal-pile': charcoalPileJson,
  'collectible.iron-ore-pile': ironOrePileJson,
  'collectible.hp-potion': hpPotionJson,
  'collectible.berry-basket': berryBasketJson,
  'collectible.energy-potion': energyPotionJson,
  'collectible.silk-clump': silkClumpJson,
  'collectible.crystal-shard': crystalShardJson,
  'collectible.green-key': greenKeyJson,
  'collectible.purple-berry': purpleBerryJson,
  'collectible.small-stone-pile': smallStonePileJson,
  'collectible.small-wood-pile': smallWoodPileJson,
  'decoration.world.floor': decorationWorldFloorJson,
  'decoration.world.solid': decorationWorldSolidJson,
  'house.world.solid': houseWorldSolidJson,
  'rock.amber-ore.mineable': amberOreMineableJson,
  'rock.world-wall.decorative': worldWallDecorativeJson,
  'rock.world-wall.solid': worldWallSolidJson,
  'tree.world.solid': treeWorldSolidJson,
  'collectible.wood-pile': woodPileJson,
  'resource.stone-node': stoneNodeJson,
  'collectible.stone-pile': stonePileJson,
  'wall.stone.solid': wallStoneSolidJson,
  'npc.world': npcWorldJson,
  'npc.world-scout': npcWorldScoutJson,
  'npc.lili': npcLiliJson,
  'npc.red-slime-boy': npcRedSlimeBoyJson,
  'npc.yellow-blond-slime-girl': npcYellowBlondSlimeGirlJson,
} as const;

export type ObjectArchetypeId = keyof typeof OBJECT_FILES;

const OBJECTS = OBJECT_FILES as unknown as Readonly<
  Record<ObjectArchetypeId, ObjectArchetypeDefinition>
>;

export function getObjectArchetype(objectId: ObjectArchetypeId): ObjectArchetypeDefinition {
  return OBJECTS[objectId];
}

export function getObjectArchetypeIds(): readonly ObjectArchetypeId[] {
  return Object.keys(OBJECTS) as ObjectArchetypeId[];
}

export function isObjectArchetypeId(value: string): value is ObjectArchetypeId {
  return value in OBJECTS;
}

export function hasObjectVisual(objectId: ObjectArchetypeId, visualId: string): boolean {
  return (getObjectArchetype(objectId).variants ?? []).some(
    (variant) => variant.frames.some((frame) => frame.visualId === visualId),
  );
}
