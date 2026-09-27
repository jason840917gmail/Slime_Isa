import { loadTypescriptModule } from '../../tests/helpers/load-typescript.mjs';

let sampling;

/**
 * Loads the shared animation/weapon/effect normalizers for converters and
 * parity tests. Weapons and effects embed their animations, so no shared
 * animation package catalog is needed.
 */
export async function loadAnimationSampling() {
  sampling ??= loadTypescriptModule('src/game/content/scenes/conversion/animationSampling.ts');
  return sampling;
}
