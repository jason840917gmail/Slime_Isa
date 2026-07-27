import Phaser from 'phaser';

import {
  getObjectArchetype,
  getObjectVisualChoice,
  type ColliderBounds,
  type ObjectArchetypeId,
  type VisualOffset,
} from '../../content/objects/ObjectCatalog';
import { getAsset } from '../../infrastructure/assets/manifest';
import { getVisualClip, type VisualSetId } from '../../content/visuals/VisualCatalog';
import { AnimatedVisual } from '../visuals/AnimatedVisual';
import {
  resolveExplicitDepth,
  resolveWorldDepth,
  type DepthMode,
} from '../../presentation/WorldDepth';
import type {
  SourceFrameDimensions,
  SourceOcclusionBounds,
} from '../../presentation/WorldOcclusion';

export interface ObjectOccluderRegistration {
  readonly id: string;
  readonly owner: Phaser.GameObjects.Image;
  readonly sourceFrame: SourceFrameDimensions;
  readonly bounds: SourceOcclusionBounds;
  readonly getDepth: () => number;
}

export interface CreateObjectOptions {
  readonly x: number;
  readonly y: number;
  readonly visualId: string;
  readonly depth?: number;
  readonly depthMode?: DepthMode;
  readonly sortId?: string;
  readonly initialState?: Readonly<Record<string, unknown>>;
}

interface ObjectFactoryContext {
  readonly scene: Phaser.Scene;
  readonly staticGroup: Phaser.Physics.Arcade.StaticGroup;
  readonly behaviorGroups?: Readonly<Record<string, Phaser.Physics.Arcade.StaticGroup>>;
  readonly physicsEnabled?: boolean;
  readonly animatedVisualsEnabled?: boolean;
  readonly registerOccluder?: (registration: ObjectOccluderRegistration) => { dispose(): void };
}

interface ResolvedVisual {
  readonly textureKey: string;
  readonly frame?: number;
  readonly visualSetId?: VisualSetId;
  readonly animationClip?: string;
  readonly origin: readonly [number, number];
  readonly visualOffset: VisualOffset;
  readonly collider?: ColliderBounds;
  readonly occlusionBounds?: SourceOcclusionBounds;
  readonly sourceFrame?: SourceFrameDimensions;
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
    visualSetId: choice.visualSetId,
    animationClip: choice.animationClip,
    origin: configuredOrigin
      ? [configuredOrigin[0], configuredOrigin[1]]
      : [0.5, 1],
    visualOffset: choice.visualOffset,
    collider: choice.collider,
    occlusionBounds: choice.occlusionBounds,
    sourceFrame: 'frame' in asset.source
      ? { width: asset.source.frame.w, height: asset.source.frame.h }
      : undefined,
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
  if (image.getData('depthMode') !== 'explicit') {
    image.setDepth(resolveWorldDepth(y, {
      stableId: String(image.getData('sortId') ?? image.getData('objectId') ?? 'object'),
    }).depth);
  }
  const body = image.body as Phaser.Physics.Arcade.StaticBody | Phaser.Physics.Arcade.Body | null;
  if (body) {
    if ('updateFromGameObject' in body && typeof body.updateFromGameObject === 'function') {
      body.updateFromGameObject();
    }
  }
  (image.getData('animatedVisual') as AnimatedVisual | undefined)?.update();
}

export function setObjectDepthMode(
  image: Phaser.GameObjects.Image,
  mode: DepthMode,
  explicitDepth?: number,
): void {
  image.setData('depthMode', mode);
  if (mode === 'explicit') {
    image.setDepth(explicitDepth ?? resolveExplicitDepth('editor-drag-lift'));
    return;
  }
  const [x, y] = getObjectAnchor(image);
  setObjectAnchor(image, x, y);
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
    image.setData('objectId', objectId);
    image.setData('sortId', options.sortId ?? `${objectId}:${options.x}:${options.y}`);
    image.setData('depthMode', options.depthMode ?? 'world-sorted');
    setObjectAnchor(image, options.x, options.y);
    if (options.depthMode === 'explicit') {
      image.setDepth(options.depth ?? image.depth);
    }
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

    if (
      visual.visualSetId
      && visual.animationClip
      && this.ctx.animatedVisualsEnabled !== false
    ) {
      const animatedVisual = new AnimatedVisual(
        this.ctx.scene,
        image,
        visual.visualSetId,
        {
          depth: image.depth,
          getDepth: () => image.depth,
          initialFrame: visual.frame,
        },
      );
      animatedVisual.play(
        getVisualClip(visual.visualSetId, visual.animationClip).runtimeKey,
      );
      image.setData('animatedVisual', animatedVisual);
      image.setVisible(false);
    }

    if (visual.occlusionBounds && visual.sourceFrame && this.ctx.registerOccluder) {
      const registration = this.ctx.registerOccluder({
        id: String(image.getData('sortId')),
        owner: image,
        sourceFrame: visual.sourceFrame,
        bounds: visual.occlusionBounds,
        getDepth: () => image.depth,
      });
      image.setData('occlusionRegistration', registration);
    }

    return image;
  }
}
