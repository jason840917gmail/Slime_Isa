/** Extra screen-space correction for attacks inherited from DOWN by UP. */
export const MIRRORED_UP_Y_OFFSET_PX = 20;

export function resolveWeaponPresentationOffsetY(mirrorY: boolean): number {
  return mirrorY ? MIRRORED_UP_Y_OFFSET_PX : 0;
}
