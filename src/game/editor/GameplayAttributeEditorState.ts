import {
  getObjectArchetype,
  getObjectVisualChoices,
  isObjectArchetypeId,
  type ObjectArchetypeId,
} from '../content/objects/ObjectCatalog';
import { isKnownItemId } from '../content/items/ItemCatalog';
import { resourceTagIssue } from '../content/ResourceTags';

export interface CollectibleGameplayDraft {
  readonly kind: 'collectible';
  readonly itemId: string;
  readonly quantity: number;
}

export interface ResourceGameplayDraft {
  readonly kind: 'resource';
  readonly health: number;
  readonly dropObjectId: string;
  readonly dropVisualId: string;
  readonly dropPieces: number;
  readonly hitEffectId: string;
  readonly persistHealth: boolean;
  readonly depletionMessage: string;
  readonly harvestTargetTag: string;
  readonly harvestMinimumTier: number;
  readonly harvestFailureMessage: string;
}

export type GameplayAttributeDraft = CollectibleGameplayDraft | ResourceGameplayDraft;

export interface GameplayAttributeViewState {
  readonly selectedObjectId?: ObjectArchetypeId;
  readonly draft?: GameplayAttributeDraft;
  readonly errors: Readonly<Record<string, string>>;
  readonly dirty: boolean;
  readonly hasDirtyDrafts: boolean;
  readonly saving: boolean;
  readonly status: string;
  readonly revision: number;
}

type Listener = (state: GameplayAttributeViewState) => void;

function cloneDraft(draft: GameplayAttributeDraft): GameplayAttributeDraft {
  return { ...draft };
}

function draftFor(objectId: ObjectArchetypeId): GameplayAttributeDraft | undefined {
  const definition = getObjectArchetype(objectId);
  if (definition.collectible) {
    return {
      kind: 'collectible',
      itemId: definition.collectible.itemId,
      quantity: definition.collectible.quantity,
    };
  }
  if (definition.resourceNode) {
    const requirement = definition.resourceNode.harvestRequirement;
    return {
      kind: 'resource',
      health: definition.resourceNode.health,
      dropObjectId: definition.resourceNode.drop.objectId,
      dropVisualId: definition.resourceNode.drop.visualId,
      dropPieces: definition.resourceNode.drop.pieces,
      hitEffectId: definition.resourceNode.hitEffectId ?? '',
      persistHealth: definition.resourceNode.persistHealth !== false,
      depletionMessage: definition.resourceNode.depletionMessage ?? '',
      harvestTargetTag: requirement?.targetTag ?? '',
      harvestMinimumTier: requirement?.minimumTier ?? 1,
      harvestFailureMessage: requirement?.failureMessage ?? '',
    };
  }
  return undefined;
}

function validateDraft(draft: GameplayAttributeDraft): Readonly<Record<string, string>> {
  const errors: Record<string, string> = {};
  if (draft.kind === 'collectible') {
    if (!draft.itemId.trim()) errors.itemId = 'Item ID is required.';
    else if (!isKnownItemId(draft.itemId.trim())) errors.itemId = 'Choose a registered inventory item.';
    if (!Number.isInteger(draft.quantity) || draft.quantity < 1) errors.quantity = 'Quantity must be a whole number of 1 or more.';
    return errors;
  }
  if (!Number.isInteger(draft.health) || draft.health < 1) errors.health = 'Life points must be a whole number of 1 or more.';
  if (!isObjectArchetypeId(draft.dropObjectId) || !getObjectArchetype(draft.dropObjectId).collectible) {
    errors.dropObjectId = 'Choose a collectible drop.';
  }
  const visuals = getObjectVisualChoices().filter((choice) => choice.objectId === draft.dropObjectId);
  if (!visuals.some((choice) => choice.visualId === draft.dropVisualId)) errors.dropVisualId = 'Choose a visual from the selected collectible.';
  if (!Number.isInteger(draft.dropPieces) || draft.dropPieces < 1) errors.dropPieces = 'Pieces must be a whole number of 1 or more.';
  const harvestTargetTag = draft.harvestTargetTag.trim();
  if (harvestTargetTag) {
    const issue = resourceTagIssue(harvestTargetTag);
    if (issue) errors.harvestTargetTag = issue;
    if (draft.harvestMinimumTier < 1 || !Number.isInteger(draft.harvestMinimumTier)) errors.harvestMinimumTier = 'Tool tier must be 1 or more.';
    if (!draft.harvestFailureMessage.trim()) errors.harvestFailureMessage = 'Add a message for a required tool.';
  }
  return errors;
}

function payloadFor(draft: GameplayAttributeDraft): Record<string, unknown> {
  if (draft.kind === 'collectible') {
    return { collectible: { itemId: draft.itemId.trim(), quantity: draft.quantity } };
  }
  return {
    resourceNode: {
      health: draft.health,
      drop: { objectId: draft.dropObjectId, visualId: draft.dropVisualId, pieces: draft.dropPieces },
      hitEffectId: draft.hitEffectId.trim() || undefined,
      persistHealth: draft.persistHealth,
      depletionMessage: draft.depletionMessage.trim() || undefined,
      harvestRequirement: draft.harvestTargetTag.trim()
        ? {
            targetTag: draft.harvestTargetTag.trim(),
            minimumTier: draft.harvestMinimumTier,
            failureMessage: draft.harvestFailureMessage.trim(),
          }
        : undefined,
    },
  };
}

