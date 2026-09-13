import type { AuthoredNodeId, InstanceId, SceneId } from './identifiers';
import type { JsonValue, SceneResourceDocument } from './resources/types';

export interface NodeReferenceDocument {
  readonly instancePath?: readonly InstanceId[];
  readonly nodeId: AuthoredNodeId;
}

export interface SceneReferenceDocument {
  readonly sceneId: SceneId;
}

export interface SceneOverrideDocument {
  readonly sourceInstancePath: readonly InstanceId[];
  readonly sourceNodeId: AuthoredNodeId;
  readonly property: string;
  readonly value: JsonValue;
}

export interface SceneNodeDocument {
  readonly id: AuthoredNodeId;
  readonly name: string;
  readonly type: string;
  readonly scriptId?: string;
  readonly parentId: AuthoredNodeId | null;
  readonly order: number;
  readonly properties: Readonly<Record<string, JsonValue>>;
}

export interface SceneInstanceDocument {
  readonly instanceId: InstanceId;
  readonly name: string;
  readonly sceneId: SceneId;
  readonly parentNodeId: AuthoredNodeId;
  readonly order: number;
  readonly overrides: readonly SceneOverrideDocument[];
}

export interface SignalConnectionDocument {
  readonly source: NodeReferenceDocument;
  readonly signal: string;
  readonly target: NodeReferenceDocument;
  readonly handler: string;
}

export interface SceneDocument {
  readonly version: 1;
  readonly sceneId: SceneId;
  readonly rootNodeId: AuthoredNodeId;
  readonly nodes: readonly SceneNodeDocument[];
  readonly instances: readonly SceneInstanceDocument[];
  readonly connections?: readonly SignalConnectionDocument[];
  readonly subresources?: readonly SceneResourceDocument[];
}

export type { JsonValue, ResourceReferenceDocument, SceneResourceDocument } from './resources/types';
