import type { UiPresentationModel } from '../scripts/ui/UiSurfaceScript';
import { MenuSurface, type MenuSurfaceOptions } from './MenuSurface';

export interface PauseMenuActions {
  /** False while the pause menu must not open (title screen, defeat, travel). */
  canOpen(): boolean;
  openJournal(): void;
  openInventory(): void;
  openMap(): void;
  openSettings(): void;
  openSaves(): void;
  quitToTitle(): void;
}

export interface PauseMenuSurfaceOptions extends MenuSurfaceOptions {
  readonly actions: PauseMenuActions;
  /** Where Escape is heard (the document in the game). */
  readonly keyTarget?: Pick<Document, 'addEventListener' | 'removeEventListener'>;
}

export const PAUSE_MENU_SURFACE_ID = 'pause-menu';

/**
 * Escape with nothing else open pauses the game and shows Resume, Journal,
 * Inventory, Map, Settings, Save, and Quit to Title. Journal, Inventory and Map
 * replace the menu; Settings and Save open on top of it, so closing them
 * returns here.
 */
export class PauseMenuSurfacePort extends MenuSurface {
  private readonly keyTarget: Pick<Document, 'addEventListener' | 'removeEventListener'>;

  constructor(private readonly options: PauseMenuSurfaceOptions) {
    super(PAUSE_MENU_SURFACE_ID, options);
    this.keyTarget = options.keyTarget ?? document;
    this.keyTarget.addEventListener('keydown', this.handleShortcut, { capture: true });
  }

  protected model(): UiPresentationModel {
    return { hint: 'Esc resumes' };
  }

  protected act(actionId: string): void {
    const { actions } = this.options;
    switch (actionId) {
      case 'resume': this.close(); break;
      case 'journal': this.close(); actions.openJournal(); break;
      case 'inventory': this.close(); actions.openInventory(); break;
      case 'map': this.close(); actions.openMap(); break;
      case 'settings': actions.openSettings(); break;
      case 'save': actions.openSaves(); break;
      case 'quit': this.close(); actions.quitToTitle(); break;
      default: break;
    }
  }

  override destroy(): void {
    this.keyTarget.removeEventListener('keydown', this.handleShortcut, { capture: true });
    super.destroy();
  }

  /** Esc opens the menu only when nothing else consumed it (the modal stack closes open windows first). */
  private readonly handleShortcut = (event: KeyboardEvent): void => {
    if (event.key !== 'Escape' || event.repeat || event.defaultPrevented || this.isOpen()) return;
    if (this.options.modalStack.hasActiveSurface() || !this.options.actions.canOpen()) return;
    if (event.target instanceof HTMLElement && event.target.closest('input, textarea, select, [contenteditable]')) return;
    this.open();
    event.preventDefault();
    event.stopPropagation();
  };
}
