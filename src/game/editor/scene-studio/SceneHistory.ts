import type { SceneDocument } from '../../content/scenes/types';
import type { SceneCommand } from './SceneCommand';
import type { SceneSelection } from './SceneSelectionState';

export interface SceneHistorySnapshot {
  readonly document: SceneDocument;
  readonly selection: SceneSelection;
}

interface SceneHistoryEntry {
  readonly label: string;
  readonly before: SceneHistorySnapshot;
  readonly after: SceneHistorySnapshot;
}

const clone = <T>(value: T): T => structuredClone(value);

export class SceneHistory {
  private entries: SceneHistoryEntry[] = [];
  private cursor = 0;
  private savedCursor = 0;

  get canUndo(): boolean { return this.cursor > 0; }
  get canRedo(): boolean { return this.cursor < this.entries.length; }
  get dirty(): boolean { return this.savedCursor < 0 || this.cursor !== this.savedCursor; }
  get undoLabel(): string | undefined { return this.entries[this.cursor - 1]?.label; }
  get redoLabel(): string | undefined { return this.entries[this.cursor]?.label; }

  execute(command: SceneCommand, current: SceneHistorySnapshot): SceneHistorySnapshot {
    const result = command.apply(clone(current.document));
    const after = { document: clone(result.document), selection: clone(result.selection ?? current.selection) };
    if (this.cursor < this.entries.length) {
      this.entries.splice(this.cursor);
      if (this.savedCursor > this.cursor) this.savedCursor = -1;
    }
    this.entries.push({ label: command.label, before: clone(current), after: clone(after) });
    this.cursor += 1;
    return after;
  }

  undo(): SceneHistorySnapshot | undefined {
    if (!this.canUndo) return undefined;
    this.cursor -= 1;
    return clone(this.entries[this.cursor].before);
  }

  redo(): SceneHistorySnapshot | undefined {
    if (!this.canRedo) return undefined;
    const snapshot = clone(this.entries[this.cursor].after);
    this.cursor += 1;
    return snapshot;
  }

  markSaved(): void { this.savedCursor = this.cursor; }
  reset(): void { this.entries = []; this.cursor = 0; this.savedCursor = 0; }
}
