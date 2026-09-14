import { persistenceKey, runtimeNodeId, type PersistenceKey, type ResourceId } from '../../../content/scenes/identifiers';
import { capabilitiesForNode, descriptorMap, propertiesForNode, signalsForNode, type DescriptorRegistry } from '../../../content/scenes/propertyDescriptors';
import type { JsonValue, NodeReferenceDocument, SceneResourceDocument } from '../../../content/scenes/types';
import { Node } from '../Node';
import { NodeReference } from '../NodeReference';
import { PackedScene, type PackedNodeDocument } from '../PackedScene';
import type { NodeTypeRegistry } from '../registries/NodeTypeRegistry';
import type { ScriptRegistry } from '../registries/ScriptRegistry';

export interface SceneInstantiatorOptions {
  readonly nodeTypes: NodeTypeRegistry;
  readonly scripts?: ScriptRegistry;
  readonly descriptors: DescriptorRegistry;
}

export interface SceneInstantiationOptions {
  readonly runtimeNamespace?: string;
  readonly persistenceKey?: PersistenceKey | string;
}

let nextDynamicNamespace = 1;

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function referenceKey(scope: readonly string[], value: NodeReferenceDocument): string {
  return [...scope, ...(value.instancePath ?? []), value.nodeId].join('/');
}

function detachedRoots(nodes: Iterable<Node>): Node[] {
  return [...nodes].filter((node) => !node.get_parent());
}

export class SceneInstantiator {
  constructor(private readonly options: SceneInstantiatorOptions) {}

  instantiate_scene(packed: PackedScene, options: SceneInstantiationOptions = {}): Node {
    packed.assertUsable();
    const definition = packed.definition;
    const runtimeNamespace = options.runtimeNamespace ?? `dynamic-${nextDynamicNamespace++}`;
    const resources = new Map<ResourceId, SceneResourceDocument>(definition.resources.map((resource) => [resource.resourceId, resource]));
    const nodes = new Map<string, Node>();
    try {
      for (const source of definition.nodes) {
        const properties = structuredClone(source.properties) as Record<string, JsonValue>;
        const context = {
          runtimeId: runtimeNodeId(runtimeNamespace, source.instancePath, source.authoredNodeId),
          name: source.name,
          type: source.type,
          scriptId: source.scriptId,
          properties,
          resources,
        };
        const node = source.scriptId
          ? this.options.scripts?.construct(context) ?? (() => { throw new Error(`No script registry is configured for '${source.scriptId}'`); })()
          : this.options.nodeTypes.construct(context);
        node._setRuntimeDescriptorInternal(source.type, capabilitiesForNode(source.type, source.scriptId, this.options.descriptors));
        node._setInstanceProvenanceInternal(source.provenance ? structuredClone(source.provenance) : undefined);
        nodes.set(source.key, node);
      }

      for (const source of definition.nodes) {
        if (source.parentKey === null) continue;
        const parent = nodes.get(source.parentKey);
        const node = nodes.get(source.key);
        if (!parent || !node) throw new Error(`Packed hierarchy endpoint for '${source.key}' does not resolve`);
        parent.add_child(node);
      }

      for (const source of definition.nodes) this.configureNode(source, nodes);
      for (const connection of definition.connections) {
        const source = nodes.get(connection.sourceKey);
        const target = nodes.get(connection.targetKey);
        if (!source || !target) throw new Error('Packed signal connection endpoint does not resolve');
        const signal = source.getSignal(connection.signal);
        if (!signal) throw new Error(`Node '${source.name}' does not declare signal '${connection.signal}'`);
        signal.connect(target, connection.handler);
      }

      const root = nodes.get(definition.rootKey);
      if (!root || root.get_parent()) throw new Error(`Packed scene '${definition.sourceSceneId}' has no detached root`);
      if (options.persistenceKey !== undefined) {
        root._setPersistenceKeyInternal(typeof options.persistenceKey === 'string' ? persistenceKey(options.persistenceKey) : options.persistenceKey);
      }
      return root;
    } catch (error) {
      for (const root of detachedRoots(nodes.values())) {
        if (!root.is_freed()) root._freeDetachedSubtree(() => undefined);
      }
      throw error;
    }
  }

  instantiateScene(packed: PackedScene, options: SceneInstantiationOptions = {}): Node {
    return this.instantiate_scene(packed, options);
  }

  private configureNode(
    source: PackedNodeDocument,
    nodes: ReadonlyMap<string, Node>,
  ): void {
    const node = nodes.get(source.key);
    if (!node) throw new Error(`Packed node '${source.key}' was not constructed`);
    for (const signal of signalsForNode(source.type, source.scriptId, this.options.descriptors).values()) {
      if (!node.getSignal(signal.id)) node.createSignal(signal.id);
    }
    const descriptors = descriptorMap(propertiesForNode(source.type, source.scriptId, this.options.descriptors) ?? []);
    for (const [property, value] of Object.entries(source.properties)) {
      const descriptor = descriptors.get(property);
      if (descriptor?.value.kind !== 'node-reference') continue;
      if (!isRecord(value) || typeof value.nodeId !== 'string') throw new Error(`Node reference '${source.key}.${property}' is malformed`);
      const scope = source.propertyScopes[property] ?? source.instancePath;
      const target = nodes.get(referenceKey(scope, value as unknown as NodeReferenceDocument));
      if (descriptor.required && !target) throw new Error(`Required node reference '${source.key}.${property}' does not resolve`);
      node.defineReference(property, new NodeReference(target, descriptor.required));
    }
  }
}
