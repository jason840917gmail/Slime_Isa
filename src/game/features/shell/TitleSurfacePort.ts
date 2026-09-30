import type { UiPresentationModel } from '../scripts/ui/UiSurfaceScript';
import { MenuSurface, type MenuSurfaceOptions } from './MenuSurface';

export interface TitleActions {
  /** True when there is a run to continue (the autosave or a save slot). */
  canContinue(): boolean;
  /** True when a save slot holds a run. */
  hasSlots(): boolean;
  /** True when starting over would replace an autosave. */
  hasAutosave(): boolean;
  newGame(): void;
  continueGame(): void;
  openLoad(): void;
  openSettings(): void;
  openCredits(): void;
}

export interface TitleSurfaceOptions extends MenuSurfaceOptions {
  readonly actions: TitleActions;
  readonly version: string;
}

export const TITLE_SURFACE_ID = 'title-screen';

/**
 * The first screen: New Game, Continue (the newest run), Load, Settings,
 * Credits and the version. Escape never closes it. Starting a new game over
 * an autosave asks first; save slots are never touched.
 */
export class TitleSurfacePort extends MenuSurface {
  private confirmingNewGame = false;
  private status = '';

  constructor(private readonly options: TitleSurfaceOptions) {
    super(TITLE_SURFACE_ID, { ...options, closableByEscape: false });
  }

  protected override onOpened(): void {
    this.confirmingNewGame = false;
    this.status = '';
  }

  protected model(): UiPresentationModel {
    const { actions } = this.options;
    return {
      version: `v${this.options.version}`,
      menuVisible: !this.confirmingNewGame,
      confirming: this.confirmingNewGame,
      continueDisabled: !actions.canContinue(),
      loadDisabled: !actions.hasSlots(),
      status: this.confirmingNewGame
        ? 'Start a new game? Your autosave will be replaced. Save slots are kept.'
        : this.status,
    };
  }

  protected act(actionId: string): void {
    const { actions } = this.options;
    switch (actionId) {
      case 'new-game':
        if (actions.hasAutosave()) { this.confirmingNewGame = true; this.publish(); return; }
        this.start(() => actions.newGame());
        return;
      case 'confirm-new-game': this.start(() => actions.newGame()); return;
      case 'cancel': this.confirmingNewGame = false; this.publish(); return;
      case 'continue': if (actions.canContinue()) this.start(() => actions.continueGame()); return;
      case 'load': actions.openLoad(); return;
      case 'settings': actions.openSettings(); return;
      case 'credits': actions.openCredits(); return;
      default: return;
    }
  }

  private start(begin: () => void): void {
    this.confirmingNewGame = false;
    this.status = 'Starting…';
    this.publish();
    begin();
  }
}
