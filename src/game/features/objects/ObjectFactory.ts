import Phaser from 'phaser';

import {
  getObjectArchetype,
  getObjectVisualChoice,
  type ColliderBounds,
  type DepthBounds,
  type ObjectArchetypeId,
  type VisualOffset,
} from '../../content/objects/ObjectCatalog';
import { getAsset } from '../../infrastructure/assets/manifest';
import { animationDefinitionResolver } from '../../content/animations/AnimationCatalog';
import { ObjectAnimationAdapter } from './ObjectAnimationAdapter';
import {
  resolveExplicitDepth,
  resolveObjectDepthAnchorY,
  resolveWorldDepth,
  type DepthMode,
} from '../../presentation/WorldDepth';
import type {
  SourceFrameDimensions,
  SourceOcclusionBounds,
} from '../../presentation/WorldOcclusion';
import { resolveCollisionShapeDimensions } from '../../shared/collisionShapes';

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
  readonly idleAnimationId?: string;
  readonly onHitAnimationId?: string;
  readonly origin: readonly [number, number];
  readonly scale: number;
  readonly visualOffset: VisualOffset;
  readonly collider?: ColliderBounds;
  readonly occlusionBounds?: SourceOcclusionBounds;
  readonly depthBounds?: DepthBounds;
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
    idleAnimationId: choice.idleAnimationId,
    onHitAnimationId: choice.onHitAnimationId,
    origin: configuredOrigin
      ? [configuredOrigin[0], configuredOrigin[1]]
      : [0.5, 1],
    scale: choice.scale,
    visualOffset: choice.visualOffset,
    collider: choice.collider,
    occlusionBounds: choice.occlusionBounds,
    depthBounds: choice.depthBounds,
    sourceFrame: 'frame' in asset.source
      ? { width: asset.source.frame.w, height: asset.source.frame.h }
      : undefined,
  };
}

function applyResolvedVisual(
  image: Phaser.GameObjects.Image,
  objectId: ObjectArchetypeId,
  visual: ResolvedVisual,
): void {
  image.setTexture(visual.textureKey, visual.frame);
  image.setOrigin(visual.origin[0], visual.origin[1]);
  image.setScale(visual.scale);
  image.setData('visualOffset', visual.visualOffset);
  image.setData('visualScale', visual.scale);
  image.setData('objectId', objectId);
  image.setData('sourceFrame', visual.sourceFrame);
  image.setData('occlusionBounds', visual.occlusionBounds);
  image.setData('depthBounds', visual.depthBounds);
  image.setData('idleAnimationId', visual.idleAnimationId);
  image.setData('onHitAnimationId', visual.onHitAnimationId);
}

export function getObjectAnchor(image: Phaser.GameObjects.Image): readonly [number, number] {
  return [
    image.getData('objectAnchorX') as number ?? image.x,
    image.getData('objectAnchorY') as number ?? image.y,
  ];
}

export function setObjectAnchor(image: Phaser.GameObjects.Image, x: number, y: number): void {
  const visualOffset = image.getData('visualOffset') as VisualOffset | undefined;
  const scaleX = Math.abs(image.scaleX);
  const scaleY = Math.abs(image.scaleY);
  const sourceFrame = image.getData('sourceFrame') as SourceFrameDimensions | undefined;
  const depthBounds = image.getData('depthBounds') as DepthBounds | undefined;
  image.setPosition(
    x + (visualOffset?.x ?? 0) * scaleX,
    y + (visualOffset?.y ?? 0) * scaleY,
  );
  image.setData('objectAnchorX', x);
  image.setData('objectAnchorY', y);
  const depthAnchorY = sourceFrame
    ? resolveObjectDepthAnchorY(y, {
      sourceFrameHeight: sourceFrame.height,
      originY: image.originY,
      bounds: depthBounds,
      scaleY,
    })
    : y;
  image.setData('depthAnchorY', depthAnchorY);
  if (image.getData('depthMode') !== 'explicit') {
    image.setDepth(resolveWorldDepth(depthAnchorY, {
      stableId: String(image.getData('sortId') ?? image.getData('objectId') ?? 'object'),
    }).depth);
  }
  const body = image.body as Phaser.Physics.Arcade.StaticBody | Phaser.Physics.Arcade.Body | null;
  if (body) {
    if ('updateFromGameObject' in body && typeof body.updateFromGameObject === 'function') {
      body.updateFromGameObject();
    }
  }
  (image.getData('objectAnimationAdapter') as ObjectAnimationAdapter | undefined)?.updateAnchor();
}

