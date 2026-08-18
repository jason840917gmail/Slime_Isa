import {
  getObjectVisualChoice,
  setObjectVisualOverride,
  type ColliderBounds,
  type DepthBounds,
  type OcclusionBounds,
  type EditableObjectVisual,
  type ObjectArchetypeId,
  type ObjectVisualChoice,
} from '../content/objects/ObjectCatalog';
import { getAsset } from '../infrastructure/assets/manifest';
import type { EditorGeometryKey } from './EditorGeometryStyles';

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
  readonly showAllMatchingOverlays: boolean;
  readonly showFrameOverlay: boolean;
  readonly showColliderOverlay: boolean;
  readonly showOcclusionOverlay: boolean;
  readonly showDepthOverlay: boolean;
  readonly dirty: boolean;
  readonly saving: boolean;
  readonly status: string;
  readonly revision: number;
}

export interface DuplicatedObjectTemplate {
  readonly objectId: ObjectArchetypeId;
  readonly visualId: string;
}

type Listener = (state: ObjectTemplateViewState) => void;

function cloneCollider(collider?: ColliderBounds): ColliderBounds | undefined {
  return collider ? { ...collider } : undefined;
}

function cloneOcclusionBounds(bounds?: OcclusionBounds): OcclusionBounds | undefined {
  return bounds ? { ...bounds } : undefined;
}

function cloneDepthBounds(bounds?: DepthBounds): DepthBounds | undefined {
  return bounds ? { ...bounds } : undefined;
}

function cloneDraft(draft: ObjectTemplateDraft): ObjectTemplateDraft {
  return {
    displayName: draft.displayName,
    scale: draft.scale,
    visualOffset: { ...draft.visualOffset },
    collider: cloneCollider(draft.collider),
    occlusionBounds: cloneOcclusionBounds(draft.occlusionBounds),
    depthBounds: cloneDepthBounds(draft.depthBounds),
  };
}

function serializeDraft(draft: ObjectTemplateDraft): string {
  return JSON.stringify(draft);
}

