import type { UiPresentationModel } from '../scripts/ui/UiSurfaceScript';
import { controlLabel, movementLabel } from '../player/ControlLabels';
import { MenuSurface, type MenuSurfaceOptions } from './MenuSurface';

/**
 * The controls as the player sees them: key(s), then what they do. Built from
 * the binding table each time it is read, so it can never disagree with it.
 */
export function controlRows(): readonly (readonly [string, string])[] {
  return [
    [movementLabel(), 'Move'],
    [controlLabel('attack'), 'Attack, or chop and mine'],
    [controlLabel('interact'), 'Talk, open, sleep, craft at a bench; hold to pick up placed furniture'],
    [controlLabel('sprint'), 'Hold to run'],
    [controlLabel('jump'), 'Jump (learned in the story)'],
    [controlLabel('dodge'), 'Dodge roll toward the pointer (learned in the story)'],
    [controlLabel('stretch-lash'), 'Stretch Lash toward the pointer'],
    [controlLabel('squash-slam'), 'Squash Slam'],
    [controlLabel('teleport'), 'Teleport to the pointer'],
    [controlLabel('eat'), 'Gulp: tap to eat at a Gulp spot or burp a form; hold for the quick wheel'],
    [controlLabel('weapon-next'), 'Switch between equipped weapons'],
    [controlLabel('menu'), 'Bag, crafting, journal and map'],
    [controlLabel('map'), 'World map'],
    [`${controlLabel('zoom-in')} / ${controlLabel('zoom-out')}`, 'Zoom in / out'],
    [controlLabel('pause'), 'Pause menu, or close the open window'],
  ];
}

export const CONTROLS_SURFACE_ID = 'controls';

/** Read-only list of every control (from Settings). */
export class ControlsSurfacePort extends MenuSurface {
  constructor(options: MenuSurfaceOptions) {
    super(CONTROLS_SURFACE_ID, options);
  }

  protected model(): UiPresentationModel {
    const rows = controlRows();
    return {
      keys: rows.map(([key]) => key).join('\n'),
      actions: rows.map(([, action]) => action).join('\n'),
    };
  }

  protected act(): void {}
}
