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
    node._setRuntimeDescriptorInternal(context.type);
    return node;
  }
}

export function createCoreNodeTypeRegistry(): NodeTypeRegistry {
  const registry = new NodeTypeRegistry();
  const node2DTypes = ['Node2D', 'Sprite2D', 'CharacterBody2D', 'StaticBody2D', 'Area2D', 'CollisionShape2D', 'TileMapLayer2D', 'Camera2D'];
  // Silent audio placeholders keep the play/stop handlers authored connections target.
  const withAudioHandlers = <T extends Node>(node: T): T => {
    node.registerSignalHandler('play', () => undefined);
    node.registerSignalHandler('stop', () => undefined);
    return node;
  };
  const controlTypes = ['Control', 'Container', 'TextureRect', 'Label', 'ProgressBar', 'Slider', 'Button', 'ItemList', 'GridContainer', 'ScrollContainer', 'ModalRoot'];
  registry.register('Node', ({ runtimeId, name }) => new Node({ runtimeId, name }));
  registry.register('ScriptNode', ({ runtimeId, name }) => new Node({ runtimeId, name }));
  for (const type of controlTypes) registry.register(type, ({ runtimeId, name }) => new Node({ runtimeId, name }));
  registry.register('PhysicsBody2D', () => { throw new Error("PhysicsBody2D is abstract; use CharacterBody2D or StaticBody2D"); });
  const node2D = ({ runtimeId, name, properties }: NodeConstructionContext): Node2D => new Node2D({
    runtimeId,
    name,
    position: Array.isArray(properties.position) ? { x: Number(properties.position[0]), y: Number(properties.position[1]) } : undefined,
    rotation: typeof properties.rotation === 'number' ? properties.rotation : undefined,
    scale: Array.isArray(properties.scale) ? { x: Number(properties.scale[0]), y: Number(properties.scale[1]) } : undefined,
    visible: typeof properties.visible === 'boolean' ? properties.visible : undefined,
    depthAnchor: Array.isArray(properties.depthAnchor) ? { x: Number(properties.depthAnchor[0]), y: Number(properties.depthAnchor[1]) } : undefined,
  });
  for (const type of node2DTypes) registry.register(type, node2D);
  registry.register('AudioStreamPlayer2D', (context) => withAudioHandlers(node2D(context)));
  registry.register('AnimationPlayer', ({ runtimeId, name }) => new Node({ runtimeId, name }));
  registry.register('AudioStreamPlayer', ({ runtimeId, name }) => withAudioHandlers(new Node({ runtimeId, name })));
  return registry;
}
