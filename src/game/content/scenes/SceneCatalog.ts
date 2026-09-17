import {
  capabilitiesForNode,
  descriptorMap,
  handlersForScript,
  propertiesForNode,
  signalsForNode,
  type PropertyDescriptor,
} from './propertyDescriptors';
import {
  assertValidSceneDocument,
  validatePropertyDocumentValue,
  type SceneValidationContext,
  type SceneValidationIssue,
} from './validation';
import type { SceneId } from './identifiers';
import type { NodeReferenceDocument, SceneDocument, SceneNodeDocument } from './types';

interface ResolvedNode {
  readonly scene: SceneDocument;
  readonly node: SceneNodeDocument;
}

function immutableScene(document: SceneDocument): SceneDocument {
  const copy = structuredClone(document);
  const freeze = (value: unknown): void => {
    if (!value || typeof value !== 'object' || Object.isFrozen(value)) return;
    Object.freeze(value);
    for (const nested of Object.values(value)) freeze(nested);
  };
  freeze(copy);
  return copy;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export class SceneCatalog {
  private readonly byId = new Map<SceneId, SceneDocument>();

  constructor(documents: readonly SceneDocument[], private readonly validation: SceneValidationContext) {
    for (const document of documents) {
      if (this.byId.has(document.sceneId)) throw new Error(`Duplicate scene ID '${document.sceneId}'`);
      assertValidSceneDocument(document, validation);
      this.byId.set(document.sceneId, immutableScene(document));
    }
    const issues = [...this.instanceCycleIssues(), ...this.relationshipIssues()];
    if (issues.length > 0) throw new Error(issues.map((issue) => `${issue.path}: ${issue.message}`).join('\n'));
  }

  get(sceneId: SceneId): SceneDocument | undefined { return this.byId.get(sceneId); }
  has(sceneId: SceneId): boolean { return this.byId.has(sceneId); }
  all(): readonly SceneDocument[] { return [...this.byId.values()]; }

  private contextFor(scene: SceneDocument): SceneValidationContext {
    const localResources = new Map<string, NonNullable<SceneDocument['subresources']>[number]>((scene.subresources ?? []).map((resource) => [resource.resourceId, resource]));
    return {
      ...this.validation,
      hasResource: this.validation.hasResource
        ? (resourceId) => localResources.has(resourceId) || Boolean(this.validation.hasResource?.(resourceId))
        : undefined,
      getResourceKind: this.validation.getResourceKind || localResources.size > 0
        ? (resourceId) => localResources.get(resourceId)?.kind ?? this.validation.getResourceKind?.(resourceId)
        : undefined,
    };
  }

  private resolveNode(owner: SceneDocument, reference: NodeReferenceDocument, path: string, issues: SceneValidationIssue[]): ResolvedNode | undefined {
    let current = owner;
    for (const instanceId of reference.instancePath ?? []) {
      const instance = current.instances.find((candidate) => candidate.instanceId === instanceId);
      if (!instance) {
        issues.push({ path, message: `instance '${instanceId}' does not resolve in scene '${current.sceneId}'` });
        return undefined;
      }
      const next = this.byId.get(instance.sceneId);
      if (!next) {
        issues.push({ path, message: `instanced scene '${instance.sceneId}' does not resolve` });
        return undefined;
      }
      current = next;
    }
    const node = current.nodes.find((candidate) => candidate.id === reference.nodeId);
    if (!node) {
      issues.push({ path, message: `node '${reference.nodeId}' does not resolve in scene '${current.sceneId}'` });
      return undefined;
    }
    return { scene: current, node };
  }

  private validateReferenceValue(owner: SceneDocument, value: unknown, descriptor: PropertyDescriptor, path: string, issues: SceneValidationIssue[]): void {
    if (descriptor.value.kind === 'node-reference' && isRecord(value) && typeof value.nodeId === 'string') {
      const resolved = this.resolveNode(owner, value as unknown as NodeReferenceDocument, path, issues);
      const expected = descriptor.value.capability;
      if (resolved && expected && !capabilitiesForNode(resolved.node.type, resolved.node.scriptId, this.validation.registry).has(expected)) {
        issues.push({ path, message: `node '${resolved.node.id}' does not provide required capability '${expected}'` });
      }
    }
    if (descriptor.value.kind === 'scene-reference' && isRecord(value) && typeof value.sceneId === 'string' && !this.byId.has(value.sceneId as SceneId)) {
      issues.push({ path, message: `scene '${value.sceneId}' does not resolve` });
    }
  }

  private relationshipIssues(): readonly SceneValidationIssue[] {
    const issues: SceneValidationIssue[] = [];
    for (const scene of this.byId.values()) {
      for (const [nodeIndex, node] of scene.nodes.entries()) {
        const descriptors = propertiesForNode(node.type, node.scriptId, this.validation.registry);
        if (!descriptors) continue;
        const byKey = descriptorMap(descriptors);
        for (const [key, value] of Object.entries(node.properties)) {
          const descriptor = byKey.get(key);
          if (descriptor) this.validateReferenceValue(scene, value, descriptor, `${scene.sceneId}/nodes/${nodeIndex}/properties/${key}`, issues);
        }
      }

      for (const [instanceIndex, instance] of scene.instances.entries()) {
        const sourceScene = this.byId.get(instance.sceneId);
        if (!sourceScene) continue;
        for (const [overrideIndex, override] of instance.overrides.entries()) {
          const path = `${scene.sceneId}/instances/${instanceIndex}/overrides/${overrideIndex}`;
          const resolved = this.resolveNode(sourceScene, { instancePath: override.sourceInstancePath, nodeId: override.sourceNodeId }, path, issues);
          if (!resolved) continue;
          const descriptor = descriptorMap(propertiesForNode(resolved.node.type, resolved.node.scriptId, this.validation.registry) ?? []).get(override.property);
          if (!descriptor || !descriptor.serialized) {
            issues.push({ path: `${path}/property`, message: `unknown exported property '${override.property}'` });
            continue;
          }
          if (!descriptor.overridable) issues.push({ path: `${path}/property`, message: `property '${override.property}' is not overridable` });
          issues.push(...validatePropertyDocumentValue(override.value, descriptor, `${path}/value`, this.contextFor(scene)));
          this.validateReferenceValue(scene, override.value, descriptor, `${path}/value`, issues);
        }
      }

      for (const [connectionIndex, connection] of (scene.connections ?? []).entries()) {
        const path = `${scene.sceneId}/connections/${connectionIndex}`;
        const source = this.resolveNode(scene, connection.source, `${path}/source`, issues);
        const target = this.resolveNode(scene, connection.target, `${path}/target`, issues);
        if (!source || !target) continue;
        const signal = signalsForNode(source.node.type, source.node.scriptId, this.validation.registry).get(connection.signal);
        if (!signal) issues.push({ path: `${path}/signal`, message: `unknown signal '${connection.signal}' on node '${source.node.id}'` });
        const handler = handlersForScript(target.node.scriptId, this.validation.registry).get(connection.handler);
        if (!handler) issues.push({ path: `${path}/handler`, message: `unknown handler '${connection.handler}' on node '${target.node.id}'` });
        if (signal && handler && (signal.payload ?? 'void') !== (handler.payload ?? 'void')) {
          issues.push({ path, message: `signal payload '${signal.payload ?? 'void'}' is incompatible with handler payload '${handler.payload ?? 'void'}'` });
        }
      }
    }
    return issues;
  }

  private instanceCycleIssues(): readonly SceneValidationIssue[] {
    const issues: SceneValidationIssue[] = [];
    const visit = (sceneId: SceneId, stack: readonly SceneId[]): void => {
      const document = this.byId.get(sceneId);
      if (!document) return;
      for (const instance of document.instances) {
        if (!this.byId.has(instance.sceneId)) {
          issues.push({ path: `${sceneId}/${instance.instanceId}`, message: `unknown instanced scene '${instance.sceneId}'` });
          continue;
        }
        if (stack.includes(instance.sceneId) || instance.sceneId === sceneId) {
          issues.push({ path: `${sceneId}/${instance.instanceId}`, message: `scene instance cycle detected through '${instance.sceneId}'` });
          continue;
        }
        visit(instance.sceneId, [...stack, sceneId]);
      }
    };
    for (const sceneId of this.byId.keys()) visit(sceneId, []);
    return issues;
  }
}
