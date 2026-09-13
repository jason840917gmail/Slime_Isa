import type { DescriptorRegistry, PropertyDescriptor } from '../../../content/scenes/propertyDescriptors';
import { capabilitiesForNode, descriptorMap, handlersForScript, nodeTypeIs, propertiesForNode, signalsForNode } from '../../../content/scenes/propertyDescriptors';
import type { InstanceId, ResourceId, SceneId } from '../../../content/scenes/identifiers';
import type {
  JsonValue,
  NodeReferenceDocument,
  SceneDocument,
  SceneInstanceDocument,
  SceneOverrideDocument,
  SceneResourceDocument,
} from '../../../content/scenes/types';
import { assertValidSceneDocument, assertValidSceneResourceDocument, validatePropertyDocumentValue } from '../../../content/scenes/validation';
import type { SceneDocumentLoader, SceneDocumentLease } from '../../../infrastructure/scenes/SceneDocumentLoader';
import type { SceneResourceLease, SceneResourceLoader } from '../../../infrastructure/scenes/SceneResourceLoader';
import { PackedScene, type PackedNodeDocument, type PackedSignalConnection } from '../PackedScene';

interface ScopedOverride {
  readonly value: SceneOverrideDocument;
  readonly origin: SceneOverrideDocument;
  readonly scopePath: readonly InstanceId[];
}

interface InstancePlacement {
  readonly instance: SceneInstanceDocument;
  readonly containingPath: readonly InstanceId[];
}

export interface SceneResolverOptions {
  readonly documents: SceneDocumentLoader;
  readonly resources?: SceneResourceLoader;
  readonly registry: DescriptorRegistry;
}

