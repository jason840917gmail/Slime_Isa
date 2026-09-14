import type { ResourceId } from '../../content/scenes/identifiers';
import type { JsonValue } from '../../content/scenes/types';
import type { WorldDepthBand } from '../../presentation/WorldDepth';
import type { Vector2 } from '../../runtime/scene/Node2D';
import { createCoreNodeTypeRegistry, type NodeConstructionContext, type NodeTypeRegistry } from '../../runtime/scene/registries/NodeTypeRegistry';
import type { PhaserNodeContext } from '../scenes/PhaserNodeContext';
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

export function createPhaserNodeRegistry(context: PhaserNodeContext): NodeTypeRegistry {
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
    }));
}
