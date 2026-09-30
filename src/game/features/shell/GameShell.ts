import { END_CARDS } from '../../content/story/endCards';
import type { ModalStack } from '../../ui/ModalStack';
import type { UiSurfacePort } from '../scripts/ui/UiSurfaceScript';
import type { GameSettingsService } from '../settings/GameSettingsService';
import { ControlsSurfacePort } from './ControlsSurfacePort';
import { CreditsSurfacePort } from './CreditsSurfacePort';
import { EndCardSurfacePort } from './EndCardSurfacePort';
import { GameOverSurfacePort, type DefeatInfo } from './GameOverSurfacePort';
import type { MenuSurface } from './MenuSurface';
import { PauseMenuSurfacePort, type PauseMenuActions } from './PauseMenuSurfacePort';
import { SaveSlotsSurfacePort, type SaveSlotStorage } from './SaveSlotsSurfacePort';
import { SettingsSurfacePort } from './SettingsSurfacePort';
import { TitleSurfacePort, type TitleActions } from './TitleSurfacePort';

export interface GameShellContext {
  readonly modalStack: ModalStack;
  /** Pauses the simulation for one menu (`source` is the menu's surface ID). */
  readonly setPaused: (source: string, paused: boolean) => void;
  readonly version: string;
  readonly settings: GameSettingsService;
  readonly saves: SaveSlotStorage;
  readonly placeName: (mapId: string) => string;
  readonly hasStoryFlag: (flagId: string) => boolean;
  readonly pause: Pick<PauseMenuActions, 'canOpen' | 'openJournal' | 'openInventory' | 'openMap' | 'quitToTitle'>;
  readonly title: Pick<TitleActions, 'canContinue' | 'hasAutosave' | 'newGame' | 'continueGame'>;
  /** Wakes the defeated slime (at its bed, or the start). */
  readonly wake: () => void;
}

/** Scenes that present the shell surfaces; mounted with the world's UI. */
export const GAME_SHELL_SCENE_IDS = Object.freeze([
  'ui.pause-menu',
  'ui.settings',
  'ui.controls',
  'ui.save-slots',
  'ui.title-screen',
  'ui.game-over',
  'ui.credits',
  'ui.end-card',
]);

/**
 * The game's frame around play: title screen, pause menu, settings and
 * controls, save slots, game over, credits, and end cards. Owns the menus and
 * how they lead into each other; the world supplies the actions.
 */
export class GameShell {
  readonly settings: SettingsSurfacePort;
  readonly controls: ControlsSurfacePort;
  readonly saves: SaveSlotsSurfacePort;
  readonly pause: PauseMenuSurfacePort;
  readonly title: TitleSurfacePort;
  readonly gameOver: GameOverSurfacePort;
  readonly credits: CreditsSurfacePort;
  readonly endCard: EndCardSurfacePort;
  private readonly all: readonly MenuSurface[];

  constructor(private readonly ctx: GameShellContext) {
    const pausing = (surfaceId: string) => (paused: boolean) => ctx.setPaused(surfaceId, paused);
    const { modalStack } = ctx;
    this.controls = new ControlsSurfacePort({ modalStack, onPausedChange: pausing('controls') });
    this.settings = new SettingsSurfacePort({
      modalStack, onPausedChange: pausing('settings'), settings: ctx.settings,
      openControls: () => this.controls.open(),
    });
    this.saves = new SaveSlotsSurfacePort({
      modalStack, onPausedChange: pausing('save-slots'), storage: ctx.saves, placeName: ctx.placeName,
    });
    this.pause = new PauseMenuSurfacePort({
      modalStack, onPausedChange: pausing('pause-menu'),
      actions: { ...ctx.pause, openSettings: () => this.settings.open(), openSaves: () => this.saves.openFor('save') },
    });
    this.credits = new CreditsSurfacePort({ modalStack, onPausedChange: pausing('credits') });
    this.title = new TitleSurfacePort({
      modalStack, onPausedChange: pausing('title-screen'), version: ctx.version,
      actions: {
        ...ctx.title,
        hasSlots: () => this.hasSlots(),
        openLoad: () => this.saves.openFor('load'),
        openSettings: () => this.settings.open(),
        openCredits: () => this.credits.open(),
      },
    });
    this.gameOver = new GameOverSurfacePort({
      modalStack, onPausedChange: pausing('game-over'),
      actions: { wake: ctx.wake, openLoad: () => this.saves.openFor('load'), hasSlots: () => this.hasSlots() },
    });
    this.endCard = new EndCardSurfacePort({
      modalStack, onPausedChange: pausing('end-card'), cards: END_CARDS, hasFlag: ctx.hasStoryFlag,
      returnToTitle: ctx.pause.quitToTitle,
    });
    this.all = [this.controls, this.settings, this.saves, this.pause, this.credits, this.title, this.gameOver, this.endCard];
  }

  /** `[surfaceId, port]` pairs for the UI surface service. */
  get surfaces(): readonly (readonly [string, UiSurfacePort])[] {
    return this.all.map((surface) => [surface.surfaceId, surface] as const);
  }

  /** True while any shell menu is showing (gameplay hotkeys stay quiet). */
  isAnyOpen(): boolean {
    return this.all.some((surface) => surface.isOpen());
  }

  showDefeat(info: DefeatInfo): void {
    this.gameOver.show(info);
  }

  destroy(): void {
    for (const surface of this.all) surface.destroy();
  }

  private hasSlots(): boolean {
    return this.ctx.saves.list().some((save) => /^Slot [1-3]$/.test(save.name));
  }
}
