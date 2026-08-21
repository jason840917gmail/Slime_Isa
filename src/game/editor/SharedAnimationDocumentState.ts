import type { AnimationPackageDocument } from '../content/animations/types';
import { validateAnimationPackage } from '../content/animations/validation';
import {
  LayeredAnimationDocumentState,
  type LayeredAnimationDocumentStateValue,
} from './LayeredAnimationDocumentState';

export interface SharedAnimationPackageStateValue {
  readonly animationId: string;
  readonly displayName: string;
  readonly description: string;
  readonly animation: LayeredAnimationDocumentStateValue;
  readonly dirty: boolean;
}

interface SharedAnimationHistoryEntry {
  readonly animationId: string;
  readonly displayName: string;
  readonly description: string;
  readonly animation: LayeredAnimationDocumentStateValue;
}

function clone<T>(value: T): T {
  return structuredClone(value);
}

/** Editor boundary for a shared package; it never creates a fake weapon wrapper. */
export class SharedAnimationDocumentState {
  private readonly original: AnimationPackageDocument;
  private animationId: string;
  private displayName: string;
  private description: string;
  private readonly document: LayeredAnimationDocumentState;
  private readonly undoStack: SharedAnimationHistoryEntry[] = [];
  private readonly redoStack: SharedAnimationHistoryEntry[] = [];

  constructor(packageValue: AnimationPackageDocument) {
    this.original = clone(packageValue);
    this.animationId = packageValue.animationId;
    this.displayName = packageValue.displayName;
    this.description = packageValue.description;
    this.document = new LayeredAnimationDocumentState(packageValue.animation);
  }

  get value(): SharedAnimationPackageStateValue {
    return {
      animationId: this.animationId,
      displayName: this.displayName,
      description: this.description,
      animation: this.document.value,
      dirty: this.isDirty(),
    };
  }

  get canUndo(): boolean {
    return this.undoStack.length > 0;
  }

  get canRedo(): boolean {
    return this.redoStack.length > 0;
  }

  updateMetadata(patch: Partial<Pick<SharedAnimationPackageStateValue, 'displayName' | 'description'>>): void {
    const before = this.capture();
    if (patch.displayName !== undefined) this.displayName = patch.displayName;
    if (patch.description !== undefined) this.description = patch.description;
    this.record(before);
  }

  setAnimationIdForNewPackage(animationId: string): boolean {
    if (this.original.animationId !== '') return false;
    if (!animationId.trim()) return false;
    const before = this.capture();
    this.animationId = animationId;
    this.record(before);
    return true;
  }

  mutateAnimation(operation: (document: LayeredAnimationDocumentState) => boolean): boolean {
    const before = this.capture();
    const accepted = operation(this.document);
    if (accepted) this.record(before);
    return accepted;
  }

  undo(): boolean {
    const previous = this.undoStack.pop();
    if (!previous) return false;
    this.redoStack.push(this.capture());
    this.restore(previous);
    return true;
  }

  redo(): boolean {
    const next = this.redoStack.pop();
    if (!next) return false;
    this.undoStack.push(this.capture());
    this.restore(next);
    return true;
  }

  toDocument(): AnimationPackageDocument {
    const value = this.document.value.animation;
    return {
      $schema: this.original.$schema,
      version: 1,
      animationId: this.animationId,
      displayName: this.displayName,
      description: this.description,
      animation: clone(value),
    };
  }

  validate(): readonly string[] {
    return validateAnimationPackage(this.toDocument()).map((issue) => `${issue.field ?? 'package'}: ${issue.message}`);
  }

  reset(): void {
    this.animationId = this.original.animationId;
    this.displayName = this.original.displayName;
    this.description = this.original.description;
    this.document.replace(this.original.animation);
    this.undoStack.length = 0;
    this.redoStack.length = 0;
  }

  private capture(): SharedAnimationHistoryEntry {
    return {
      animationId: this.animationId,
      displayName: this.displayName,
      description: this.description,
      animation: this.document.value,
    };
  }

  private restore(snapshot: SharedAnimationHistoryEntry): void {
    this.animationId = snapshot.animationId;
    this.displayName = snapshot.displayName;
    this.description = snapshot.description;
    this.document.restore(snapshot.animation);
  }

  private record(before: SharedAnimationHistoryEntry): void {
    const after = this.capture();
    const beforeContent = { animationId: before.animationId, displayName: before.displayName, description: before.description, animation: before.animation.animation };
    const afterContent = { animationId: after.animationId, displayName: after.displayName, description: after.description, animation: after.animation.animation };
    if (JSON.stringify(beforeContent) === JSON.stringify(afterContent)) return;
    this.undoStack.push(before);
    if (this.undoStack.length > 100) this.undoStack.shift();
    this.redoStack.length = 0;
  }

  private isDirty(): boolean {
    return JSON.stringify(this.toDocument()) !== JSON.stringify({
      $schema: this.original.$schema,
      version: 1,
      animationId: this.original.animationId,
      displayName: this.original.displayName,
      description: this.original.description,
      animation: this.original.animation,
    });
  }
}
