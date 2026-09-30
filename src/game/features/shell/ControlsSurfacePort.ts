import type { UiPresentationModel } from '../scripts/ui/UiSurfaceScript';
import { MenuSurface, type MenuSurfaceOptions } from './MenuSurface';

/** Keyboard controls as the player sees them: key(s), then what they do. */
export const CONTROL_ROWS: readonly (readonly [string, string])[] = Object.freeze([
  ['Arrows / IJKL', 'Move'],
  ['E / Click', 'Attack'],
  ['Q', 'Roll / dodge'],
  ['Space', 'Jump'],
  ['T', 'Squash Slam'],
  ['R', 'Stretch Lash'],
  ['Y', 'Teleport'],
  ['F', 'Interact, talk, sleep'],
  ['G', 'Pick up placed furniture'],
  ['W', 'Gulp: tap to eat a Gulp material or burp a form; hold for the quick wheel'],
  ['1–6', 'Choose a hotbar weapon'],
  ['Tab', 'Inventory'],
  ['C', 'Crafting'],
  ['U', 'Quest book'],
  ['M', 'World map'],
  ['Mouse wheel', 'Zoom'],
  ['Esc', 'Pause menu, or close the open window'],
]);

export const CONTROLS_SURFACE_ID = 'controls';

/** Read-only list of every control (from Settings). */
export class ControlsSurfacePort extends MenuSurface {
  constructor(options: MenuSurfaceOptions) {
    super(CONTROLS_SURFACE_ID, options);
  }

  protected model(): UiPresentationModel {
    return {
      keys: CONTROL_ROWS.map(([key]) => key).join('\n'),
      actions: CONTROL_ROWS.map(([, action]) => action).join('\n'),
    };
  }

  protected act(): void {}
}
