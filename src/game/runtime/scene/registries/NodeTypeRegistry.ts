import type { JsonValue, SceneResourceDocument } from '../../../content/scenes/types';
import type { ResourceId, RuntimeNodeId } from '../../../content/scenes/identifiers';
import { Node } from '../Node';
import { Node2D } from '../Node2D';

export interface NodeConstructionContext {
  readonly runtimeId: RuntimeNodeId;
  readonly name: string;
  readonly type: string;
  readonly scriptId?: string;
  readonly properties: Readonly<Record<string, JsonValue>>;
  readonly resources: ReadonlyMap<ResourceId, SceneResourceDocument>;
}

export type NodeFactory = (context: NodeConstructionContext) => Node;

export class NodeTypeRegistry {
  private readonly factories = new Map<string, NodeFactory>();

  register(type: string, factory: NodeFactory): this {
    if (this.factories.has(type)) throw new Error(`Node type '${type}' is already registered`);
    this.factories.set(type, factory);
    return this;
  }

  replace(type: string, factory: NodeFactory): this {
    if (!this.factories.has(type)) throw new Error(`Node type '${type}' is not registered`);
    this.factories.set(type, factory);
    return this;
  }

  has(type: string): boolean { return this.factories.has(type); }

  construct(context: NodeConstructionContext): Node {
    const factory = this.factories.get(context.type);
    if (!factory) throw new Error(`No runtime constructor is registered for node type '${context.type}'`);
    const node = factory(context);
    if (node.runtimeId !== context.runtimeId || node.name !== context.name) throw new Error(`Node factory '${context.type}' changed immutable identity`);
    return node;
  }
}

export function createCoreNodeTypeRegistry(): NodeTypeRegistry {
  const registry = new NodeTypeRegistry();
  const node2DTypes = ['Node2D', 'Sprite2D', 'PhysicsBody2D', 'CharacterBody2D', 'StaticBody2D', 'Area2D', 'CollisionShape2D', 'TileMapLayer2D', 'Camera2D', 'AudioStreamPlayer2D', 'Control'];
  registry.register('Node', ({ runtimeId, name }) => new Node({ runtimeId, name }));
  registry.register('ScriptNode', ({ runtimeId, name }) => new Node({ runtimeId, name }));
  for (const type of node2DTypes) registry.register(type, ({ runtimeId, name, properties }) => new Node2D({
    runtimeId,
    name,
    position: Array.isArray(properties.position) ? { x: Number(properties.position[0]), y: Number(properties.position[1]) } : undefined,
    rotation: typeof properties.rotation === 'number' ? properties.rotation : undefined,
    scale: Array.isArray(properties.scale) ? { x: Number(properties.scale[0]), y: Number(properties.scale[1]) } : undefined,
    visible: typeof properties.visible === 'boolean' ? properties.visible : undefined,
  }));
  for (const type of ['AnimationPlayer', 'AudioStreamPlayer']) registry.register(type, ({ runtimeId, name }) => new Node({ runtimeId, name }));
  return registry;
}