function packedKey(instancePath: readonly InstanceId[], nodeId: string): string {
  return [...instancePath, nodeId].join('/');
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function referenceKey(scopePath: readonly InstanceId[], reference: NodeReferenceDocument): string {
  return packedKey([...scopePath, ...(reference.instancePath ?? [])], reference.nodeId);
}

function resourceDescriptor(descriptor: PropertyDescriptor | undefined): descriptor is PropertyDescriptor & { readonly value: { readonly kind: 'resource-reference' } } {
  return descriptor?.value.kind === 'resource-reference';
}

export class SceneResolver {
  constructor(private readonly options: SceneResolverOptions) {}

  async prepare_scene(sceneId: SceneId, signal?: AbortSignal): Promise<PackedScene> {
    const documentLeases: SceneDocumentLease[] = [];
    const resourceLeases: SceneResourceLease[] = [];
    try {
      const documents = new Map<SceneId, SceneDocument>();
      const loadGraph = async (currentId: SceneId, stack: readonly SceneId[]): Promise<void> => {
        if (signal?.aborted) throw this.abortError();
        if (stack.includes(currentId)) throw new Error(`Scene instance cycle detected through '${currentId}'`);
        if (documents.has(currentId)) return;
        const lease = await this.options.documents.acquire(currentId, signal);
        documentLeases.push(lease);
        if (lease.document.sceneId !== currentId) throw new Error(`Scene loader returned '${lease.document.sceneId}' for requested scene '${currentId}'`);
        assertValidSceneDocument(lease.document, { registry: this.options.registry });
        documents.set(currentId, lease.document);
        for (const instance of lease.document.instances) await loadGraph(instance.sceneId, [...stack, currentId]);
      };
      await loadGraph(sceneId, []);

      const nodes: PackedNodeDocument[] = [];
      const connections: PackedSignalConnection[] = [];
      const scopeDocuments = new Map<string, SceneDocument>();
      const appliedOverrides = new Set<SceneOverrideDocument>();
      const appliedOverrideTargets = new Map<SceneOverrideDocument, { readonly descriptor: PropertyDescriptor; readonly scopePath: readonly InstanceId[] }>();

      const expandScene = (
        document: SceneDocument,
        instancePath: readonly InstanceId[],
        hostParentKey: string | null,
        rootName: string | undefined,
        rootOrder: number,
        overrides: readonly ScopedOverride[],
        placement?: InstancePlacement,
      ): void => {
        scopeDocuments.set(instancePath.join('/'), document);
        for (const connection of document.connections ?? []) {
          connections.push({
            sourceKey: referenceKey(instancePath, connection.source),
            signal: connection.signal,
            targetKey: referenceKey(instancePath, connection.target),
            handler: connection.handler,
          });
        }

        const emitNode = (nodeId: string, parentKey: string | null, nameOverride?: string, orderOverride?: number): void => {
          const source = document.nodes.find((node) => node.id === nodeId);
          if (!source) throw new Error(`Scene '${document.sceneId}' contains an unresolved node '${nodeId}'`);
          const key = packedKey(instancePath, source.id);
          const declaredProperties = propertiesForNode(source.type, source.scriptId, this.options.registry) ?? [];
          const descriptors = descriptorMap(declaredProperties);
          const properties: Record<string, JsonValue> = {};
          const propertyScopes: Record<string, readonly InstanceId[]> = {};
          for (const descriptor of declaredProperties) {
            if (descriptor.defaultValue === undefined) continue;
            properties[descriptor.key] = structuredClone(descriptor.defaultValue);
            propertyScopes[descriptor.key] = [...instancePath];
          }
          for (const [property, value] of Object.entries(source.properties)) {
            properties[property] = structuredClone(value);
            propertyScopes[property] = [...instancePath];
          }
          for (const scoped of overrides) {
            if (scoped.value.sourceInstancePath.length === 0 && scoped.value.sourceNodeId === source.id) {
              const descriptor = descriptors.get(scoped.value.property);
              if (!descriptor || !descriptor.serialized) throw new Error(`Unknown exported property '${scoped.value.property}' on '${key}'`);
              if (!descriptor.overridable) throw new Error(`Property '${scoped.value.property}' on '${key}' is not overridable`);
              properties[scoped.value.property] = structuredClone(scoped.value.value);
              propertyScopes[scoped.value.property] = [...scoped.scopePath];
              appliedOverrides.add(scoped.origin);
              appliedOverrideTargets.set(scoped.origin, { descriptor, scopePath: [...scoped.scopePath] });
            }
          }
          nodes.push({
            key,
            sourceSceneId: document.sceneId,
            authoredNodeId: source.id,
            instancePath: [...instancePath],
            name: nameOverride ?? source.name,
            type: source.type,
            scriptId: source.scriptId,
            parentKey,
            order: orderOverride ?? source.order,
            properties,
            propertyScopes,
            provenance: placement && source.id === document.rootNodeId ? {
              sourceSceneId: document.sceneId,
              authoredInstanceId: placement.instance.instanceId,
              containingInstancePath: [...placement.containingPath],
              overrides: structuredClone(placement.instance.overrides),
            } : undefined,
          });

          const children = [
            ...document.nodes.filter((candidate) => candidate.parentId === source.id).map((candidate) => ({ kind: 'node' as const, order: candidate.order, value: candidate })),
            ...document.instances.filter((candidate) => candidate.parentNodeId === source.id).map((candidate) => ({ kind: 'instance' as const, order: candidate.order, value: candidate })),
          ].sort((left, right) => left.order - right.order);
          for (const child of children) {
            if (child.kind === 'node') emitNode(child.value.id, key);
            else {
              const nestedDocument = documents.get(child.value.sceneId);
              if (!nestedDocument) throw new Error(`Unknown instanced scene '${child.value.sceneId}'`);
              const forwarded = overrides
                .filter((scoped) => scoped.value.sourceInstancePath[0] === child.value.instanceId)
                .map((scoped) => ({ ...scoped, value: { ...scoped.value, sourceInstancePath: scoped.value.sourceInstancePath.slice(1) } }));
              const local = child.value.overrides.map((value) => ({ value, origin: value, scopePath: [...instancePath] }));
              expandScene(
                nestedDocument,
                [...instancePath, child.value.instanceId],
                key,
                child.value.name,
                child.value.order,
                [...local, ...forwarded],
                { instance: child.value, containingPath: instancePath },
              );
            }
          }
        };
        emitNode(document.rootNodeId, hostParentKey, rootName, rootOrder);
      };

      const rootDocument = documents.get(sceneId);
      if (!rootDocument) throw new Error(`Unknown scene '${sceneId}'`);
      expandScene(rootDocument, [], null, undefined, 0, []);
      for (const document of documents.values()) {
        for (const instance of document.instances) {
          for (const override of instance.overrides) if (!appliedOverrides.has(override)) throw new Error(`Stale override '${override.property}' in instance '${instance.instanceId}'`);
        }
      }

      const packedByKey = new Map(nodes.map((node) => [node.key, node]));
      for (const connection of connections) {
        if (!packedByKey.has(connection.sourceKey) || !packedByKey.has(connection.targetKey)) throw new Error(`Signal connection endpoint does not resolve in packed scene '${sceneId}'`);
      }

      const packedResources = new Map<ResourceId, SceneResourceDocument>();
      const externalResourceIds = new Set<ResourceId>();
      for (const node of nodes) {
        const descriptors = descriptorMap(propertiesForNode(node.type, node.scriptId, this.options.registry) ?? []);
        for (const [property, value] of Object.entries(node.properties)) {
          const descriptor = descriptors.get(property);
          if (!resourceDescriptor(descriptor) || !isRecord(value) || typeof value.resourceId !== 'string') continue;
          const scopePath = node.propertyScopes[property] ?? node.instancePath;
          const scopeDocument = scopeDocuments.get(scopePath.join('/'));
          const inline = scopeDocument?.subresources?.find((resource) => resource.resourceId === value.resourceId);
          if (inline) packedResources.set(inline.resourceId, structuredClone(inline));
          else externalResourceIds.add(value.resourceId as ResourceId);
        }
      }
      const acquireResource = async (resourceId: ResourceId): Promise<void> => {
        if (packedResources.has(resourceId)) return;
        if (!this.options.resources) throw new Error(`Scene '${sceneId}' requires resource '${resourceId}' but no resource loader is configured`);
        const lease = await this.options.resources.acquire(resourceId, signal);
        resourceLeases.push(lease);
        if (lease.resource.resourceId !== resourceId) throw new Error(`Resource loader returned '${lease.resource.resourceId}' for requested resource '${resourceId}'`);
        assertValidSceneResourceDocument(lease.resource);
        packedResources.set(resourceId, lease.resource);
        if (lease.resource.kind === 'tile-data') await acquireResource(lease.resource.tileSet);
      };
      for (const resourceId of [...externalResourceIds].sort()) await acquireResource(resourceId);
      if (signal?.aborted) throw this.abortError();

      const resourceContext = {
        hasResource: (resourceId: string): boolean => packedResources.has(resourceId as ResourceId),
        getResourceKind: (resourceId: string): string | undefined => packedResources.get(resourceId as ResourceId)?.kind,
      };
      for (const resource of packedResources.values()) assertValidSceneResourceDocument(resource, resourceContext);
      for (const [override, target] of appliedOverrideTargets) {
        const path = `override:${override.sourceInstancePath.join('/')}/${override.sourceNodeId}.${override.property}`;
        const issues = validatePropertyDocumentValue(override.value, target.descriptor, path, { registry: this.options.registry, ...resourceContext });
        if (issues.length > 0) throw new Error(issues.map((issue) => `${issue.path}: ${issue.message}`).join('\n'));
        if (target.descriptor.value.kind === 'node-reference' && isRecord(override.value) && typeof override.value.nodeId === 'string') {
          const referenced = packedByKey.get(referenceKey(target.scopePath, override.value as unknown as NodeReferenceDocument));
          if (!referenced) throw new Error(`${path}: node reference does not resolve`);
          const capability = target.descriptor.value.capability;
          if (capability && !capabilitiesForNode(referenced.type, referenced.scriptId, this.options.registry).has(capability)) {
            throw new Error(`${path}: node reference requires capability '${capability}'`);
          }
        }
      }
      for (const node of nodes) {
        const descriptors = descriptorMap(propertiesForNode(node.type, node.scriptId, this.options.registry) ?? []);
        for (const [property, value] of Object.entries(node.properties)) {
          const descriptor = descriptors.get(property);
          if (!descriptor) continue;
          const issues = validatePropertyDocumentValue(value, descriptor, `${node.key}.${property}`, { registry: this.options.registry, ...resourceContext });
          if (issues.length > 0) throw new Error(issues.map((issue) => `${issue.path}: ${issue.message}`).join('\n'));
          if (descriptor.value.kind === 'node-reference' && isRecord(value) && typeof value.nodeId === 'string') {
            const target = packedByKey.get(referenceKey(node.propertyScopes[property] ?? node.instancePath, value as unknown as NodeReferenceDocument));
            if (!target) throw new Error(`Node reference '${node.key}.${property}' does not resolve`);
            const capability = descriptor.value.capability;
            if (capability && !capabilitiesForNode(target.type, target.scriptId, this.options.registry).has(capability)) {
              throw new Error(`Node reference '${node.key}.${property}' requires capability '${capability}'`);
            }
          }
        }
        if (node.parentKey) {
          const parent = packedByKey.get(node.parentKey);
          if (!parent) throw new Error(`Parent '${node.parentKey}' does not resolve for '${node.key}'`);
          const type = this.options.registry.nodeTypes.get(node.type);
          const parentType = this.options.registry.nodeTypes.get(parent.type);
          if (type?.allowedParentTypes && !type.allowedParentTypes.some((allowed) => nodeTypeIs(parent.type, allowed, this.options.registry))) {
            throw new Error(`${node.type} cannot be parented to ${parent.type} at '${node.key}'`);
          }
          if (parentType?.allowedChildTypes && !parentType.allowedChildTypes.some((allowed) => nodeTypeIs(node.type, allowed, this.options.registry))) {
            throw new Error(`${parent.type} cannot contain ${node.type} at '${node.key}'`);
          }
        }
      }
      for (const connection of connections) {
        const source = packedByKey.get(connection.sourceKey);
        const target = packedByKey.get(connection.targetKey);
        if (!source || !target) throw new Error(`Signal connection endpoint does not resolve in packed scene '${sceneId}'`);
        const signalDescriptor = signalsForNode(source.type, source.scriptId, this.options.registry).get(connection.signal);
        const handlerDescriptor = handlersForScript(target.scriptId, this.options.registry).get(connection.handler);
        if (!signalDescriptor || !handlerDescriptor) throw new Error(`Signal connection '${connection.signal}' to '${connection.handler}' is not registered`);
        if ((signalDescriptor.payload ?? 'void') !== (handlerDescriptor.payload ?? 'void')) throw new Error(`Signal connection payload mismatch for '${connection.signal}'`);
      }

      return new PackedScene({
        sourceSceneId: sceneId,
        rootKey: packedKey([], rootDocument.rootNodeId),
        nodes,
        connections,
        resources: [...packedResources.values()],
      }, [...documentLeases.map((lease) => lease.release), ...resourceLeases.map((lease) => lease.release)]);
    } catch (error) {
      for (const lease of [...resourceLeases].reverse()) lease.release();
      for (const lease of [...documentLeases].reverse()) lease.release();
      throw error;
    }
  }

  prepareScene(sceneId: SceneId, signal?: AbortSignal): Promise<PackedScene> { return this.prepare_scene(sceneId, signal); }

  private abortError(): Error { const error = new Error('Scene preparation was aborted'); error.name = 'AbortError'; return error; }
}
