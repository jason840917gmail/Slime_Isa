import Phaser from 'phaser';

import {
  getObjectArchetype,
  type ColliderBounds,
  type ObjectArchetypeId,
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
  readonly collider?: ColliderBounds;
}

function resolveVisual(objectId: ObjectArchetypeId, visualId: string): ResolvedVisual {
  const archetype = getObjectArchetype(objectId);
  const resolved = archetype.variants
    .map((variation) => ({
      variation,
      frameVariant: variation.frames.find((frame) => frame.visualId === visualId),
    }))
    .find((candidate) => candidate.frameVariant);
  if (!resolved?.frameVariant) {
    throw new Error(`Object '${objectId}' has no authored visual '${visualId}'`);
  }
  const { variation, frameVariant } = resolved;
  const asset = getAsset(variation.assetId);
  const frame = asset.source.kind === 'spritesheet' ? frameVariant.frame : undefined;

  if (asset.source.kind !== 'spritesheet' && asset.source.kind !== 'procedural') {
    throw new Error(`Object '${objectId}' requires spritesheet or procedural media from '${variation.assetId}'`);
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
    collider: frameVariant.collider,
  };
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
      body.setOffset(visual.collider.offsetX, visual.collider.offsetY);
    } else if (behaviorGroup) {
      (image as Phaser.Physics.Arcade.Image).refreshBody();
    }

    return image;
  }
}
