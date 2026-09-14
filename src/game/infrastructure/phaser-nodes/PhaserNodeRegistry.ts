import type { ResourceId } from '../../content/scenes/identifiers';
import type { JsonValue } from '../../content/scenes/types';
import type { WorldDepthBand } from '../../presentation/WorldDepth';
import type { Vector2 } from '../../runtime/scene/Node2D';
import { createCoreNodeTypeRegistry, type NodeConstructionContext, type NodeTypeRegistry } from '../../runtime/scene/registries/NodeTypeRegistry';
import type { PhaserNodeContext } from '../scenes/PhaserNodeContext';
import type { InputRouter } from '../../runtime/scene/input/InputRouter';
import { ControlNode, type ControlPresentation } from '../../runtime/scene/ui/ControlNode';
import { AnimationPlayerNode, parseAnimationLibrary } from '../../runtime/scene/animation/AnimationPlayerNode';
import type { AnimationBinding } from '../../runtime/scene/animation/AnimationBinding';
import { AudioStreamPlayerNode, type AudioPreferences, type AudioUnlockService } from './AudioStreamPlayerNode';
import { AudioStreamPlayer2DNode } from './AudioStreamPlayer2DNode';
import { Camera2DNode } from './Camera2DNode';
import { Area2DNode } from './Area2DNode';
import { CharacterBody2DNode } from './CharacterBody2DNode';
import { CollisionShape2DNode } from './CollisionShape2DNode';
import { Sprite2DNode } from './Sprite2DNode';
import { StaticBody2DNode } from './StaticBody2DNode';

function record(value: JsonValue | undefined): Readonly<Record<string, JsonValue>> | undefined {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
  return value as Readonly<Record<string, JsonValue>>;
}

function vector(value: JsonValue | undefined, fallback: Vector2): Vector2 {
  return Array.isArray(value) && value.length === 2 ? { x: Number(value[0]), y: Number(value[1]) } : fallback;
}

function textureResourceId(value: JsonValue | undefined): ResourceId {
  const reference = record(value);
  if (typeof reference?.resourceId !== 'string') throw new Error('Sprite2D requires a texture resource reference');
  return reference.resourceId as ResourceId;
}

function requiredResourceId(value: JsonValue | undefined, owner: string): ResourceId {
  const reference = record(value);
  if (typeof reference?.resourceId !== 'string') throw new Error(`${owner} requires a resource reference`);
  return reference.resourceId as ResourceId;
}

function base(context: NodeConstructionContext) {
  return {
    runtimeId: context.runtimeId,
    name: context.name,
    position: vector(context.properties.position, { x: 0, y: 0 }),
    rotation: typeof context.properties.rotation === 'number' ? context.properties.rotation : 0,
    scale: vector(context.properties.scale, { x: 1, y: 1 }),
    visible: typeof context.properties.visible === 'boolean' ? context.properties.visible : true,
  };
}

export interface PhaserNodeRegistryServices {
  readonly inputRouter?: InputRouter;
  readonly controlPresentation?: ControlPresentation;
  readonly resolveAnimationBinding?: (player: AnimationPlayerNode, binding: string, property: string) => AnimationBinding;
  readonly audioPreferences?: AudioPreferences;
  readonly audioUnlock?: AudioUnlockService;
}

function audioResource(construction: NodeConstructionContext) {
  const resourceId = requiredResourceId(construction.properties.stream, construction.type);
  const resource = construction.resources.get(resourceId);
  if (!resource || resource.kind !== 'audio') throw new Error(`${construction.type} requires audio resource '${resourceId}'`);
  return resource;
}

function themeValues(construction: NodeConstructionContext): Readonly<Record<string, JsonValue>> | undefined {
  const reference = record(construction.properties.theme);
  if (!reference) return undefined;
  const resourceId = reference.resourceId;
  if (typeof resourceId !== 'string') throw new Error('Control theme must be a resource reference');
  const resource = construction.resources.get(resourceId as ResourceId);
  if (!resource || resource.kind !== 'theme') throw new Error(`Control requires theme resource '${resourceId}'`);
  return resource.values;
}

function audioOptions(construction: NodeConstructionContext, services: PhaserNodeRegistryServices, context: PhaserNodeContext) {
  return {
    assetId: context.assetKey(audioResource(construction).assetId),
    bus: construction.properties.bus === 'music' ? 'music' as const : 'effects' as const,
    volume: typeof construction.properties.volume === 'number' ? construction.properties.volume : undefined,
    pitch: typeof construction.properties.pitch === 'number' ? construction.properties.pitch : undefined,
    loop: typeof construction.properties.loop === 'boolean' ? construction.properties.loop : undefined,
    autoplay: typeof construction.properties.autoplay === 'boolean' ? construction.properties.autoplay : undefined,
    preferences: services.audioPreferences,
    unlock: services.audioUnlock,
  };
}

