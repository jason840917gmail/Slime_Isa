import type { LayeredAnimationHostTransform } from '../../shared/animation';

/** Domain adapters provide placement while shared animation owns visual composition. */
export interface LayeredAnimationHost {
  getAnimationHostTransform(): LayeredAnimationHostTransform;
}
