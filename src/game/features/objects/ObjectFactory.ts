import Phaser from 'phaser';

import {
  getObjectArchetype,
  getObjectVisualChoice,
  type ColliderBounds,
  type ObjectArchetypeId,
  type VisualOffset,
} from '../../content/objects/ObjectCatalog';
import { getAsset } from '../../infrastructure/assets/manifest';

export interface CreateObjectOptions {
  readonly x: number;
  readonly y: number;
  readonly visualId: string;
  readonly depth?: number;
  readonly initialState?: Readonly<Record<string, unknown>>;
}

interface ObjectFactoryContext {
  readonly scene: Phaser.Scene;
  readonly staticGroup: Phaser.Physics.Arcade.StaticGroup;
  readonly behaviorGroups?: Readonly<Record<string, Phaser.Physics.Arcade.StaticGroup>>;
  readonly physicsEnabled?: boolean;
}

interface ResolvedVisual {
  readonly textureKey: string;
  readonly frame?: number;
  readonly origin: readonly [number, number];
  readonly visualOffset: VisualOffset;
  readonly collider?: ColliderBounds;
}

function resolveVisual(objectId: ObjectArchetypeId, visualId: string): ResolvedVisual {
  const choice = getObjectVisualChoice(objectId, visualId);
  if (!choice) {
    throw new Error(`Object '${objectId}' has no authored visual '${visualId}'`);
  }
  const asset = getAsset(choice.assetId);
  const frame = asset.source.kind === 'spritesheet' ? choice.frame : undefined;

  if (asset.source.kind !== 'spritesheet' && asset.source.kind !== 'procedural') {
    throw new Error(`Object '${objectId}' requires spritesheet or procedural media from '${choice.assetId}'`);
  }

  const configuredOrigin = 'render' in asset && Array.isArray(asset.render.origin)
    ? asset.render.origin
    : undefined;

  return {
    textureKey: asset.runtime.textureKey,
    frame,
    origin: configuredOrigin
      ? [configuredOrigin[0], configuredOrigin[1]]
      : [0.5, 1],
    visualOffset: choice.visualOffset,
    collider: choice.collider,
  };
}

export function getObjectAnchor(image: Phaser.GameObjects.Image): readonly [number, number] {
  return [
    image.getData('objectAnchorX') as number ?? image.x,
    image.getData('objectAnchorY') as number ?? image.y,
  ];
}

export function setObjectAnchor(image: Phaser.GameObjects.Image, x: number, y: number): void {
  const visualOffset = image.getData('visualOffset') as VisualOffset | undefined;
  image.setPosition(x + (visualOffset?.x ?? 0), y + (visualOffset?.y ?? 0));
  image.setData('objectAnchorX', x);
  image.setData('objectAnchorY', y);
  const body = image.body as Phaser.Physics.Arcade.StaticBody | Phaser.Physics.Arcade.Body | null;
  if (body) {
    if ('updateFromGameObject' in body && typeof body.updateFromGameObject === 'function') {
      body.updateFromGameObject();
    }
  }
}

/** Creates an object from immutable content data without coupling it to a scene class. */
export class ObjectFactory {
  constructor(private readonly ctx: ObjectFactoryContext) {}

  create(objectId: ObjectArchetypeId, options: CreateObjectOptions): Phaser.GameObjects.Image {
    const archetype = getObjectArchetype(objectId);
    const visual = resolveVisual(objectId, options.visualId);
    const behaviorGroup = archetype.behavior
      ? this.ctx.behaviorGroups?.[archetype.behavior]
      : undefined;
    const image = archetype.physics && this.ctx.physicsEnabled !== false
      ? this.ctx.staticGroup.create(options.x, options.y, visual.textureKey, visual.frame) as Phaser.Physics.Arcade.Image
      : behaviorGroup
        ? behaviorGroup.create(options.x, options.y, visual.textureKey, visual.frame) as Phaser.Physics.Arcade.Image
      : this.ctx.scene.add.image(options.x, options.y, visual.textureKey, visual.frame);

    image.setOrigin(visual.origin[0], visual.origin[1]);
    image.setData('visualOffset', visual.visualOffset);
    setObjectAnchor(image, options.x, options.y);
    image.setDepth(options.depth ?? 2);
    image.setData('objectId', objectId);
    for (const [key, value] of Object.entries(options.initialState ?? {})) {
      image.setData(key, value);
    }

    if (archetype.physics && this.ctx.physicsEnabled !== false) {
      const physicsImage = image as Phaser.Physics.Arcade.Image;
      physicsImage.refreshBody();
      if (!visual.collider) {
        throw new Error(`Solid object '${objectId}' has no collider for its selected frame`);
      }
      const body = physicsImage.body as Phaser.Physics.Arcade.StaticBody;
      body.setSize(visual.collider.width, visual.collider.height);
      body.setOffset(
        visual.collider.offsetX - visual.visualOffset.x,
        visual.collider.offsetY - visual.visualOffset.y,
      );
    } else if (behaviorGroup) {
      (image as Phaser.Physics.Arcade.Image).refreshBody();
    }

    return image;
  }
}
