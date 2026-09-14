import type { AuthoredNodeId, InstanceId, ResourceId } from '../../content/scenes/identifiers';
import type { JsonValue, SceneDocument, SceneInstanceDocument, SceneNodeDocument, SceneOverrideDocument, SceneResourceDocument, SignalConnectionDocument } from '../../content/scenes/types';
import type { SceneSelection } from './SceneSelectionState';

export interface SceneCommandResult {
  readonly document: SceneDocument;
  readonly selection?: SceneSelection;
}

export interface SceneCommand {
  readonly label: string;
  apply(document: SceneDocument): SceneCommandResult;
}

type SceneMutation = (draft: MutableSceneDocument) => SceneSelection | void;
type MutableSceneDocument = {
  -readonly [K in keyof SceneDocument]: SceneDocument[K] extends readonly (infer T)[] ? T[] : SceneDocument[K]
} & Record<string, unknown>;

export function sceneMutationCommand(label: string, mutation: SceneMutation): SceneCommand {
  return {
    label,
    apply(document) {
      const draft = structuredClone(document) as MutableSceneDocument;
      const selection = mutation(draft);
      return { document: draft, ...(selection ? { selection } : {}) };
    },
  };
}

function subtreeIds(document: SceneDocument, rootId: AuthoredNodeId): Set<AuthoredNodeId> {
  const ids = new Set<AuthoredNodeId>([rootId]);
  let changed = true;
  while (changed) {
    changed = false;
    for (const node of document.nodes) if (node.parentId && ids.has(node.parentId) && !ids.has(node.id)) { ids.add(node.id); changed = true; }
  }
  return ids;
}

function normalizeChildren(draft: MutableSceneDocument, parentId: AuthoredNodeId): void {
  const ordered = [
    ...draft.nodes.filter((node) => node.parentId === parentId).map((entry) => ({ kind: 'node' as const, entry })),
    ...draft.instances.filter((instance) => instance.parentNodeId === parentId).map((entry) => ({ kind: 'instance' as const, entry })),
  ].sort((left, right) => left.entry.order - right.entry.order || left.entry.name.localeCompare(right.entry.name));
  const order = new Map(ordered.map((child, index) => [`${child.kind}:${child.kind === 'node' ? child.entry.id : child.entry.instanceId}`, index]));
  draft.nodes = draft.nodes.map((node) => node.parentId === parentId ? { ...node, order: order.get(`node:${node.id}`) ?? node.order } : node);
  draft.instances = draft.instances.map((instance) => instance.parentNodeId === parentId ? { ...instance, order: order.get(`instance:${instance.instanceId}`) ?? instance.order } : instance);
}

function placeChild(
  draft: MutableSceneDocument,
  parentId: AuthoredNodeId,
  child: { readonly kind: 'node'; readonly id: AuthoredNodeId } | { readonly kind: 'instance'; readonly id: InstanceId },
  requestedOrder: number,
): void {
  const key = `${child.kind}:${child.id}`;
  const siblings = [
    ...draft.nodes.filter((node) => node.parentId === parentId).map((entry) => ({ key: `node:${entry.id}`, order: entry.order })),
    ...draft.instances.filter((instance) => instance.parentNodeId === parentId).map((entry) => ({ key: `instance:${entry.instanceId}`, order: entry.order })),
  ].filter((entry) => entry.key !== key).sort((left, right) => left.order - right.order || left.key.localeCompare(right.key));
  siblings.splice(Math.max(0, Math.min(requestedOrder, siblings.length)), 0, { key, order: requestedOrder });
  const orders = new Map(siblings.map((entry, index) => [entry.key, index]));
  draft.nodes = draft.nodes.map((node) => node.parentId === parentId ? { ...node, order: orders.get(`node:${node.id}`) ?? node.order } : node);
  draft.instances = draft.instances.map((instance) => instance.parentNodeId === parentId ? { ...instance, order: orders.get(`instance:${instance.instanceId}`) ?? instance.order } : instance);
}