/** Applies a reusable object visual to an existing image while preserving its world anchor. */
export function applyObjectVisual(
  image: Phaser.GameObjects.Image,
  objectId: ObjectArchetypeId,
  visualId: string,
): void {
  const visual = resolveVisual(objectId, visualId);
  const [anchorX, anchorY] = getObjectAnchor(image);
  (image.getData('objectAnimationAdapter') as ObjectAnimationAdapter | undefined)?.dispose();
  image.setData('objectAnimationAdapter', undefined);
  image.setVisible(true);
  applyResolvedVisual(image, objectId, visual);
  setObjectAnchor(image, anchorX, anchorY);
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
  private readonly animationAdapters = new Set<ObjectAnimationAdapter>();

  constructor(private readonly ctx: ObjectFactoryContext) {
    ctx.scene.events.on(Phaser.Scenes.Events.UPDATE, this.handleSceneUpdate);
    ctx.scene.events.once(Phaser.Scenes.Events.SHUTDOWN, this.handleSceneShutdown);
  }

  update(deltaMs: number): void {
    for (const adapter of this.animationAdapters) adapter.update(deltaMs);
  }

  destroy(): void {
    this.ctx.scene.events.off(Phaser.Scenes.Events.UPDATE, this.handleSceneUpdate);
    this.ctx.scene.events.off(Phaser.Scenes.Events.SHUTDOWN, this.handleSceneShutdown);
    for (const adapter of this.animationAdapters) adapter.dispose();
    this.animationAdapters.clear();
  }

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

    applyResolvedVisual(image, objectId, visual);
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
      const collider = visual.collider;
      const dimensions = resolveCollisionShapeDimensions(collider);
      const scaleX = Math.abs(image.scaleX);
      const scaleY = Math.abs(image.scaleY);
      if (dimensions.shape === 'circle') {
        body.setCircle(
          (dimensions.radius ?? Math.min(collider.width, collider.height) / 2) * Math.min(scaleX, scaleY),
          (collider.offsetX - visual.visualOffset.x) * scaleX,
          (collider.offsetY - visual.visualOffset.y) * scaleY,
        );
      } else {
        // Arcade has no native ellipse. Its authored bounds remain a safe
        // conservative fallback for static world collision.
        body.setSize(dimensions.width * scaleX, dimensions.height * scaleY, false);
        body.setOffset(
          (collider.offsetX - visual.visualOffset.x) * scaleX,
          (collider.offsetY - visual.visualOffset.y) * scaleY,
        );
      }
    } else if (behaviorGroup) {
      (image as Phaser.Physics.Arcade.Image).refreshBody();
    }

    if (
      (visual.idleAnimationId || visual.onHitAnimationId)
      && this.ctx.animatedVisualsEnabled !== false
    ) {
      try {
        const adapter = new ObjectAnimationAdapter({
          scene: this.ctx.scene,
          anchor: image,
          resolver: animationDefinitionResolver,
          objectId,
          idleAnimationId: visual.idleAnimationId,
          onHitAnimationId: visual.onHitAnimationId,
        });
        this.animationAdapters.add(adapter);
        image.setData('objectAnimationAdapter', adapter);
        image.once('destroy', () => {
          adapter.dispose();
          this.animationAdapters.delete(adapter);
        });
      } catch (error) {
        image.setVisible(true);
        if (import.meta.env.DEV) {
          console.warn(`Object '${objectId}' shared animation fell back to its static image.`, error);
        }
      }
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

  private readonly handleSceneUpdate = (_time: number, delta: number): void => {
    this.update(delta);
  };

  private readonly handleSceneShutdown = (): void => {
    this.destroy();
  };
}
