import type { AuthoredNodeId, InstanceId, ResourceId } from '../../content/scenes/identifiers';

export type SceneSelection =
  | { readonly kind: 'scene' }
  | { readonly kind: 'node'; readonly nodeId: AuthoredNodeId }
  | { readonly kind: 'instance'; readonly instanceId: InstanceId }
  | { readonly kind: 'resource'; readonly resourceId: ResourceId };

export class SceneSelectionState {
  private current: SceneSelection = { kind: 'scene' };

  get value(): SceneSelection { return structuredClone(this.current); }
  select(selection: SceneSelection): void { this.current = structuredClone(selection); }
  restore(selection: SceneSelection): void { this.select(selection); }
}
