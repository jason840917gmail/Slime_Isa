import type { SceneValidationIssue } from '../../../content/scenes/validation';

export interface SceneDebugSnapshot {
  readonly validation: readonly SceneValidationIssue[];
  readonly lifecycleErrors: readonly string[];
  readonly unresolvedReferences: readonly string[];
  readonly activeResources: number;
}

export class SceneDebugContext {
  private lifecycleErrors: string[] = [];
  private unresolvedReferences: string[] = [];
  private activeResources = 0;
  reportLifecycle(error: unknown): void { this.lifecycleErrors.push(error instanceof Error ? error.message : String(error)); }
  reportUnresolved(reference: string): void { this.unresolvedReferences.push(reference); }
  setActiveResources(count: number): void { this.activeResources = Math.max(0, Math.trunc(count)); }
  snapshot(validation: readonly SceneValidationIssue[]): SceneDebugSnapshot { return { validation, lifecycleErrors: [...this.lifecycleErrors], unresolvedReferences: [...this.unresolvedReferences], activeResources: this.activeResources }; }
  clear(): void { this.lifecycleErrors = []; this.unresolvedReferences = []; this.activeResources = 0; }
}