export class GameplayAttributeEditorState {
  private selectedObjectIdValue?: ObjectArchetypeId;
  private draftValue?: GameplayAttributeDraft;
  private savedDraft?: GameplayAttributeDraft;
  private errorsValue: Readonly<Record<string, string>> = {};
  private dirtyValue = false;
  private savingValue = false;
  private statusValue = 'Select a resource or collectible to inspect';
  private revisionValue = 0;
  private readonly savedDrafts = new Map<ObjectArchetypeId, GameplayAttributeDraft>();
  private readonly workingDrafts = new Map<ObjectArchetypeId, GameplayAttributeDraft>();
  private readonly dirtyObjectIds = new Set<ObjectArchetypeId>();
  private listeners = new Set<Listener>();

  get value(): GameplayAttributeViewState {
    return {
      selectedObjectId: this.selectedObjectIdValue,
      draft: this.draftValue ? cloneDraft(this.draftValue) : undefined,
      errors: this.errorsValue,
      dirty: this.dirtyValue,
      hasDirtyDrafts: this.dirtyObjectIds.size > 0,
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

  select(objectId?: ObjectArchetypeId): void {
    if (objectId === this.selectedObjectIdValue) return;
    if (this.selectedObjectIdValue && this.draftValue) {
      this.workingDrafts.set(this.selectedObjectIdValue, cloneDraft(this.draftValue));
    }
    this.selectedObjectIdValue = objectId;
    this.savedDraft = objectId
      ? this.savedDrafts.get(objectId) ?? draftFor(objectId)
      : undefined;
    if (objectId && this.savedDraft && !this.savedDrafts.has(objectId)) this.savedDrafts.set(objectId, cloneDraft(this.savedDraft));
    const selectedDraft = objectId ? this.workingDrafts.get(objectId) ?? this.savedDraft : undefined;
    this.draftValue = selectedDraft ? cloneDraft(selectedDraft) : undefined;
    this.dirtyValue = objectId ? this.dirtyObjectIds.has(objectId) : false;
    this.errorsValue = this.draftValue ? validateDraft(this.draftValue) : {};
    this.statusValue = objectId && this.draftValue
      ? this.dirtyValue ? `Restored unsaved gameplay draft for ${objectId}` : `Inspecting ${objectId}`
      : 'This object has no gameplay attributes';
    this.revisionValue += 1;
    this.emit();
  }

  updateDraft(patch: Partial<CollectibleGameplayDraft> | Partial<ResourceGameplayDraft>): boolean {
    if (!this.draftValue || !this.savedDraft) return false;
    const next = { ...this.draftValue, ...patch } as GameplayAttributeDraft;
    this.draftValue = next;
    if (this.selectedObjectIdValue) this.workingDrafts.set(this.selectedObjectIdValue, cloneDraft(next));
    this.errorsValue = validateDraft(next);
    this.dirtyValue = JSON.stringify(next) !== JSON.stringify(this.savedDraft);
    if (this.selectedObjectIdValue) {
      if (this.dirtyValue) this.dirtyObjectIds.add(this.selectedObjectIdValue);
      else this.dirtyObjectIds.delete(this.selectedObjectIdValue);
    }
    this.statusValue = Object.keys(this.errorsValue).length > 0 ? 'Draft has validation errors' : this.dirtyValue ? 'Unsaved gameplay draft' : 'Gameplay matches saved definition';
    this.revisionValue += 1;
    this.emit();
    return Object.keys(this.errorsValue).length === 0;
  }

  resetChanges(): void {
    if (!this.savedDraft) return;
    this.draftValue = cloneDraft(this.savedDraft);
    if (this.selectedObjectIdValue) {
      this.workingDrafts.set(this.selectedObjectIdValue, cloneDraft(this.savedDraft));
      this.dirtyObjectIds.delete(this.selectedObjectIdValue);
    }
    this.errorsValue = {};
    this.dirtyValue = false;
    this.statusValue = 'Gameplay changes reset';
    this.revisionValue += 1;
    this.emit();
  }

  async save(): Promise<void> {
    const objectId = this.selectedObjectIdValue;
    const draft = this.draftValue;
    if (!objectId || !draft || this.savingValue || !this.dirtyValue) return;
    this.errorsValue = validateDraft(draft);
    if (Object.keys(this.errorsValue).length > 0) {
      this.statusValue = 'Fix gameplay errors before saving';
      this.revisionValue += 1;
      this.emit();
      return;
    }
    this.savingValue = true;
    this.statusValue = 'Saving gameplay attributes...';
    this.emit();
    try {
      const response = await fetch('/__map-editor/object-gameplay/update', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ objectId, ...payloadFor(draft) }),
      });
      const result = await response.json() as { ok?: boolean; error?: string };
      if (!response.ok || !result.ok) throw new Error(result.error ?? `Gameplay save failed (${response.status})`);
      this.savedDraft = cloneDraft(draft);
      this.savedDrafts.set(objectId, cloneDraft(draft));
      this.workingDrafts.set(objectId, cloneDraft(draft));
      this.dirtyObjectIds.delete(objectId);
      this.dirtyValue = false;
      this.errorsValue = {};
      this.statusValue = `Saved gameplay for ${objectId}`;
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
