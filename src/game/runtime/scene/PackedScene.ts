import type { AuthoredNodeId, InstanceId, SceneId } from '../../content/scenes/identifiers';
import type { JsonValue, SceneInstanceProvenance, SceneResourceDocument } from '../../content/scenes/types';
import type { Disposable } from '../../shared/lifecycle/Disposable';

export interface PackedNodeDocument {
  readonly key: string;
  readonly sourceSceneId: SceneId;
  readonly authoredNodeId: AuthoredNodeId;
  readonly instancePath: readonly InstanceId[];
  readonly name: string;
  readonly type: string;
  readonly scriptId?: string;
  readonly parentKey: string | null;
  readonly order: number;
  readonly properties: Readonly<Record<string, JsonValue>>;
  readonly propertyScopes: Readonly<Record<string, readonly InstanceId[]>>;
  readonly provenance?: SceneInstanceProvenance;
}

export interface PackedSignalConnection {
  readonly sourceKey: string;
  readonly signal: string;
  readonly targetKey: string;
  readonly handler: string;
}

export interface PackedSceneDefinition {
  readonly sourceSceneId: SceneId;
  readonly rootKey: string;
  readonly nodes: readonly PackedNodeDocument[];
  readonly connections: readonly PackedSignalConnection[];
  readonly resources: readonly SceneResourceDocument[];
}

function deepFreeze<T>(value: T): T {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const nested of Object.values(value as Record<string, unknown>)) deepFreeze(nested);
  }
  return value;
}

export class PackedScene implements Disposable {
  readonly definition: PackedSceneDefinition;
  private released = false;

  constructor(definition: PackedSceneDefinition, private readonly releaseActions: readonly (() => void)[] = []) {
    this.definition = deepFreeze(structuredClone(definition));
  }

  get sourceSceneId(): SceneId { return this.definition.sourceSceneId; }
  get isDisposed(): boolean { return this.released; }

  assertUsable(): void {
    if (this.released) throw new Error(`Packed scene '${this.sourceSceneId}' has been disposed`);
  }

  dispose(): void {
    if (this.released) return;
    this.released = true;
    const errors: unknown[] = [];
    for (const release of [...this.releaseActions].reverse()) {
      try { release(); } catch (error) { errors.push(error); }
    }
    if (errors.length > 0) throw new AggregateError(errors, `Failed to release packed scene '${this.sourceSceneId}'`);
  }
}
