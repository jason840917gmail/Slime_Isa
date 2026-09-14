import type { AuthoredNodeId } from '../../content/scenes/identifiers';
import type { NodeReferenceDocument, SceneDocument, SceneNodeDocument, SignalConnectionDocument } from '../../content/scenes/types';
import { sceneMutationCommand, type SceneCommand } from './SceneCommand';

interface SceneClipboardPayload {
  readonly rootId: AuthoredNodeId;
  readonly nodes: readonly SceneNodeDocument[];
  readonly connections: readonly SignalConnectionDocument[];
}

function remapReferences(value: unknown, ids: ReadonlyMap<AuthoredNodeId, AuthoredNodeId>): unknown {
  if (Array.isArray(value)) return value.map((entry) => remapReferences(entry, ids));
  if (!value || typeof value !== 'object') return value;
  const record = value as Record<string, unknown>;
  const remapped = Object.fromEntries(Object.entries(record).map(([key, entry]) => [key, remapReferences(entry, ids)]));
  if (typeof record.nodeId === 'string' && ids.has(record.nodeId as AuthoredNodeId)) remapped.nodeId = ids.get(record.nodeId as AuthoredNodeId);
  return remapped;
}

export class SceneClipboard {
  private payload?: SceneClipboardPayload;

  get hasContent(): boolean { return this.payload !== undefined; }

  copy(document: SceneDocument, rootId: AuthoredNodeId): void {
    if (!document.nodes.some((node) => node.id === rootId)) throw new Error(`Node '${rootId}' does not exist`);
    const ids = new Set<AuthoredNodeId>([rootId]);
    let changed = true;
    while (changed) {
      changed = false;
      for (const node of document.nodes) if (node.parentId && ids.has(node.parentId) && !ids.has(node.id)) { ids.add(node.id); changed = true; }
    }
    this.payload = {
      rootId,
      nodes: structuredClone(document.nodes.filter((node) => ids.has(node.id))),
      connections: structuredClone((document.connections ?? []).filter((connection) => ids.has(connection.source.nodeId) && ids.has(connection.target.nodeId))),
    };
  }

  clear(): void { this.payload = undefined; }

  paste(parentId: AuthoredNodeId, idFor: (source: AuthoredNodeId) => AuthoredNodeId): SceneCommand {
    if (!this.payload) throw new Error('Scene clipboard is empty');
    const payload = structuredClone(this.payload);
    return sceneMutationCommand(`Paste ${payload.rootId}`, (draft) => {
      if (!draft.nodes.some((node) => node.id === parentId)) throw new Error(`Parent '${parentId}' does not exist`);
      const ids = new Map(payload.nodes.map((node) => [node.id, idFor(node.id)]));
      const existing = new Set(draft.nodes.map((node) => node.id));
      for (const id of ids.values()) if (existing.has(id)) throw new Error(`Pasted node ID '${id}' already exists`);
      const nextOrder = Math.max(-1, ...draft.nodes.filter((node) => node.parentId === parentId).map((node) => node.order), ...draft.instances.filter((instance) => instance.parentNodeId === parentId).map((instance) => instance.order)) + 1;
      const nodes = payload.nodes.map((node) => ({
        ...node,
        id: ids.get(node.id)!,
        parentId: node.id === payload.rootId ? parentId : node.parentId ? ids.get(node.parentId) ?? node.parentId : parentId,
        order: node.id === payload.rootId ? nextOrder : node.order,
        properties: remapReferences(node.properties, ids) as SceneNodeDocument['properties'],
      }));
      const remapEndpoint = (reference: NodeReferenceDocument): NodeReferenceDocument => ({ ...reference, nodeId: ids.get(reference.nodeId) ?? reference.nodeId });
      const connections = payload.connections.map((connection) => ({ ...connection, source: remapEndpoint(connection.source), target: remapEndpoint(connection.target) }));
      draft.nodes.push(...nodes);
      draft.connections = [...(draft.connections ?? []), ...connections];
      return { kind: 'node', nodeId: ids.get(payload.rootId)! };
    });
  }
}
