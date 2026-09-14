import type { DescriptorRegistry } from '../../content/scenes/propertyDescriptors';
import type { SceneDocument } from '../../content/scenes/types';
import { validateSceneDocument, type SceneValidationContext, type SceneValidationIssue } from '../../content/scenes/validation';

export class SceneValidationState {
  private currentIssues: readonly SceneValidationIssue[] = [];

  constructor(private readonly context: SceneValidationContext) {}

  get issues(): readonly SceneValidationIssue[] { return structuredClone(this.currentIssues); }
  get repairMode(): boolean { return this.currentIssues.length > 0; }
  get registry(): DescriptorRegistry { return this.context.registry; }

  update(document: SceneDocument): readonly SceneValidationIssue[] {
    this.currentIssues = validateSceneDocument(document, this.context);
    return this.issues;
  }
}
