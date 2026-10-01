import type { NamedSaveMetadata } from '../../infrastructure/persistence/SaveSchema';
import type { UiPresentationModel } from '../scripts/ui/UiSurfaceScript';
import { MenuSurface, type MenuSurfaceOptions } from './MenuSurface';

export type SaveOutcome = { readonly ok: true } | { readonly ok: false; readonly message: string };

/** The save operations the slots use (SaveSystem's named saves and the autosave). */
export interface SaveSlotStorage {
  list(): readonly NamedSaveMetadata[];
  /** Named saves that exist but cannot be read, with why (a slot shows the reason instead of "Empty"). */
  unreadable(): readonly { readonly name: string; readonly reason: string }[];
  create(name: string): SaveOutcome;
  overwrite(saveId: string): SaveOutcome;
  /** Starts loading a save; on success the page travels to it. */
  load(saveId: string): Promise<SaveOutcome>;
  /** The recovery autosave, listed first when loading. */
  autosave(): { readonly mapId: string; readonly playTimeMs: number } | undefined;
  loadAutosave(): SaveOutcome;
}

export interface SaveSlotsSurfaceOptions extends MenuSurfaceOptions {
  readonly storage: SaveSlotStorage;
  /** Display name of a saved map ("Slimeshire Meadow"). */
  readonly placeName: (mapId: string) => string;
  /** Formats a save time for the slot label. */
  readonly formatTime?: (epochMs: number) => string;
}

export type SaveSlotsMode = 'save' | 'load';

export const SAVE_SLOTS_SURFACE_ID = 'save-slots';
export const SAVE_SLOT_COUNT = 3;

/** Slots are named saves called "Slot 1" to "Slot 3". */
export function slotName(slot: number): string {
  return `Slot ${slot}`;
}

export function formatPlayTime(ms: number): string {
  const minutes = Math.floor(Math.max(0, ms) / 60_000);
  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, '0')} played`;
}

/**
 * Three save slots for players. In save mode (pause menu) a slot saves the
 * current run, asking before it overwrites one; in load mode (title, pause,
 * defeat) the autosave comes first, then each slot loads its run. Empty slots
 * cannot be loaded, and a slot whose save cannot be read says why.
 */
export class SaveSlotsSurfacePort extends MenuSurface {
  private mode: SaveSlotsMode = 'save';
  private confirmSlot?: number;
  private status = '';
  private busy = false;

  constructor(private readonly options: SaveSlotsSurfaceOptions) {
    super(SAVE_SLOTS_SURFACE_ID, options);
  }

  /** Opens the slots to save or to load. */
  openFor(mode: SaveSlotsMode): void {
    this.mode = mode;
    this.confirmSlot = undefined;
    this.status = '';
    if (this.isOpen()) this.publish();
    else this.open();
  }

  protected model(): UiPresentationModel {
    const slots = this.slots();
    const unreadable = this.options.storage.unreadable();
    const confirming = this.confirmSlot !== undefined;
    const autosave = this.mode === 'load' ? this.options.storage.autosave() : undefined;
    const model: Record<string, string | boolean> = {
      title: this.mode === 'save' ? 'Save game' : 'Load game',
      status: confirming ? `${slotName(this.confirmSlot!)} already holds a save. Overwrite it?` : this.status,
      confirming,
      listVisible: !confirming,
      autosaveVisible: !!autosave,
      autosaveLabel: autosave
        ? `Autosave (latest)  ·  ${this.options.placeName(autosave.mapId)}  ·  ${formatPlayTime(autosave.playTimeMs)}`
        : 'Autosave  ·  None yet',
      autosaveDisabled: this.busy || !autosave,
    };
    slots.forEach((save, index) => {
      const broken = save ? undefined : unreadable.find((entry) => entry.name === slotName(index + 1));
      model[`slot${index + 1}Label`] = save ? this.describe(index + 1, save)
        : broken ? `${slotName(index + 1)}  ·  Can't be loaded: ${broken.reason}`
          : `${slotName(index + 1)}  ·  Empty`;
      model[`slot${index + 1}Disabled`] = this.busy || (this.mode === 'load' && !save);
    });
    return model;
  }

  protected act(actionId: string): void {
    if (this.busy) return;
    if (actionId === 'autosave') { this.useAutosave(); return; }
    const slot = /^slot-(\d)$/.exec(actionId);
    if (slot) { this.useSlot(Number(slot[1])); return; }
    if (actionId === 'confirm' && this.confirmSlot !== undefined) {
      const target = this.slots()[this.confirmSlot - 1];
      const slotNumber = this.confirmSlot;
      this.confirmSlot = undefined;
      if (target) this.report(this.options.storage.overwrite(target.saveId), slotNumber);
      else this.publish();
      return;
    }
    if (actionId === 'cancel') { this.confirmSlot = undefined; this.publish(); }
  }

  private useSlot(slot: number): void {
    if (slot < 1 || slot > SAVE_SLOT_COUNT) return;
    const save = this.slots()[slot - 1];
    if (this.mode === 'save') {
      if (save) { this.confirmSlot = slot; this.publish(); return; }
      this.report(this.options.storage.create(slotName(slot)), slot);
      return;
    }
    if (!save) return;
    this.busy = true;
    this.status = `Loading ${slotName(slot)}…`;
    this.publish();
    void this.options.storage.load(save.saveId)
      .catch((error: unknown): SaveOutcome => ({ ok: false, message: error instanceof Error ? error.message : 'The save could not be loaded.' }))
      .then((outcome) => {
        this.busy = false;
        this.status = outcome.ok ? `Loading ${slotName(slot)}…` : outcome.message;
        this.publish();
      });
  }

  private useAutosave(): void {
    if (this.mode !== 'load') return;
    const outcome = this.options.storage.loadAutosave();
    this.busy = outcome.ok;
    this.status = outcome.ok ? 'Loading the autosave…' : outcome.message;
    this.publish();
  }

  private report(outcome: SaveOutcome, slot: number): void {
    this.status = outcome.ok ? `Saved to ${slotName(slot)}.` : outcome.message;
    this.publish();
  }

  private slots(): (NamedSaveMetadata | undefined)[] {
    const saves = this.options.storage.list();
    return Array.from({ length: SAVE_SLOT_COUNT }, (_, index) => saves.find((save) => save.name === slotName(index + 1)));
  }

  private describe(slot: number, save: NamedSaveMetadata): string {
    const when = this.options.formatTime?.(save.updatedAt) ?? new Date(save.updatedAt).toLocaleString();
    return `${slotName(slot)}  ·  ${this.options.placeName(save.currentMapId)}  ·  ${formatPlayTime(save.playTimeMs)}  ·  ${when}`;
  }
}
