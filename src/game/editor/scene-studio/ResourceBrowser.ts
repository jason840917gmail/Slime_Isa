import type { ResourceId } from '../../content/scenes/identifiers';
import type { JsonValue, SceneDocument, SceneResourceDocument } from '../../content/scenes/types';
import { sceneMutationCommand, type SceneCommand } from './SceneCommand';

export interface ResourceConsumer {
  readonly resourceId: ResourceId;
  readonly owner: 'node' | 'override' | 'resource';
  readonly ownerId: string;
  readonly property: string;
}

function referencedResource(value: JsonValue): ResourceId | undefined {
  if (value === null || Array.isArray(value) || typeof value !== 'object') return undefined;
  const record = value as Readonly<Record<string, JsonValue>>;
  return typeof record.resourceId === 'string' ? record.resourceId as ResourceId : undefined;
}

export function resourceConsumers(document: SceneDocument, resourceId: ResourceId): readonly ResourceConsumer[] {
  const consumers: ResourceConsumer[] = [];
  for (const node of document.nodes) {
    for (const [property, value] of Object.entries(node.properties)) if (referencedResource(value) === resourceId) consumers.push({ resourceId, owner: 'node', ownerId: node.id, property });
  }
  for (const instance of document.instances) {
    for (const override of instance.overrides) if (referencedResource(override.value) === resourceId) consumers.push({ resourceId, owner: 'override', ownerId: instance.instanceId, property: override.property });
  }
  for (const resource of document.subresources ?? []) {
    const scan = (value: unknown, property: string): void => {
      if (Array.isArray(value)) value.forEach((nested, index) => scan(nested, `${property}/${index}`));
      else if (value !== null && typeof value === 'object') {
        if ((value as { resourceId?: unknown }).resourceId === resourceId) consumers.push({ resourceId, owner: 'resource', ownerId: resource.resourceId, property });
        for (const [key, nested] of Object.entries(value)) scan(nested, `${property}/${key}`);
      }
    };
    scan(resource, '');
  }
  return consumers;
}

export function makeResourceUniqueForNode(
  ownerNodeId: string,
  property: string,
  source: SceneResourceDocument,
  uniqueId: ResourceId,
): SceneCommand {
  return sceneMutationCommand(`Make ${source.resourceId} unique`, (draft) => {
    if ((draft.subresources ?? []).some((candidate) => candidate.resourceId === uniqueId)) throw new Error(`Resource '${uniqueId}' already exists`);
    const owner = draft.nodes.find((node) => node.id === ownerNodeId);
    if (!owner) throw new Error(`Node '${ownerNodeId}' does not exist`);
    const copy = { ...structuredClone(source), resourceId: uniqueId } as SceneResourceDocument;
    draft.subresources = [...(draft.subresources ?? []), copy];
    draft.nodes = draft.nodes.map((node) => node.id === ownerNodeId ? { ...node, properties: { ...node.properties, [property]: { resourceId: uniqueId } } } : node);
    return { kind: 'resource', resourceId: uniqueId };
  });
}
