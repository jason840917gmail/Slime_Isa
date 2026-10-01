import type { UiPresentationModel } from '../scripts/ui/UiSurfaceScript';
import { MenuSurface, type MenuSurfaceOptions } from './MenuSurface';
import { formatPlayTime } from './SaveSlotsSurfacePort';

export interface DefeatInfo {
  /** What defeated the slime, when known ("Worm Brawler"). */
  readonly cause?: string;
  readonly playTimeMs: number;
  /** True when a bed is set as the respawn point. */
  readonly hasBed: boolean;
}

export interface GameOverActions {
  wake(): void;
  openLoad(): void;
  /** True when the Load window has something to show (the autosave or a save slot). */
  hasLoadable(): boolean;
}

export interface GameOverSurfaceOptions extends MenuSurfaceOptions {
  readonly actions: GameOverActions;
}

export const GAME_OVER_SURFACE_ID = 'game-over';

/**
 * Shown after a defeat: what defeated the slime and the time played, then
 * "Wake at your bed" (or in Slimeshire without one) or "Load a save". Escape
 * never skips it, so a defeat always resolves through one of its buttons.
 */
export class GameOverSurfacePort extends MenuSurface {
  private info: DefeatInfo = { playTimeMs: 0, hasBed: false };
  private waking = false;

  constructor(private readonly options: GameOverSurfaceOptions) {
    super(GAME_OVER_SURFACE_ID, { ...options, closableByEscape: false });
  }

  show(info: DefeatInfo): void {
    this.info = info;
    this.waking = false;
    if (this.isOpen()) this.publish();
    else this.open();
  }

  protected model(): UiPresentationModel {
    return {
      cause: this.info.cause ? `Defeated by ${this.info.cause}` : 'You were defeated',
      playTime: formatPlayTime(this.info.playTimeMs),
      wakeLabel: this.info.hasBed ? 'Wake at your bed' : 'Wake in Slimeshire',
      wakeDisabled: this.waking,
      loadDisabled: this.waking || !this.options.actions.hasLoadable(),
    };
  }

  protected act(actionId: string): void {
    if (this.waking) return;
    if (actionId === 'wake') {
      this.waking = true;
      this.close();
      this.options.actions.wake();
    } else if (actionId === 'load') {
      this.options.actions.openLoad();
    }
  }
}