export const sceneCommands = {
  addNode(node: SceneNodeDocument): SceneCommand {
    return sceneMutationCommand(`Add ${node.name}`, (draft) => {
      if (draft.nodes.some((candidate) => candidate.id === node.id)) throw new Error(`Node '${node.id}' already exists`);
      if (node.parentId !== null && !draft.nodes.some((candidate) => candidate.id === node.parentId)) throw new Error(`Parent '${node.parentId}' does not exist`);
      draft.nodes.push(structuredClone(node));
      if (node.parentId) placeChild(draft, node.parentId, { kind: 'node', id: node.id }, node.order);
      return { kind: 'node', nodeId: node.id };
    });
  },

  replaceRoot(node: SceneNodeDocument): SceneCommand {
    return sceneMutationCommand(`Replace root with ${node.name}`, (draft) => {
      if (node.parentId !== null) throw new Error('Replacement root must have parentId null');
      const removed = subtreeIds(draft, draft.rootNodeId);
      draft.nodes = draft.nodes.filter((candidate) => !removed.has(candidate.id));
      draft.instances = draft.instances.filter((instance) => !removed.has(instance.parentNodeId));
      draft.connections = (draft.connections ?? []).filter((connection) => !removed.has(connection.source.nodeId) && !removed.has(connection.target.nodeId));
      draft.nodes.push(structuredClone(node));
      draft.rootNodeId = node.id;
      return { kind: 'node', nodeId: node.id };
    });
  },

  renameNode(nodeId: AuthoredNodeId, name: string): SceneCommand {
    return sceneMutationCommand(`Rename ${nodeId}`, (draft) => {
      const trimmed = name.trim();
      if (!trimmed) throw new Error('Node name cannot be empty');
      let found = false;
      draft.nodes = draft.nodes.map((node) => node.id === nodeId ? (found = true, { ...node, name: trimmed }) : node);
      if (!found) throw new Error(`Node '${nodeId}' does not exist`);
      return { kind: 'node', nodeId };
    });
  },

  reparentNode(nodeId: AuthoredNodeId, parentId: AuthoredNodeId, order: number): SceneCommand {
    return sceneMutationCommand(`Reparent ${nodeId}`, (draft) => {
      const node = draft.nodes.find((candidate) => candidate.id === nodeId);
      if (!node || node.parentId === null) throw new Error('Root cannot be reparented');
      if (!draft.nodes.some((candidate) => candidate.id === parentId)) throw new Error(`Parent '${parentId}' does not exist`);
      if (subtreeIds(draft, nodeId).has(parentId)) throw new Error('Cannot reparent a node beneath its own subtree');
      const previousParent = node.parentId;
      draft.nodes = draft.nodes.map((candidate) => candidate.id === nodeId ? { ...candidate, parentId, order } : candidate);
      normalizeChildren(draft, previousParent);
      placeChild(draft, parentId, { kind: 'node', id: nodeId }, order);
      return { kind: 'node', nodeId };
    });
  },

  reorderNode(nodeId: AuthoredNodeId, order: number): SceneCommand {
    return sceneMutationCommand(`Reorder ${nodeId}`, (draft) => {
      const node = draft.nodes.find((candidate) => candidate.id === nodeId);
      if (!node?.parentId) throw new Error('Root cannot be reordered');
      placeChild(draft, node.parentId, { kind: 'node', id: nodeId }, order);
      return { kind: 'node', nodeId };
    });
  },

  setProperty(nodeId: AuthoredNodeId, property: string, value: JsonValue): SceneCommand {
    return sceneMutationCommand(`Set ${nodeId}.${property}`, (draft) => {
      let found = false;
      draft.nodes = draft.nodes.map((node) => node.id === nodeId ? (found = true, { ...node, properties: { ...node.properties, [property]: structuredClone(value) } }) : node);
      if (!found) throw new Error(`Node '${nodeId}' does not exist`);
      return { kind: 'node', nodeId };
    });
  },

  clearProperty(nodeId: AuthoredNodeId, property: string): SceneCommand {
    return sceneMutationCommand(`Reset ${nodeId}.${property}`, (draft) => {
      const node = draft.nodes.find((candidate) => candidate.id === nodeId);
      if (!node) throw new Error(`Node '${nodeId}' does not exist`);
      const properties = { ...node.properties };
      delete properties[property];
      draft.nodes = draft.nodes.map((candidate) => candidate.id === nodeId ? { ...candidate, properties } : candidate);
      return { kind: 'node', nodeId };
    });
  },

  addInstance(instance: SceneInstanceDocument): SceneCommand {
    return sceneMutationCommand(`Add ${instance.name}`, (draft) => {
      if (draft.instances.some((candidate) => candidate.instanceId === instance.instanceId)) throw new Error(`Instance '${instance.instanceId}' already exists`);
      if (!draft.nodes.some((candidate) => candidate.id === instance.parentNodeId)) throw new Error(`Parent '${instance.parentNodeId}' does not exist`);
      draft.instances.push(structuredClone(instance));
      placeChild(draft, instance.parentNodeId, { kind: 'instance', id: instance.instanceId }, instance.order);
      return { kind: 'instance', instanceId: instance.instanceId };
    });
  },

  renameInstance(instanceId: InstanceId, name: string): SceneCommand {
    return sceneMutationCommand(`Rename ${instanceId}`, (draft) => {
      const trimmed = name.trim();
      if (!trimmed) throw new Error('Instance name cannot be empty');
      let found = false;
      draft.instances = draft.instances.map((instance) => instance.instanceId === instanceId
        ? (found = true, { ...instance, name: trimmed })
        : instance);
      if (!found) throw new Error(`Instance '${instanceId}' does not exist`);
      return { kind: 'instance', instanceId };
    });
  },

  moveInstance(instanceId: InstanceId, parentNodeId: AuthoredNodeId, order: number): SceneCommand {
    return sceneMutationCommand(`Move ${instanceId}`, (draft) => {
      const instance = draft.instances.find((candidate) => candidate.instanceId === instanceId);
      if (!instance) throw new Error(`Instance '${instanceId}' does not exist`);
      if (!draft.nodes.some((candidate) => candidate.id === parentNodeId)) throw new Error(`Parent '${parentNodeId}' does not exist`);
      const previousParent = instance.parentNodeId;
      draft.instances = draft.instances.map((candidate) => candidate.instanceId === instanceId ? { ...candidate, parentNodeId, order } : candidate);
      normalizeChildren(draft, previousParent);
      placeChild(draft, parentNodeId, { kind: 'instance', id: instanceId }, order);
      return { kind: 'instance', instanceId };
    });
  },

  duplicateInstance(instanceId: InstanceId, duplicateId: InstanceId, name: string): SceneCommand {
    return sceneMutationCommand(`Duplicate ${instanceId}`, (draft) => {
      if (draft.instances.some((candidate) => candidate.instanceId === duplicateId)) throw new Error(`Instance '${duplicateId}' already exists`);
      const source = draft.instances.find((candidate) => candidate.instanceId === instanceId);
      if (!source) throw new Error(`Instance '${instanceId}' does not exist`);
      const duplicate = { ...structuredClone(source), instanceId: duplicateId, name: name.trim() || `${source.name} Copy`, order: source.order + 1 };
      draft.instances.push(duplicate);
      placeChild(draft, source.parentNodeId, { kind: 'instance', id: duplicateId }, duplicate.order);
      return { kind: 'instance', instanceId: duplicateId };
    });
  },

  removeInstance(instanceId: InstanceId): SceneCommand {
    return sceneMutationCommand(`Remove ${instanceId}`, (draft) => {
      const instance = draft.instances.find((candidate) => candidate.instanceId === instanceId);
      if (!instance) throw new Error(`Instance '${instanceId}' does not exist`);
      draft.instances = draft.instances.filter((candidate) => candidate.instanceId !== instanceId);
      normalizeChildren(draft, instance.parentNodeId);
      return { kind: 'node', nodeId: instance.parentNodeId };
    });
  },

  setOverride(instanceId: InstanceId, override: SceneOverrideDocument): SceneCommand {
    return sceneMutationCommand(`Override ${override.sourceNodeId}.${override.property}`, (draft) => {
      const instance = draft.instances.find((candidate) => candidate.instanceId === instanceId);
      if (!instance) throw new Error(`Instance '${instanceId}' does not exist`);
      const matches = (candidate: SceneOverrideDocument): boolean => candidate.sourceNodeId === override.sourceNodeId && candidate.property === override.property && candidate.sourceInstancePath.join('/') === override.sourceInstancePath.join('/');
      const overrides = [...instance.overrides.filter((candidate) => !matches(candidate)), structuredClone(override)];
      draft.instances = draft.instances.map((candidate) => candidate.instanceId === instanceId ? { ...candidate, overrides } : candidate);
      return { kind: 'instance', instanceId };
    });
  },

  revertOverride(instanceId: InstanceId, sourceInstancePath: readonly InstanceId[], sourceNodeId: AuthoredNodeId, property: string): SceneCommand {
    return sceneMutationCommand(`Revert ${sourceNodeId}.${property}`, (draft) => {
      const instance = draft.instances.find((candidate) => candidate.instanceId === instanceId);
      if (!instance) throw new Error(`Instance '${instanceId}' does not exist`);
      const overrides = instance.overrides.filter((candidate) => !(candidate.sourceNodeId === sourceNodeId && candidate.property === property && candidate.sourceInstancePath.join('/') === sourceInstancePath.join('/')));
      draft.instances = draft.instances.map((candidate) => candidate.instanceId === instanceId ? { ...candidate, overrides } : candidate);
      return { kind: 'instance', instanceId };
    });
  },

  upsertResource(resource: SceneResourceDocument): SceneCommand {
    return sceneMutationCommand(`Update ${resource.resourceId}`, (draft) => {
      draft.subresources = [...(draft.subresources ?? []).filter((candidate) => candidate.resourceId !== resource.resourceId), structuredClone(resource)];
      return { kind: 'resource', resourceId: resource.resourceId };
    });
  },

  removeResource(resourceId: ResourceId): SceneCommand {
    return sceneMutationCommand(`Remove ${resourceId}`, (draft) => {
      if (!(draft.subresources ?? []).some((candidate) => candidate.resourceId === resourceId)) throw new Error(`Resource '${resourceId}' does not exist`);
      draft.subresources = (draft.subresources ?? []).filter((candidate) => candidate.resourceId !== resourceId);
      return { kind: 'scene' };
    });
  },

  connectSignal(connection: SignalConnectionDocument): SceneCommand {
    return sceneMutationCommand(`Connect ${connection.signal}`, (draft) => { draft.connections = [...(draft.connections ?? []), structuredClone(connection)]; });
  },

  disconnectSignal(index: number): SceneCommand {
    return sceneMutationCommand('Disconnect signal', (draft) => {
      if (!(draft.connections ?? [])[index]) throw new Error(`Signal connection ${index} does not exist`);
      draft.connections = (draft.connections ?? []).filter((_connection, candidate) => candidate !== index);
    });
  },

  deleteSubtree(nodeId: AuthoredNodeId, propertyRepairs: readonly { readonly ownerNodeId: AuthoredNodeId; readonly property: string; readonly value?: JsonValue }[] = []): SceneCommand {
    return sceneMutationCommand(`Delete ${nodeId}`, (draft) => {
      const node = draft.nodes.find((candidate) => candidate.id === nodeId);
      if (!node) throw new Error(`Node '${nodeId}' does not exist`);
      if (node.parentId === null) throw new Error('Root deletion requires an explicit root replacement');
      const removed = subtreeIds(draft, nodeId);
      for (const repair of propertyRepairs) {
        const owner = draft.nodes.find((candidate) => candidate.id === repair.ownerNodeId);
        if (!owner || removed.has(owner.id)) continue;
        const properties = { ...owner.properties };
        if (repair.value === undefined) delete properties[repair.property];
        else properties[repair.property] = structuredClone(repair.value);
        draft.nodes = draft.nodes.map((candidate) => candidate.id === owner.id ? { ...candidate, properties } : candidate);
      }
      draft.nodes = draft.nodes.filter((candidate) => !removed.has(candidate.id));
      draft.instances = draft.instances.filter((instance) => !removed.has(instance.parentNodeId));
      draft.connections = (draft.connections ?? []).filter((connection) => !removed.has(connection.source.nodeId) && !removed.has(connection.target.nodeId));
      normalizeChildren(draft, node.parentId);
      return { kind: 'node', nodeId: node.parentId };
    });
  },
};
