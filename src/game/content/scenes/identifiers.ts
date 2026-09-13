declare const identifierBrand: unique symbol;

type BrandedIdentifier<Name extends string> = string & { readonly [identifierBrand]: Name };

export type SceneId = BrandedIdentifier<'SceneId'>;
export type ResourceId = BrandedIdentifier<'ResourceId'>;
export type AuthoredNodeId = BrandedIdentifier<'AuthoredNodeId'>;
export type InstanceId = BrandedIdentifier<'InstanceId'>;
export type RuntimeNodeId = BrandedIdentifier<'RuntimeNodeId'>;
export type PersistenceKey = BrandedIdentifier<'PersistenceKey'>;

export const SERIALIZED_ID_PATTERN = /^[a-z0-9]+(?:[._-][a-z0-9]+)*$/;

function identifier<Name extends string>(value: string, label: Name): BrandedIdentifier<Name> {
  if (!SERIALIZED_ID_PATTERN.test(value)) {
    throw new Error(`${label} '${value}' must use lowercase letters, digits, and internal '.', '_' or '-' delimiters`);
  }
  return value as BrandedIdentifier<Name>;
}

export const sceneId = (value: string): SceneId => identifier(value, 'SceneId');
export const resourceId = (value: string): ResourceId => identifier(value, 'ResourceId');
export const authoredNodeId = (value: string): AuthoredNodeId => identifier(value, 'AuthoredNodeId');
export const instanceId = (value: string): InstanceId => identifier(value, 'InstanceId');
export const persistenceKey = (value: string): PersistenceKey => identifier(value, 'PersistenceKey');

export function encodeRuntimeSegment(value: string): string {
  if (!SERIALIZED_ID_PATTERN.test(value)) throw new Error(`Runtime ID segment '${value}' is not canonical`);
  return encodeURIComponent(value);
}

export function runtimeNodeId(
  runtimeNamespace: string,
  instancePath: readonly InstanceId[],
  nodeId: AuthoredNodeId,
): RuntimeNodeId {
  return [runtimeNamespace, ...instancePath, nodeId].map(encodeRuntimeSegment).join('/') as RuntimeNodeId;
}
