import type { DescriptorRegistry, PropertyDescriptor } from '../../content/scenes/propertyDescriptors';
import { descriptorMap, propertiesForNode } from '../../content/scenes/propertyDescriptors';
import type { AuthoredNodeId, SceneId } from '../../content/scenes/identifiers';
import type { JsonValue, SceneDocument } from '../../content/scenes/types';
import type { SceneValidationContext, SceneValidationIssue } from '../../content/scenes/validation';
import { sceneCommands, type SceneCommand } from './SceneCommand';
import { SceneHistory, type SceneHistorySnapshot } from './SceneHistory';
import { SceneSelectionState, type SceneSelection } from './SceneSelectionState';
import { SceneValidationState } from './SceneValidationState';

export interface AffectedNodeReference {
  readonly ownerNodeId: AuthoredNodeId;
  readonly property: string;
  readonly targetNodeId: AuthoredNodeId;
  readonly required: boolean;
  readonly descriptor: PropertyDescriptor;
}

export type DeleteReferenceResolution =
  | { readonly kind: 'cancel' }
  | { readonly kind: 'remove-optional' }
  | { readonly kind: 'repair'; readonly replacements: Readonly<Record<string, JsonValue | null>> };

export type DeleteNodeResult =
  | { readonly kind: 'cancelled' }
  | { readonly kind: 'requires-repair'; readonly references: readonly AffectedNodeReference[] }
  | { readonly kind: 'deleted' };

const clone = <T>(value: T): T => structuredClone(value);

function removedSubtree(document: SceneDocument, nodeId: AuthoredNodeId): ReadonlySet<AuthoredNodeId> {
  const removed = new Set<AuthoredNodeId>([nodeId]);
  let changed = true;
  while (changed) {
    changed = false;
    for (const node of document.nodes) if (node.parentId && removed.has(node.parentId) && !removed.has(node.id)) { removed.add(node.id); changed = true; }
  }
  return removed;
}

function referenceTarget(value: JsonValue): AuthoredNodeId | undefined {
  if (value === null || Array.isArray(value) || typeof value !== 'object') return undefined;
  const record = value as Readonly<Record<string, JsonValue>>;
  if (Array.isArray(record.instancePath) && record.instancePath.length > 0) return undefined;
  return typeof record.nodeId === 'string' ? record.nodeId as AuthoredNodeId : undefined;
}

export function affectedReferences(document: SceneDocument, nodeId: AuthoredNodeId, registry: DescriptorRegistry): readonly AffectedNodeReference[] {
  const removed = removedSubtree(document, nodeId);
  const affected: AffectedNodeReference[] = [];
  for (const owner of document.nodes) {
    if (removed.has(owner.id)) continue;
    const descriptors = descriptorMap(propertiesForNode(owner.type, owner.scriptId, registry) ?? []);
    for (const [property, value] of Object.entries(owner.properties)) {
      const descriptor = descriptors.get(property);
      const targetNodeId = descriptor?.value.kind === 'node-reference' ? referenceTarget(value) : undefined;
      if (descriptor && targetNodeId && removed.has(targetNodeId)) affected.push({ ownerNodeId: owner.id, property, targetNodeId, required: descriptor.required ?? false, descriptor });
    }
  }
  return affected;
}

export class SceneDocumentState {
  private documentValue: SceneDocument;
  private readonly selectionState = new SceneSelectionState();
  private readonly history = new SceneHistory();
  private readonly validation: SceneValidationState;
  private diskHashValue?: string;
  private revisionValue = 0;

  constructor(document: SceneDocument, validationContext: SceneValidationContext, diskHash?: string) {
    this.documentValue = clone(document);
    this.validation = new SceneValidationState(validationContext);
    this.diskHashValue = diskHash;
    this.validation.update(this.documentValue);
  }

  get sceneId(): SceneId { return this.documentValue.sceneId; }
  get document(): SceneDocument { return clone(this.documentValue); }
  get selection(): SceneSelection { return this.selectionState.value; }
  get issues(): readonly SceneValidationIssue[] { return this.validation.issues; }
  get repairMode(): boolean { return this.validation.repairMode; }
  get dirty(): boolean { return this.history.dirty; }
  get canUndo(): boolean { return this.history.canUndo; }
  get canRedo(): boolean { return this.history.canRedo; }
  get diskHash(): string | undefined { return this.diskHashValue; }
  /** Increments whenever the document content changes (execute, undo, redo). */
  get revision(): number { return this.revisionValue; }

  select(selection: SceneSelection): void { this.selectionState.select(selection); }

  execute(command: SceneCommand): void {
    this.restore(this.history.execute(command, this.snapshot()));
  }

  undo(): boolean {
    const snapshot = this.history.undo();
    if (!snapshot) return false;
    this.restore(snapshot);
    return true;
  }

  redo(): boolean {
    const snapshot = this.history.redo();
    if (!snapshot) return false;
    this.restore(snapshot);
    return true;
  }

  markSaved(diskHash: string): void { this.diskHashValue = diskHash; this.history.markSaved(); }

  requestDeleteNode(nodeId: AuthoredNodeId, resolution?: DeleteReferenceResolution): DeleteNodeResult {
    if (resolution?.kind === 'cancel') return { kind: 'cancelled' };
    const references = affectedReferences(this.documentValue, nodeId, this.validation.registry);
    if (references.length > 0 && !resolution) return { kind: 'requires-repair', references };
    if (resolution?.kind === 'remove-optional' && references.some((reference) => reference.required)) return { kind: 'requires-repair', references };
    const repairs = references.map((reference) => {
      const key = `${reference.ownerNodeId}.${reference.property}`;
      const replacement = resolution?.kind === 'repair' ? resolution.replacements[key] : null;
      if (reference.required && (replacement === null || replacement === undefined)) throw new Error(`Required reference '${key}' needs a replacement`);
      return { ownerNodeId: reference.ownerNodeId, property: reference.property, ...(replacement === null || replacement === undefined ? {} : { value: replacement }) };
    });
    this.execute(sceneCommands.deleteSubtree(nodeId, repairs));
    return { kind: 'deleted' };
  }

  private snapshot(): SceneHistorySnapshot { return { document: this.documentValue, selection: this.selectionState.value }; }

  private restore(snapshot: SceneHistorySnapshot): void {
    this.documentValue = clone(snapshot.document);
    this.revisionValue += 1;
    this.selectionState.restore(snapshot.selection);
    this.validation.update(this.documentValue);
  }
}

export class SceneDocumentWorkspace {
  private readonly tabs = new Map<SceneId, SceneDocumentState>();
  private activeId?: SceneId;

  get active(): SceneDocumentState | undefined { return this.activeId ? this.tabs.get(this.activeId) : undefined; }
  get openSceneIds(): readonly SceneId[] { return [...this.tabs.keys()]; }

  open(document: SceneDocument, validationContext: SceneValidationContext, diskHash?: string): SceneDocumentState {
    const existing = this.tabs.get(document.sceneId);
    if (existing) { this.activeId = document.sceneId; return existing; }
    const state = new SceneDocumentState(document, validationContext, diskHash);
    this.tabs.set(document.sceneId, state);
    this.activeId = document.sceneId;
    return state;
  }

  activate(sceneId: SceneId): boolean { if (!this.tabs.has(sceneId)) return false; this.activeId = sceneId; return true; }

  close(sceneId: SceneId, discard = false): boolean {
    const state = this.tabs.get(sceneId);
    if (!state || (state.dirty && !discard)) return false;
    this.tabs.delete(sceneId);
    if (this.activeId === sceneId) this.activeId = [...this.tabs.keys()].at(-1);
    return true;
  }
}
