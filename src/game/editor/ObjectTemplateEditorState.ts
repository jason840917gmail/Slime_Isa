import {
  getObjectVisualChoice,
  setObjectVisualOverride,
  type ColliderBounds,
  type EditableObjectVisual,
  type ObjectArchetypeId,
  type ObjectVisualChoice,
} from '../content/objects/ObjectCatalog';
import { getAsset } from '../infrastructure/assets/manifest';

export interface SourceFrameDimensions {
  readonly width: number;
  readonly height: number;
}

export interface ObjectTemplateDraft extends EditableObjectVisual {}

export interface ObjectTemplateViewState {
  readonly selected?: ObjectVisualChoice;
  readonly draft?: ObjectTemplateDraft;
  readonly frameDimensions?: SourceFrameDimensions;
  readonly errors: Readonly<Record<string, string>>;
  readonly dirty: boolean;
  readonly saving: boolean;
  readonly status: string;
  readonly revision: number;
}

type Listener = (state: ObjectTemplateViewState) => void;

function cloneCollider(collider?: ColliderBounds): ColliderBounds | undefined {
  return collider ? { ...collider } : undefined;
}

function cloneDraft(draft: ObjectTemplateDraft): ObjectTemplateDraft {
  return {
    displayName: draft.displayName,
    visualOffset: { ...draft.visualOffset },
    collider: cloneCollider(draft.collider),
  };
}

function serializeDraft(draft: ObjectTemplateDraft): string {
  return JSON.stringify(draft);
}

function draftFromChoice(choice: ObjectVisualChoice): ObjectTemplateDraft {
  return {
    displayName: choice.displayName,
    visualOffset: { ...choice.visualOffset },
    collider: cloneCollider(choice.collider),
  };
}

function isInteger(value: number): boolean {
  return Number.isFinite(value) && Number.isInteger(value);
}

export function getSourceFrameDimensions(choice: ObjectVisualChoice): SourceFrameDimensions | undefined {
  const asset = getAsset(choice.assetId);
  if (asset.source.kind !== 'spritesheet' || !('frame' in asset.source)) return undefined;
  return {
    width: asset.source.frame.w,
    height: asset.source.frame.h,
  };
}

export function validateObjectTemplateDraft(
  choice: ObjectVisualChoice,
  draft: ObjectTemplateDraft,
): Readonly<Record<string, string>> {
  const errors: Record<string, string> = {};
  const dimensions = getSourceFrameDimensions(choice);
  if (draft.displayName.trim().length === 0) errors.displayName = 'Template name is required.';

  if (!isInteger(draft.visualOffset.x)) errors.visualOffsetX = 'Use a whole number of pixels.';
  if (!isInteger(draft.visualOffset.y)) errors.visualOffsetY = 'Use a whole number of pixels.';

  if (choice.physics === null) {
    if (draft.collider) errors.collider = 'Decorative templates cannot have a collider.';
    return errors;
  }

  if (!draft.collider) {
    errors.collider = 'Solid templates require a collider.';
    return errors;
  }
  const { width, height, offsetX, offsetY } = draft.collider;
  if (!isInteger(width) || width < 1) errors.width = 'Width must be a positive whole number.';
  if (!isInteger(height) || height < 1) errors.height = 'Height must be a positive whole number.';
  if (!isInteger(offsetX) || offsetX < 0) errors.offsetX = 'Offset must be a whole number of 0 or more.';
  if (!isInteger(offsetY) || offsetY < 0) errors.offsetY = 'Offset must be a whole number of 0 or more.';
  if (dimensions && isInteger(width) && isInteger(offsetX) && offsetX + width > dimensions.width) {
    errors.width = `Collider must fit inside the ${dimensions.width}px frame.`;
  }
  if (dimensions && isInteger(height) && isInteger(offsetY) && offsetY + height > dimensions.height) {
    errors.height = `Collider must fit inside the ${dimensions.height}px frame.`;
  }
  return errors;
}

export class ObjectTemplateEditorState {
  private selectedValue?: ObjectVisualChoice;
  private draftValue?: ObjectTemplateDraft;
  private savedDraft?: ObjectTemplateDraft;
  private errorsValue: Readonly<Record<string, string>> = {};
  private dirtyValue = false;
  private savingValue = false;
  private statusValue = 'Select an object template to inspect';
  private revisionValue = 0;
  private listeners = new Set<Listener>();

  constructor(initialObjectId?: ObjectArchetypeId, initialVisualId?: string) {
    if (initialObjectId && initialVisualId) this.select(initialObjectId, initialVisualId, true);
  }

