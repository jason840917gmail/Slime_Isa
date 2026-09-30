import type { JsonValue } from '../../content/scenes/types';
import type { ModalHandle, ModalStack } from '../../ui/ModalStack';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

export interface MenuSurfaceOptions {
  readonly modalStack: ModalStack;
  /** The simulation pauses while the menu is open (omit for menus over an already paused game). */
  readonly onPausedChange?: (paused: boolean) => void;
  /** False for menus Escape must not close (the title screen). */
  readonly closableByEscape?: boolean;
}

/**
 * Shared lifecycle of the game-shell menus (pause, settings, title, saves,
 * game over, credits): one modal-stack entry, open/close with pausing, and a
 * presentation model pushed to the authored `ui.*` scene through
 * `game.ui-surface`. Subclasses provide the model and handle actions.
 */
export abstract class MenuSurface implements UiSurfacePort {
  private readonly handle: ModalHandle;
  private readonly listeners = new Set<(model: UiPresentationModel) => void>();
  private openValue = false;
  private stopped = false;

  protected constructor(readonly surfaceId: string, private readonly menuOptions: MenuSurfaceOptions) {
    this.handle = menuOptions.modalStack.register(surfaceId, {
      isOpen: () => this.openValue,
      canClose: () => menuOptions.closableByEscape !== false,
      close: () => this.close(),
    });
  }

  isOpen(): boolean { return this.openValue; }

  open(): void {
    if (this.openValue || this.stopped) return;
    this.openValue = true;
    this.menuOptions.onPausedChange?.(true);
    this.handle.open();
    this.onOpened();
    this.publish();
  }

  close(): void {
    if (!this.openValue) { this.handle.close(); return; }
    this.openValue = false;
    this.handle.close();
    this.menuOptions.onPausedChange?.(false);
    this.publish();
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== this.surfaceId || this.stopped) return {};
    return { open: this.openValue, ...this.model() };
  }

  subscribe(surfaceId: string, listener: (model: UiPresentationModel) => void): () => void {
    if (surfaceId !== this.surfaceId || this.stopped) return () => undefined;
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  invoke(surfaceId: string, actionId: string, payload?: JsonValue): void {
    if (surfaceId !== this.surfaceId || this.stopped) return;
    if (actionId === 'close') { this.close(); return; }
    this.act(actionId, payload);
  }

  destroy(): void {
    if (this.stopped) return;
    this.close();
    this.stopped = true;
    this.handle.unregister();
    this.listeners.clear();
  }

  /** The surface-specific part of the presentation model (`open` is added). */
  protected abstract model(): UiPresentationModel;
  /** Handles one bound action other than `close`. */
  protected abstract act(actionId: string, payload?: JsonValue): void;
  /** Refreshes derived state each time the menu opens. */
  protected onOpened(): void {}

  protected publish(): void {
    if (this.stopped) return;
    const model = this.snapshot(this.surfaceId);
    for (const listener of this.listeners) listener(model);
  }
}
