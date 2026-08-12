import type { ResolvedAnimationVisualLayer } from './types';

export interface LayeredAnimationHostTransform {
  readonly x: number;
  readonly y: number;
  readonly baseDepth: number;
  readonly rotationRad: number;
  readonly mirrorX: boolean;
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
  const [layerOffsetX, layerOffsetY] = layer.layerTransform.offset;
  const [blockOffsetX, blockOffsetY] = layer.blockTransform.offset;
  const authoredOffsetX = layerOffsetX + blockOffsetX;
  const localOffsetX = host.mirrorX ? -authoredOffsetX : authoredOffsetX;
  const localOffsetY = layerOffsetY + blockOffsetY;
  const cos = Math.cos(host.rotationRad);
  const sin = Math.sin(host.rotationRad);
  const rotatedOffsetX = localOffsetX * cos - localOffsetY * sin;
  const rotatedOffsetY = localOffsetX * sin + localOffsetY * cos;
  const localRotationDeg = layer.layerTransform.rotationDeg + layer.blockTransform.rotationDeg;
  const mirroredLocalRotationDeg = host.mirrorX ? -localRotationDeg : localRotationDeg;

  return {
    x: host.x + rotatedOffsetX,
    y: host.y + rotatedOffsetY,
    depth: host.baseDepth + layer.relativeDepth,
    originX: layer.layerTransform.origin[0],
    originY: layer.layerTransform.origin[1],
    scaleX: layer.layerTransform.scale[0] * layer.blockTransform.scale[0],
    scaleY: layer.layerTransform.scale[1] * layer.blockTransform.scale[1],
    rotationRad: host.rotationRad + mirroredLocalRotationDeg * Math.PI / 180,
    flipX: exclusiveOr(host.mirrorX, layer.layerTransform.flipX, layer.blockTransform.flipX),
    flipY: exclusiveOr(layer.layerTransform.flipY, layer.blockTransform.flipY),
  };
}
