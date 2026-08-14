import type {
  AnimationBlockTransformDocument,
  AnimationLayerTransformDocument,
  LayeredAnimationDocument,
} from './types';

export interface DirectionalMaterializationOptions {
  readonly mirrorX: boolean;
  readonly mirrorY: boolean;
}

function hasOddMirrorParity(options: DirectionalMaterializationOptions): boolean {
  return options.mirrorX !== options.mirrorY;
}

function materializeTransform<T extends AnimationBlockTransformDocument>(
  transform: T | undefined,
  options: DirectionalMaterializationOptions,
  includeFlip: boolean,
): T | undefined {
  if (!transform && !includeFlip) return undefined;
  const next: {
    offset?: readonly [number, number];
    rotationDeg?: number;
    flipX?: boolean;
    flipY?: boolean;
  } = { ...transform };
  if (transform?.offset) {
    next.offset = [
      options.mirrorX ? -transform.offset[0] : transform.offset[0],
      options.mirrorY ? -transform.offset[1] : transform.offset[1],
    ];
  }
  if (transform?.rotationDeg !== undefined && hasOddMirrorParity(options)) {
    next.rotationDeg = -transform.rotationDeg;
  }
  if (includeFlip && options.mirrorX) next.flipX = !(transform?.flipX ?? false);
  if (includeFlip && options.mirrorY) next.flipY = !(transform?.flipY ?? false);
  return next as T;
}

/**
 * Bakes the host reflection used by an inherited direction into visual data.
 * Gameplay tracks are intentionally not part of a layered animation document.
 */
export function materializeDirectionalAnimation(
  animation: LayeredAnimationDocument,
  options: DirectionalMaterializationOptions,
): LayeredAnimationDocument {
  if (!options.mirrorX && !options.mirrorY) return structuredClone(animation);
  return {
    ...animation,
    layers: animation.layers.map((layer) => ({
      ...layer,
      transform: materializeTransform(
        layer.transform as AnimationLayerTransformDocument | undefined,
        options,
        true,
      ),
      blocks: layer.blocks.map((block) => ({
        ...block,
        transform: materializeTransform(block.transform, options, false),
      })),
    })),
  };
}
