import {
  validateGameConstants,
  type GameConstantsIssue,
} from '../content/GameConstantsValidation';
import type { GameConstants } from '../Constant';

export type GameConstantsSaveState = 'clean' | 'dirty' | 'saving' | 'saved' | 'error' | 'conflict';
export type GameConstantsScalarSection = 'initialAttributes' | 'movement' | 'player' | 'progression';
export type GameConstantsLevelField = 'xpToNextLevel' | 'maxHp' | 'maxEnergy' | 'attack' | 'defense';

type DeepMutable<T> = T extends readonly (infer Item)[]
  ? DeepMutable<Item>[]
  : T extends object
    ? { -readonly [Key in keyof T]: DeepMutable<T[Key]> }
    : T;

type MutableGameConstants = DeepMutable<GameConstants>;

export interface GameConstantsStudioSnapshot {
  readonly document: GameConstants;
  readonly revision: string;
  readonly dirty: boolean;
  readonly errors: readonly GameConstantsIssue[];
  readonly saveState: GameConstantsSaveState;
  readonly statusMessage: string;
}

type Listener = (snapshot: GameConstantsStudioSnapshot) => void;
type Command = { readonly label: string; readonly before: MutableGameConstants; readonly after: MutableGameConstants };

function clone<T>(value: T): T {
  return structuredClone(value);
}

export class GameConstantsStudioState {
  private draft: MutableGameConstants;
  private saved: MutableGameConstants;
  private revision: string;
  private errors: readonly GameConstantsIssue[] = [];
  private saveState: GameConstantsSaveState = 'clean';
  private statusMessage = 'Gameplay defaults saved';
  private readonly undoStack: Command[] = [];
  private readonly redoStack: Command[] = [];
  private readonly listeners = new Set<Listener>();

  constructor(document: GameConstants, revision: string) {
    this.draft = clone(document) as MutableGameConstants;
    this.saved = clone(document) as MutableGameConstants;
    this.revision = revision;
    this.revalidate();
  }

  get value(): GameConstantsStudioSnapshot {
    return {
      document: clone(this.draft) as GameConstants,
      revision: this.revision,
      dirty: JSON.stringify(this.draft) !== JSON.stringify(this.saved),
      errors: [...this.errors],
      saveState: this.saveState,
      statusMessage: this.statusMessage,
    };
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    listener(this.value);
    return () => this.listeners.delete(listener);
  }

  updateScalar(section: GameConstantsScalarSection, field: string, value: number): boolean {
    return this.mutate(`Updated ${field}`, (draft) => {
      const player = draft.character.player;
      const target = section === 'initialAttributes' ? player.initialAttributes
        : section === 'movement' ? player.movement
          : section === 'progression' ? player.progression
            : player;
      (target as unknown as Record<string, number>)[field] = value;
    });
  }

  updateLevel(level: number, field: GameConstantsLevelField, value: number): boolean {
    if (!Number.isInteger(level) || level < 1 || level > this.draft.character.player.progression.maxLevel) return false;
    if (level === 1 && field !== 'xpToNextLevel') return false;
    if (level === this.draft.character.player.progression.maxLevel && field === 'xpToNextLevel') return false;
    return this.mutate(`Updated level ${level}`, (draft) => {
      const entry = draft.character.player.progression.levels[level - 1];
      if (field === 'xpToNextLevel') entry.xpToNextLevel = value;
      else entry.gains[field] = value;
    });
  }

  setMaxLevel(maxLevel: number): boolean {
    if (!Number.isInteger(maxLevel) || maxLevel < 1) return false;
    return this.mutate(`Changed maximum level to ${maxLevel}`, (draft) => {
      const progression = draft.character.player.progression;
      if (maxLevel > progression.maxLevel) {
        const oldFinal = progression.levels[progression.levels.length - 1];
        if (oldFinal) oldFinal.xpToNextLevel = -1;
        for (let level = progression.maxLevel + 1; level <= maxLevel; level += 1) {
          progression.levels.push({
            level,
            xpToNextLevel: level === maxLevel ? null : -1,
            gains: { maxHp: -1, maxEnergy: -1, attack: -1, defense: -1 },
          });
        }
      } else if (maxLevel < progression.maxLevel) {
        progression.levels.length = maxLevel;
        progression.levels[maxLevel - 1].xpToNextLevel = null;
      }
      progression.maxLevel = maxLevel;
    });
  }

  undo(): void {
    const command = this.undoStack.pop();
    if (!command) return;
    this.redoStack.push(command);
    this.draft = clone(command.before);
    this.saveState = 'dirty';
    this.statusMessage = `Undid ${command.label}`;
    this.revalidate();
  }

  redo(): void {
    const command = this.redoStack.pop();
    if (!command) return;
    this.undoStack.push(command);
    this.draft = clone(command.after);
    this.saveState = 'dirty';
    this.statusMessage = `Redid ${command.label}`;
    this.revalidate();
  }

  markSaving(): void {
    this.saveState = 'saving';
    this.statusMessage = 'Saving gameplay defaults...';
    this.emit();
  }

  markSaved(document: GameConstants, revision: string): void {
    this.draft = clone(document) as MutableGameConstants;
    this.saved = clone(document) as MutableGameConstants;
    this.revision = revision;
    this.saveState = 'saved';
    this.statusMessage = 'Gameplay defaults saved';
    this.undoStack.length = 0;
    this.redoStack.length = 0;
    this.revalidate();
  }

  markSaveFailure(message: string, conflict = false): void {
    this.saveState = conflict ? 'conflict' : 'error';
    this.statusMessage = message;
    this.emit();
  }

  private mutate(label: string, mutation: (draft: MutableGameConstants) => void): boolean {
    const before = clone(this.draft);
    mutation(this.draft);
    if (JSON.stringify(before) === JSON.stringify(this.draft)) return false;
    this.undoStack.push({ label, before, after: clone(this.draft) });
    this.redoStack.length = 0;
    this.saveState = 'dirty';
    this.statusMessage = `${label} - unsaved`;
    this.revalidate();
    return true;
  }

  private revalidate(): void {
    this.errors = validateGameConstants(this.draft);
    this.emit();
  }

  private emit(): void {
    const snapshot = this.value;
    this.listeners.forEach((listener) => listener(snapshot));
  }
}
