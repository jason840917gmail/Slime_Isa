import type { JsonValue } from '../../content/scenes/types';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

export const MENU_TABS_SURFACE_ID = 'menu-tabs';

/** The four windows the menu key reaches, in tab order. */
export const MENU_TABS = ['inventory', 'crafting', 'journal', 'map'] as const;
export type MenuTab = typeof MENU_TABS[number];

export interface MenuTabWindow {
  isOpen(): boolean;
  open(): void;
  close(): void;
}

/** The first-time pointer at the tabs (saved with the run as a story flag). */
export interface MenuTabsCoach {
  isLearned(): boolean;
  learn(): void;
  /** Wall-clock milliseconds, for how long the pointer has been read. */
  now(): number;
}

export const MENU_TABS_COACH_TEXT = 'These tabs switch between your Bag, Crafting, Journal and Map. Click one!';
/** Closing the menu after reading the pointer this long also counts as learned. */
const COACH_READ_MS = 3000;

/**
 * One menu (roadmap 4.10): while the bag, crafting, journal or map window is
 * open, a tab strip above it switches to the others. The windows stay the
 * surfaces they are; switching closes one and opens the next, so only one
 * shows at a time. The open tab's button is disabled. The first time the menu
 * opens, a pointer under the strip shows what the tabs are; clicking a tab (or
 * closing the menu after reading it) puts it away for the rest of the run.
 */
export class MenuTabsSurfacePort implements UiSurfacePort {
  private lastSignature = '';
  private lastModel: UiPresentationModel = {};
  private stopped = false;
  private coachShownAt?: number;

  constructor(
    private readonly windows: () => Readonly<Record<MenuTab, MenuTabWindow | undefined>>,
    private readonly coach?: MenuTabsCoach,
  ) {}

  /** The open tab, if any of the four windows is open. */
  current(): MenuTab | undefined {
    const windows = this.windows();
    return MENU_TABS.find((tab) => windows[tab]?.isOpen());
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== MENU_TABS_SURFACE_ID || this.stopped) return {};
    const current = this.current();
    const coachVisible = current !== undefined && !!this.coach && !this.coach.isLearned();
    if (coachVisible) this.coachShownAt ??= this.coach!.now();
    else if (current === undefined && this.coachShownAt !== undefined) {
      if (this.coach && this.coach.now() - this.coachShownAt >= COACH_READ_MS) this.coach.learn();
      this.coachShownAt = undefined;
    }
    const signature = `${current ?? ''}|${coachVisible}`;
    if (signature === this.lastSignature && this.lastModel.visible !== undefined) return this.lastModel;
    this.lastSignature = signature;
    this.lastModel = {
      visible: current !== undefined,
      coachVisible,
      coachText: MENU_TABS_COACH_TEXT,
      ...Object.fromEntries(MENU_TABS.map((tab) => [`${tab}Disabled`, tab === current])),
    };
    return this.lastModel;
  }

  invoke(surfaceId: string, actionId: string, _payload?: JsonValue): void {
    if (this.stopped || surfaceId !== MENU_TABS_SURFACE_ID) return;
    const target = MENU_TABS.find((tab) => tab === actionId);
    const current = this.current();
    if (!target || !current || target === current) return;
    this.coach?.learn();
    const windows = this.windows();
    windows[current]?.close();
    windows[target]?.open();
  }

  destroy(): void {
    this.stopped = true;
    this.lastModel = {};
    this.lastSignature = '';
  }
}
