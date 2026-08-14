import type { ResolvedAnimationVisualLayer } from './types';

export interface LayeredAnimationHostTransform {
  readonly x: number;
  readonly y: number;
  readonly baseDepth: number;
  readonly rotationRad: number;
  readonly mirrorX: boolean;
  readonly mirrorY: boolean;
}

export interface ComposedAnimationVisualTransform {
  readonly x: number;
  readonly y: number;
  readonly depth: number;
  readonly originX: number;
  readonly originY: number;
  readonly scaleX: number;
  readonly scaleY: number;
  readonly rotationRad: number;
  readonly flipX: boolean;
  readonly flipY: boolean;
}

function exclusiveOr(...values: readonly boolean[]): boolean {
  return values.reduce((result, value) => result !== value, false);
}

/** Exact transform composition shared by Studio preview and Phaser runtime. */
export function composeAnimationVisualTransform(
  layer: ResolvedAnimationVisualLayer,
  host: LayeredAnimationHostTransform,
): ComposedAnimationVisualTransform {
  const mirrorX = host.mirrorX === true;
  const mirrorY = host.mirrorY === true;
  const [layerOffsetX, layerOffsetY] = layer.layerTransform.offset;
  const [blockOffsetX, blockOffsetY] = layer.blockTransform.offset;
  const authoredOffsetX = layerOffsetX + blockOffsetX;
  const localOffsetX = mirrorX ? -authoredOffsetX : authoredOffsetX;
  const authoredOffsetY = layerOffsetY + blockOffsetY;
  const localOffsetY = mirrorY ? -authoredOffsetY : authoredOffsetY;
  const cos = Math.cos(host.rotationRad);
  const sin = Math.sin(host.rotationRad);
  const rotatedOffsetX = localOffsetX * cos - localOffsetY * sin;
  const rotatedOffsetY = localOffsetX * sin + localOffsetY * cos;
  const localRotationDeg = layer.layerTransform.rotationDeg + layer.blockTransform.rotationDeg;
  const mirroredLocalRotationDeg = mirrorX !== mirrorY ? -localRotationDeg : localRotationDeg;

  return {
    x: host.x + rotatedOffsetX,
    y: host.y + rotatedOffsetY,
    depth: host.baseDepth + layer.relativeDepth,
    originX: layer.layerTransform.origin[0],
    originY: layer.layerTransform.origin[1],
    scaleX: layer.layerTransform.scale[0] * layer.blockTransform.scale[0],
    scaleY: layer.layerTransform.scale[1] * layer.blockTransform.scale[1],
    rotationRad: host.rotationRad + mirroredLocalRotationDeg * Math.PI / 180,
    flipX: exclusiveOr(mirrorX, layer.layerTransform.flipX, layer.blockTransform.flipX),
    flipY: exclusiveOr(mirrorY, layer.layerTransform.flipY, layer.blockTransform.flipY),
  };
}