  get value(): ObjectTemplateViewState {
    return {
      selected: this.selectedValue,
      draft: this.draftValue ? cloneDraft(this.draftValue) : undefined,
      frameDimensions: this.selectedValue ? getSourceFrameDimensions(this.selectedValue) : undefined,
      errors: this.errorsValue,
      dirty: this.dirtyValue,
      saving: this.savingValue,
      status: this.statusValue,
      revision: this.revisionValue,
    };
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    listener(this.value);
    return () => this.listeners.delete(listener);
  }

  select(objectId: ObjectArchetypeId, visualId: string, force = false): boolean {
    if (!force && this.dirtyValue) return false;
    const choice = getObjectVisualChoice(objectId, visualId);
    if (!choice) {
      this.statusValue = `Unknown object template ${objectId} / ${visualId}`;
      this.emit();
      return false;
    }
    if (this.selectedValue?.objectId === objectId && this.selectedValue.visualId === visualId) return true;
    this.selectedValue = choice;
    this.savedDraft = draftFromChoice(choice);
    this.draftValue = cloneDraft(this.savedDraft);
    this.errorsValue = {};
    this.dirtyValue = false;
    this.statusValue = `Inspecting ${choice.displayName}`;
    this.revisionValue += 1;
    this.emit();
    return true;
  }

  discardAndSelect(objectId: ObjectArchetypeId, visualId: string): boolean {
    this.discardChanges();
    return this.select(objectId, visualId, true);
  }

  updateDraft(patch: Partial<ObjectTemplateDraft>): boolean {
    if (!this.selectedValue || !this.draftValue) return false;
    const next: ObjectTemplateDraft = {
      displayName: patch.displayName ?? this.draftValue.displayName,
      visualOffset: patch.visualOffset
        ? { ...this.draftValue.visualOffset, ...patch.visualOffset }
        : { ...this.draftValue.visualOffset },
      collider: patch.collider === undefined
        ? cloneCollider(this.draftValue.collider)
        : cloneCollider(patch.collider),
    };
    const errors = validateObjectTemplateDraft(this.selectedValue, next);
    this.errorsValue = errors;
    this.draftValue = next;
    this.dirtyValue = serializeDraft(next) !== serializeDraft(this.savedDraft as ObjectTemplateDraft);
    if (Object.keys(errors).length > 0) {
      this.statusValue = 'Draft has validation errors';
      this.revisionValue += 1;
      this.emit();
      return false;
    }
    setObjectVisualOverride(this.selectedValue.objectId, this.selectedValue.visualId, next);
    this.statusValue = this.dirtyValue ? 'Unsaved template draft' : 'Template matches saved definition';
    this.revisionValue += 1;
    this.emit();
    return true;
  }

  resetChanges(): void {
    if (!this.selectedValue || !this.savedDraft) return;
    this.draftValue = cloneDraft(this.savedDraft);
    setObjectVisualOverride(this.selectedValue.objectId, this.selectedValue.visualId, this.savedDraft);
    this.errorsValue = {};
    this.dirtyValue = false;
    this.statusValue = 'Template changes reset';
    this.revisionValue += 1;
    this.emit();
  }

  discardChanges(): void {
    if (!this.selectedValue || !this.savedDraft) return;
    this.draftValue = cloneDraft(this.savedDraft);
    setObjectVisualOverride(this.selectedValue.objectId, this.selectedValue.visualId, this.savedDraft);
    this.errorsValue = {};
    this.dirtyValue = false;
    this.statusValue = 'Template draft discarded';
    this.revisionValue += 1;
    this.emit();
  }

  async save(): Promise<void> {
    const selected = this.selectedValue;
    const draft = this.draftValue;
    if (!selected || !draft || this.savingValue || !this.dirtyValue) return;
    const errors = validateObjectTemplateDraft(selected, draft);
    this.errorsValue = errors;
    if (Object.keys(errors).length > 0) {
      this.statusValue = 'Fix template errors before saving';
      this.revisionValue += 1;
      this.emit();
      return;
    }

    this.savingValue = true;
    this.statusValue = 'Saving shared template...';
    this.emit();
    try {
      const response = await fetch('/__map-editor/object-template/update', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          objectId: selected.objectId,
          visualId: selected.visualId,
          displayName: draft.displayName,
          visualOffset: draft.visualOffset,
          collider: draft.collider,
        }),
      });
      const result = await response.json() as { ok?: boolean; error?: string };
      if (!response.ok || !result.ok) throw new Error(result.error ?? `Template save failed (${response.status})`);
      this.savedDraft = cloneDraft(draft);
      this.dirtyValue = false;
      setObjectVisualOverride(selected.objectId, selected.visualId, draft);
      this.statusValue = `Saved ${draft.displayName}`;
      this.errorsValue = {};
    } catch (error) {
      this.statusValue = error instanceof Error ? error.message : String(error);
    } finally {
      this.savingValue = false;
      this.revisionValue += 1;
      this.emit();
    }
  }

  private emit(): void {
    const state = this.value;
    for (const listener of this.listeners) listener(state);
  }
}
