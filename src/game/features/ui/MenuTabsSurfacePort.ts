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

/**
 * One menu (roadmap 4.10): while the bag, crafting, journal or map window is
 * open, a tab strip above it switches to the others. The windows stay the
 * surfaces they are; switching closes one and opens the next, so only one
 * shows at a time. The open tab's button is disabled.
 */
export class MenuTabsSurfacePort implements UiSurfacePort {
  private lastSignature = '';
  private lastModel: UiPresentationModel = {};
  private stopped = false;

  constructor(private readonly windows: () => Readonly<Record<MenuTab, MenuTabWindow | undefined>>) {}

  /** The open tab, if any of the four windows is open. */
  current(): MenuTab | undefined {
    const windows = this.windows();
    return MENU_TABS.find((tab) => windows[tab]?.isOpen());
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== MENU_TABS_SURFACE_ID || this.stopped) return {};
    const current = this.current();
    const signature = current ?? '';
    if (signature === this.lastSignature && this.lastModel.visible !== undefined) return this.lastModel;
    this.lastSignature = signature;
    this.lastModel = {
      visible: current !== undefined,
      ...Object.fromEntries(MENU_TABS.map((tab) => [`${tab}Disabled`, tab === current])),
    };
    return this.lastModel;
  }

  invoke(surfaceId: string, actionId: string, _payload?: JsonValue): void {
    if (this.stopped || surfaceId !== MENU_TABS_SURFACE_ID) return;
    const target = MENU_TABS.find((tab) => tab === actionId);
    const current = this.current();
    if (!target || !current || target === current) return;
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
