import type { JsonValue, SceneResourceDocument } from '../../content/scenes/types';

export function editResourceField(resource: SceneResourceDocument, field: string, value: JsonValue): SceneResourceDocument {
  if (['version', 'resourceId', 'kind'].includes(field)) throw new Error(`Resource identity field '${field}' cannot be edited in place`);
  if (!Object.hasOwn(resource, field)) throw new Error(`Resource '${resource.resourceId}' has no field '${field}'`);
  return { ...structuredClone(resource), [field]: structuredClone(value) } as SceneResourceDocument;
}

export function resourceSummary(resource: SceneResourceDocument): string {
  if ('assetId' in resource) return `${resource.kind} · ${resource.assetId}`;
  if (resource.kind === 'collision-shape') return `${resource.kind} · ${resource.value.shape}`;
  return `${resource.kind} · ${resource.resourceId}`;
}
