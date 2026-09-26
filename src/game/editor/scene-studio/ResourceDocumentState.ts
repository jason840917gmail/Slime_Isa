import type { JsonValue, SceneResourceDocument } from '../../content/scenes/types';
import { editResourceField } from './ResourceInspector';

export class ResourceDocumentState {
  private current: SceneResourceDocument;
  private saved: string;
  private readonly undoStack: SceneResourceDocument[] = [];
  private readonly redoStack: SceneResourceDocument[] = [];
  diskHash?: string;

  constructor(document: SceneResourceDocument, diskHash?: string) {
    this.current = structuredClone(document);
    this.saved = JSON.stringify(document);
    this.diskHash = diskHash;
  }

  get document(): SceneResourceDocument { return this.current; }
  get dirty(): boolean { return JSON.stringify(this.current) !== this.saved; }
  get canUndo(): boolean { return this.undoStack.length > 0; }
  get canRedo(): boolean { return this.redoStack.length > 0; }

  setField(field: string, value: JsonValue): void {
    const next = editResourceField(this.current, field, value);
    if (JSON.stringify(next) === JSON.stringify(this.current)) return;
    this.undoStack.push(this.current);
    this.redoStack.length = 0;
    this.current = next;
  }

  undo(): boolean {
    const previous = this.undoStack.pop();
    if (!previous) return false;
    this.redoStack.push(this.current);
    this.current = previous;
    return true;
  }

  redo(): boolean {
    const next = this.redoStack.pop();
    if (!next) return false;
    this.undoStack.push(this.current);
    this.current = next;
    return true;
  }

  markSaved(hash: string): void {
    this.diskHash = hash;
    this.saved = JSON.stringify(this.current);
  }
}