function draftFromChoice(choice: ObjectVisualChoice): ObjectTemplateDraft {
  return {
    displayName: choice.displayName,
    scale: choice.scale,
    visualOffset: { ...choice.visualOffset },
    collider: cloneCollider(choice.collider),
    occlusionBounds: cloneOcclusionBounds(choice.occlusionBounds),
    depthBounds: cloneDepthBounds(choice.depthBounds),
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

  if (!Number.isFinite(draft.scale) || draft.scale < 0.05 || draft.scale > 8) {
    errors.scale = 'Scale must be between 0.05 and 8.';
  }

  if (!isInteger(draft.visualOffset.x)) errors.visualOffsetX = 'Use a whole number of pixels.';
  if (!isInteger(draft.visualOffset.y)) errors.visualOffsetY = 'Use a whole number of pixels.';

  if (draft.occlusionBounds) {
    if (!dimensions) {
      errors.occlusionBounds = 'Occlusion requires an authoritative spritesheet frame.';
    } else if (choice.visualSetId || choice.animationClip) {
      errors.occlusionBounds = 'Animated object templates cannot occlude actors yet.';
    } else {
      const { width, height, offsetX, offsetY } = draft.occlusionBounds;
      if (!isInteger(width) || width < 1) errors.occlusionWidth = 'Width must be a positive whole number.';
      if (!isInteger(height) || height < 1) errors.occlusionHeight = 'Height must be a positive whole number.';
      if (!isInteger(offsetX) || offsetX < 0) errors.occlusionOffsetX = 'Offset must be 0 or more.';
      if (!isInteger(offsetY) || offsetY < 0) errors.occlusionOffsetY = 'Offset must be 0 or more.';
      if (isInteger(width) && isInteger(offsetX) && offsetX + width > dimensions.width) {
        errors.occlusionWidth = `Occlusion must fit inside the ${dimensions.width}px frame.`;
      }
      if (isInteger(height) && isInteger(offsetY) && offsetY + height > dimensions.height) {
        errors.occlusionHeight = `Occlusion must fit inside the ${dimensions.height}px frame.`;
      }
    }
  }

  if (choice.physics === null) {
    if (draft.collider) errors.collider = 'Decorative templates cannot have a collider.';
    return errors;
  }

  if (!draft.collider) {
    errors.collider = 'Solid templates require a collider.';
    return errors;
  }
  const { width, height, offsetX, offsetY } = draft.collider;
  const shape = draft.collider.shape ?? 'rectangle';
  if (shape !== 'rectangle' && shape !== 'circle' && shape !== 'ellipse') errors.shape = 'Choose rectangle, circle, or ellipse.';
  if (shape === 'circle' && (!Number.isInteger(draft.collider.radius) || (draft.collider.radius ?? 0) < 1)) errors.radius = 'Circle radius must be a positive whole number.';
  if (shape === 'ellipse') {
    if (!Number.isInteger(draft.collider.radiusX) || (draft.collider.radiusX ?? 0) < 1) errors.radiusX = 'Ellipse radius X must be a positive whole number.';
    if (!Number.isInteger(draft.collider.radiusY) || (draft.collider.radiusY ?? 0) < 1) errors.radiusY = 'Ellipse radius Y must be a positive whole number.';
  }

  if (draft.depthBounds) {
    if (!dimensions) {
      errors.depthBounds = 'Depth bounds require an authoritative spritesheet frame.';
    } else {
      const { width, height, offsetX, offsetY } = draft.depthBounds;
      if (!isInteger(width) || width < 1) errors.depthWidth = 'Width must be a positive whole number.';
      if (!isInteger(height) || height < 1) errors.depthHeight = 'Height must be a positive whole number.';
      if (!isInteger(offsetX) || offsetX < 0) errors.depthOffsetX = 'Offset must be 0 or more.';
      if (!isInteger(offsetY) || offsetY < 0) errors.depthOffsetY = 'Offset must be 0 or more.';
      if (isInteger(width) && isInteger(offsetX) && offsetX + width > dimensions.width) {
        errors.depthWidth = `Depth bound must fit inside the ${dimensions.width}px frame.`;
      }
      if (isInteger(height) && isInteger(offsetY) && offsetY + height > dimensions.height) {
        errors.depthHeight = `Depth bound must fit inside the ${dimensions.height}px frame.`;
      }
    }
  }
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
  private showAllMatchingOverlaysValue = false;
  private showFrameOverlayValue = true;
  private showColliderOverlayValue = true;
  private showOcclusionOverlayValue = true;
  private showDepthOverlayValue = true;
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
      showAllMatchingOverlays: this.showAllMatchingOverlaysValue,
      showFrameOverlay: this.showFrameOverlayValue,
      showColliderOverlay: this.showColliderOverlayValue,
      showOcclusionOverlay: this.showOcclusionOverlayValue,
      showDepthOverlay: this.showDepthOverlayValue,
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

  setShowAllMatchingOverlays(showAll: boolean): void {
    if (this.showAllMatchingOverlaysValue === showAll) return;
    this.showAllMatchingOverlaysValue = showAll;
    this.emit();
  }

  setOverlayVisibility(key: EditorGeometryKey, visible: boolean): void {
    if (key === 'frame') {
      if (this.showFrameOverlayValue === visible) return;
      this.showFrameOverlayValue = visible;
    } else if (key === 'collider') {
      if (this.showColliderOverlayValue === visible) return;
      this.showColliderOverlayValue = visible;
    } else if (key === 'occlusion') {
      if (this.showOcclusionOverlayValue === visible) return;
      this.showOcclusionOverlayValue = visible;
    } else {
      if (this.showDepthOverlayValue === visible) return;
      this.showDepthOverlayValue = visible;
    }
    this.emit();
  }

  updateDraft(patch: Partial<ObjectTemplateDraft>): boolean {
    if (!this.selectedValue || !this.draftValue) return false;
    const next: ObjectTemplateDraft = {
      displayName: patch.displayName ?? this.draftValue.displayName,
      scale: patch.scale ?? this.draftValue.scale,
      visualOffset: patch.visualOffset
        ? { ...this.draftValue.visualOffset, ...patch.visualOffset }
        : { ...this.draftValue.visualOffset },
      collider: patch.collider === undefined
        ? cloneCollider(this.draftValue.collider)
        : cloneCollider(patch.collider),
      occlusionBounds: 'occlusionBounds' in patch
        ? cloneOcclusionBounds(patch.occlusionBounds)
        : cloneOcclusionBounds(this.draftValue.occlusionBounds),
      depthBounds: 'depthBounds' in patch
        ? cloneDepthBounds(patch.depthBounds)
        : cloneDepthBounds(this.draftValue.depthBounds),
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
          scale: draft.scale,
          visualOffset: draft.visualOffset,
          collider: draft.collider,
          occlusionBounds: draft.occlusionBounds,
          depthBounds: draft.depthBounds,
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

  async saveAsNewTemplate(
    visualId: string,
    displayName: string,
  ): Promise<DuplicatedObjectTemplate | undefined> {
    const selected = this.selectedValue;
    const draft = this.draftValue;
    if (!selected || !draft || this.savingValue) return undefined;
    const candidate = { ...cloneDraft(draft), displayName };
    const errors = validateObjectTemplateDraft(selected, candidate);
    if (Object.keys(errors).length > 0) {
      this.statusValue = Object.values(errors)[0] ?? 'Fix template errors before saving';
      this.emit();
      return undefined;
    }

    this.savingValue = true;
    this.statusValue = 'Saving new template...';
    this.emit();
    try {
      const response = await fetch('/__map-editor/object-template/duplicate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          objectId: selected.objectId,
          sourceVisualId: selected.visualId,
          visualId,
          displayName,
          scale: draft.scale,
          visualOffset: draft.visualOffset,
          collider: draft.collider,
          occlusionBounds: draft.occlusionBounds,
          depthBounds: draft.depthBounds,
        }),
      });
      const result = await response.json() as {
        ok?: boolean;
        error?: string;
        objectId?: ObjectArchetypeId;
        visualId?: string;
      };
      if (!response.ok || !result.ok || !result.objectId || !result.visualId) {
        throw new Error(result.error ?? `Template creation failed (${response.status})`);
      }
      this.statusValue = `Created ${displayName}`;
      this.errorsValue = {};
      return { objectId: result.objectId, visualId: result.visualId };
    } catch (error) {
      this.statusValue = error instanceof Error ? error.message : String(error);
      throw error;
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