export function createPhaserNodeRegistry(context: PhaserNodeContext, services: PhaserNodeRegistryServices = {}): NodeTypeRegistry {
  return createCoreNodeTypeRegistry()
    .replace('Sprite2D', (construction) => new Sprite2DNode({
      ...base(construction), context,
      texture: textureResourceId(construction.properties.texture),
      frame: typeof construction.properties.frame === 'number' ? construction.properties.frame : undefined,
      origin: vector(construction.properties.origin, { x: 0.5, y: 0.5 }),
      visualOffset: vector(construction.properties.visualOffset, { x: 0, y: 0 }),
      alpha: typeof construction.properties.alpha === 'number' ? construction.properties.alpha : 1,
      tint: typeof construction.properties.tint === 'string' ? construction.properties.tint : undefined,
      flipX: Boolean(construction.properties.flipX),
      flipY: Boolean(construction.properties.flipY),
      depthMode: construction.properties.depthMode === 'explicit' ? 'explicit' : 'world-sorted',
      depthBand: typeof construction.properties.depthBand === 'string' ? construction.properties.depthBand as WorldDepthBand : undefined,
      depth: typeof construction.properties.depth === 'number' ? construction.properties.depth : undefined,
    }))
    .replace('Camera2D', (construction) => new Camera2DNode({
      ...base(construction), context,
      zoom: typeof construction.properties.zoom === 'number' ? construction.properties.zoom : 1,
      roundPixels: typeof construction.properties.roundPixels === 'boolean' ? construction.properties.roundPixels : true,
    }))
    .replace('CharacterBody2D', (construction) => new CharacterBody2DNode({
      ...base(construction), context,
      collisionLayer: typeof construction.properties.collisionLayer === 'number' ? construction.properties.collisionLayer : undefined,
      collisionMask: typeof construction.properties.collisionMask === 'number' ? construction.properties.collisionMask : undefined,
      collisionEnabled: typeof construction.properties.collisionEnabled === 'boolean' ? construction.properties.collisionEnabled : undefined,
      velocity: vector(construction.properties.velocity, { x: 0, y: 0 }),
    }))
    .replace('StaticBody2D', (construction) => new StaticBody2DNode({
      ...base(construction), context,
      collisionLayer: typeof construction.properties.collisionLayer === 'number' ? construction.properties.collisionLayer : undefined,
      collisionMask: typeof construction.properties.collisionMask === 'number' ? construction.properties.collisionMask : undefined,
      collisionEnabled: typeof construction.properties.collisionEnabled === 'boolean' ? construction.properties.collisionEnabled : undefined,
    }))
    .replace('Area2D', (construction) => new Area2DNode({
      ...base(construction), context,
      collisionLayer: typeof construction.properties.collisionLayer === 'number' ? construction.properties.collisionLayer : undefined,
      collisionMask: typeof construction.properties.collisionMask === 'number' ? construction.properties.collisionMask : undefined,
      monitoring: typeof construction.properties.monitoring === 'boolean' ? construction.properties.monitoring : undefined,
      monitorable: typeof construction.properties.monitorable === 'boolean' ? construction.properties.monitorable : undefined,
    }))
    .replace('CollisionShape2D', (construction) => new CollisionShape2DNode({
      ...base(construction), context,
      shape: requiredResourceId(construction.properties.shape, 'CollisionShape2D'),
      disabled: typeof construction.properties.disabled === 'boolean' ? construction.properties.disabled : undefined,
      angleRad: typeof construction.properties.angleRad === 'number' ? construction.properties.angleRad : undefined,
    }))
    .replace('Control', (construction) => new ControlNode({
      runtimeId: construction.runtimeId,
      name: construction.name,
      inputRouter: services.inputRouter,
      presentation: services.controlPresentation,
      layout: {
        anchorMin: vector(construction.properties.anchorMin, { x: 0, y: 0 }),
        anchorMax: vector(construction.properties.anchorMax, { x: 0, y: 0 }),
        offsetMin: vector(construction.properties.offsetMin, { x: 0, y: 0 }),
        offsetMax: vector(construction.properties.offsetMax, { x: 0, y: 0 }),
      },
      visible: typeof construction.properties.visible === 'boolean' ? construction.properties.visible : undefined,
      focused: typeof construction.properties.focused === 'boolean' ? construction.properties.focused : undefined,
      modal: typeof construction.properties.modal === 'boolean' ? construction.properties.modal : undefined,
      consumeInput: typeof construction.properties.consumeInput === 'boolean' ? construction.properties.consumeInput : undefined,
      processWhenPaused: typeof construction.properties.processWhenPaused === 'boolean' ? construction.properties.processWhenPaused : undefined,
      inputPriority: typeof construction.properties.inputPriority === 'number' ? construction.properties.inputPriority : undefined,
      theme: themeValues(construction),
    }))
    .replace('AnimationPlayer', (construction) => {
      const libraryId = requiredResourceId(construction.properties.library, 'AnimationPlayer');
      const library = construction.resources.get(libraryId);
      if (!library || library.kind !== 'animation-library') throw new Error(`AnimationPlayer requires animation-library resource '${libraryId}'`);
      return new AnimationPlayerNode({
        runtimeId: construction.runtimeId,
        name: construction.name,
        domain: construction.properties.domain === 'physics' ? 'physics' : 'render',
        animations: parseAnimationLibrary(library.animations),
        advanceSource: context,
        autoplay: typeof construction.properties.autoplay === 'string' && construction.properties.autoplay.length > 0 ? construction.properties.autoplay : undefined,
        resolveBinding: (player, binding, property) => services.resolveAnimationBinding?.(player, binding, property)
          ?? (() => { throw new Error(`No animation binding resolver is configured for '${binding}.${property}'`); })(),
      });
    })
    .replace('AudioStreamPlayer', (construction) => new AudioStreamPlayerNode({
      runtimeId: construction.runtimeId,
      name: construction.name,
      scene: context.scene,
      ...audioOptions(construction, services, context),
    }))
    .replace('AudioStreamPlayer2D', (construction) => new AudioStreamPlayer2DNode({
      ...base(construction),
      scene: context.scene,
      ...audioOptions(construction, services, context),
      maxDistance: typeof construction.properties.maxDistance === 'number' ? construction.properties.maxDistance : undefined,
      panDistance: typeof construction.properties.panDistance === 'number' ? construction.properties.panDistance : undefined,
    }));
}
