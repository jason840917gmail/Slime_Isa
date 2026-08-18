import type { AssetId } from '../../infrastructure/assets/manifest';
import type { VisualSetId } from '../visuals/VisualCatalog';
import type { CollisionShape } from '../../shared/collisionShapes';
import amberOreMineableJson from './rocks/rock-amber-ore-mineable.json';
import worldWallDecorativeJson from './rocks/rock-world-wall-decorative.json';
import worldWallSolidJson from './rocks/rock-world-wall-solid.json';
import purpleBerryJson from './collectibles/collectible-purple-berry.json';
import decorationWorldFloorJson from './decorations/decoration-world-floor.json';
import decorationWorldSolidJson from './decorations/decoration-world-solid.json';
import houseWorldSolidJson from './houses/house-world-solid.json';
import treeWorldSolidJson from './trees/tree-world-solid.json';
import woodPileJson from './resources/resource-wood-pile.json';
import wallStoneSolidJson from './walls/wall-stone-solid.json';

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
  readonly visualSetId?: VisualSetId;
  readonly animationClip?: string;
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
  readonly variants: readonly ObjectVariantGroup[];
  readonly physics: null | { readonly body: 'static' };
  readonly behavior?: string;
  readonly destructible?: {
    readonly health: number;
    readonly drops: readonly string[];
  };
  readonly resourceNode?: {
    readonly health: number;
    readonly dropItem: string;
    readonly dropCount: number;
    readonly replacement?: {
      readonly objectId: string;
      readonly visualId: string;
    };
  };
  readonly resourcePile?: {
    readonly itemId: string;
    readonly amount: number;
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
  'resource.wood-pile': woodPileJson,
  'wall.stone.solid': wallStoneSolidJson,
} as const;

export type ObjectArchetypeId = keyof typeof OBJECT_FILES;

/** Serializable layer-three map data: definition reference plus mutable state. */
export interface ObjectInstance {
  readonly objectId: ObjectArchetypeId;
  readonly visualId: string;
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
  readonly displayName: string;
  readonly assetId: AssetId;
  readonly frame: number;
  readonly scale: number;
  readonly visualSetId?: VisualSetId;
  readonly animationClip?: string;
  readonly visualOffset: VisualOffset;
  readonly collider?: ColliderBounds;
  readonly occlusionBounds?: OcclusionBounds;
  readonly depthBounds?: DepthBounds;
  readonly physics: ObjectArchetypeDefinition['physics'];
  readonly tags: readonly string[];
}

export type EditableObjectVisual = Pick<
  ObjectVisualChoice,
  'displayName' | 'scale' | 'visualOffset' | 'collider' | 'occlusionBounds' | 'depthBounds'
>;

const OBJECT_VISUAL_OVERRIDES = new Map<string, EditableObjectVisual>();

function visualKey(objectId: ObjectArchetypeId, visualId: string): string {
  return `${objectId}::${visualId}`;
}

function createObjectVisualChoice(
  objectId: ObjectArchetypeId,
  assetId: AssetId,
  frame: ObjectFrameVariant,
): ObjectVisualChoice {
  const object = getObjectArchetype(objectId);
  const override = OBJECT_VISUAL_OVERRIDES.get(visualKey(objectId, frame.visualId));
  return {
    key: visualKey(objectId, frame.visualId),
    objectId,
    visualId: frame.visualId,
    displayName: override?.displayName ?? frame.displayName ?? frame.visualId,
    assetId,
    frame: frame.frame,
    scale: override?.scale ?? frame.scale ?? 1,
    visualSetId: frame.visualSetId,
    animationClip: frame.animationClip,
    visualOffset: override?.visualOffset ?? frame.visualOffset ?? { x: 0, y: 0 },
    collider: override?.collider ?? frame.collider,
    occlusionBounds: override?.occlusionBounds ?? frame.occlusionBounds,
    depthBounds: override?.depthBounds ?? frame.depthBounds,
    physics: object.physics,
    tags: object.tags,
  };
}

export function getObjectVisualChoices(): readonly ObjectVisualChoice[] {
  return getObjectArchetypeIds().flatMap((objectId) => {
    const object = getObjectArchetype(objectId);
    return object.variants.flatMap((variant) => variant.frames.map((frame) => (
      createObjectVisualChoice(objectId, variant.assetId, frame)
    )));
  });
}

export function getObjectVisualChoice(
  objectId: ObjectArchetypeId,
  visualId: string,
): ObjectVisualChoice | undefined {
  const object = getObjectArchetype(objectId);
  for (const variant of object.variants) {
    const frame = variant.frames.find((candidate) => candidate.visualId === visualId);
    if (frame) return createObjectVisualChoice(objectId, variant.assetId, frame);
  }
  return undefined;
}

export function setObjectVisualOverride(
  objectId: ObjectArchetypeId,
  visualId: string,
  override: EditableObjectVisual,
): void {
  OBJECT_VISUAL_OVERRIDES.set(visualKey(objectId, visualId), {
    displayName: override.displayName,
    scale: override.scale,
    visualOffset: { ...override.visualOffset },
    collider: override.collider ? { ...override.collider } : undefined,
    occlusionBounds: override.occlusionBounds ? { ...override.occlusionBounds } : undefined,
    depthBounds: override.depthBounds ? { ...override.depthBounds } : undefined,
  });
}

export function clearObjectVisualOverride(objectId: ObjectArchetypeId, visualId: string): void {
  OBJECT_VISUAL_OVERRIDES.delete(visualKey(objectId, visualId));
}

export function hasObjectVisual(objectId: ObjectArchetypeId, visualId: string): boolean {
  return getObjectArchetype(objectId).variants.some(
    (variant) => variant.frames.some((frame) => frame.visualId === visualId),
  );
}
