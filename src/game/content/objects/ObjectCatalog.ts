import type { AssetId } from '../../infrastructure/assets/manifest';
import amberOreMineableJson from './rocks/rock-amber-ore-mineable.json';
import worldWallDecorativeJson from './rocks/rock-world-wall-decorative.json';
import worldWallSolidJson from './rocks/rock-world-wall-solid.json';
import purpleBerryJson from './collectibles/collectible-purple-berry.json';
import decorationWorldFloorJson from './decorations/decoration-world-floor.json';
import decorationWorldSolidJson from './decorations/decoration-world-solid.json';
import houseWorldSolidJson from './houses/house-world-solid.json';
import treeWorldSolidJson from './trees/tree-world-solid.json';

export interface ColliderBounds {
  readonly width: number;
  readonly height: number;
  readonly offsetX: number;
  readonly offsetY: number;
}

export interface ObjectFrameVariant {
  readonly visualId: string;
  readonly frame: number;
  readonly collider?: ColliderBounds;
}

export interface ObjectVariantGroup {
  readonly assetId: AssetId;
  readonly frames: readonly ObjectFrameVariant[];
}

export interface ObjectArchetypeDefinition {
  readonly objectId: ObjectArchetypeId;
  readonly selection: 'authored';
  readonly variants: readonly ObjectVariantGroup[];
  readonly physics: null | { readonly body: 'static' };
  readonly behavior?: string;
  readonly destructible?: {
    readonly health: number;
    readonly drops: readonly string[];
  };
  readonly tags: readonly string[];
}

const OBJECT_FILES = {
  'collectible.purple-berry': purpleBerryJson,
  'decoration.world.floor': decorationWorldFloorJson,
  'decoration.world.solid': decorationWorldSolidJson,
  'house.world.solid': houseWorldSolidJson,
  'rock.amber-ore.mineable': amberOreMineableJson,
  'rock.world-wall.decorative': worldWallDecorativeJson,
  'rock.world-wall.solid': worldWallSolidJson,
  'tree.world.solid': treeWorldSolidJson,
} as const;

export type ObjectArchetypeId = keyof typeof OBJECT_FILES;

/** Serializable layer-three map data: definition reference plus mutable state. */
export interface ObjectInstance {
  readonly objectId: ObjectArchetypeId;
  readonly x: number;
  readonly y: number;
  readonly state?: Readonly<Record<string, boolean | number | string>>;
}

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

export interface ObjectVisualChoice {
  readonly key: string;
  readonly objectId: ObjectArchetypeId;
  readonly visualId: string;
  readonly assetId: AssetId;
  readonly frame: number;
  readonly tags: readonly string[];
}

export function getObjectVisualChoices(): readonly ObjectVisualChoice[] {
  return getObjectArchetypeIds().flatMap((objectId) => {
    const object = getObjectArchetype(objectId);
    return object.variants.flatMap((variant) => variant.frames.map((frame) => ({
      key: `${objectId}::${frame.visualId}`,
      objectId,
      visualId: frame.visualId,
      assetId: variant.assetId,
      frame: frame.frame,
      tags: object.tags,
    })));
  });
}

export function hasObjectVisual(objectId: ObjectArchetypeId, visualId: string): boolean {
  return getObjectArchetype(objectId).variants.some(
    (variant) => variant.frames.some((frame) => frame.visualId === visualId),
  );
}
