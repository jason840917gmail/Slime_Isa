import type {
  AnimationBlockTransformDocument,
  AnimationLayerTransformDocument,
  AnimationVisualLayerDocument,
  LayeredAnimationDocument,
  NormalizedAnimationBlockTransform,
  NormalizedAnimationLayerTransform,
  NormalizedAnimationVisualBlockDocument,
  NormalizedAnimationVisualLayerDocument,
  NormalizedLayeredAnimationDocument,
  ResolvedAnimationVisualLayer,
} from './types';

export const LAYER_ORDER_DEPTH_STEP = 0.001;

const DEFAULT_BLOCK_TRANSFORM: NormalizedAnimationBlockTransform = {
  offset: [0, 0],
  scale: [1, 1],
  rotationDeg: 0,
  flipX: false,
  flipY: false,
};

export function layeredTimelineFrameCount(
  animation: Pick<LayeredAnimationDocument, 'durationSeconds' | 'framesPerSecond'>,
): number {
  // Duration is authored in seconds; FPS only determines the editor/runtime sampling grid.
  const product = animation.durationSeconds * animation.framesPerSecond;
  const rounded = Math.round(product);
  if (
    !Number.isFinite(animation.durationSeconds)
    || animation.durationSeconds <= 0
    || !Number.isInteger(animation.framesPerSecond)
    || animation.framesPerSecond < 1
    || animation.framesPerSecond > 240
    || rounded < 1
  ) {
    throw new Error('Layered animation duration and FPS must resolve to at least one timeline frame');
  }
  return rounded;
}

export function normalizeAnimationBlockTransform(
  transform?: AnimationBlockTransformDocument,
): NormalizedAnimationBlockTransform {
  return {
    offset: transform?.offset ?? DEFAULT_BLOCK_TRANSFORM.offset,
    scale: transform?.scale ?? DEFAULT_BLOCK_TRANSFORM.scale,
    rotationDeg: transform?.rotationDeg ?? DEFAULT_BLOCK_TRANSFORM.rotationDeg,
    flipX: transform?.flipX ?? DEFAULT_BLOCK_TRANSFORM.flipX,
    flipY: transform?.flipY ?? DEFAULT_BLOCK_TRANSFORM.flipY,
  };
}

export function normalizeAnimationLayerTransform(
  transform?: AnimationLayerTransformDocument,
): NormalizedAnimationLayerTransform {
  return {
    ...normalizeAnimationBlockTransform(transform),
    origin: transform?.origin ?? [0.5, 0.5],
  };
}

export function normalizeLayeredAnimation(
  animation: LayeredAnimationDocument,
): NormalizedLayeredAnimationDocument {
  layeredTimelineFrameCount(animation);
  return {
    ...animation,
    loopMode: animation.loopMode ?? 'wrap',
    layers: animation.layers.map((layer): NormalizedAnimationVisualLayerDocument => ({
      ...layer,
      transform: normalizeAnimationLayerTransform(layer.transform),
      blocks: [...layer.blocks]
        .sort((left, right) => left.from - right.from || left.through - right.through)
        .map((block): NormalizedAnimationVisualBlockDocument => ({
          ...block,
          transform: normalizeAnimationBlockTransform(block.transform),
        })),
    })),
  };
}

export function activeAnimationBlockIndex(
  layer: Pick<AnimationVisualLayerDocument, 'blocks'>,
  timelineFrame: number,
): number {
  if (!Number.isInteger(timelineFrame) || timelineFrame < 0) return -1;
  return layer.blocks.findIndex((block) => block.from <= timelineFrame && timelineFrame <= block.through);
}

export function animationLayerRelativeDepth(layerIndex: number, depthOffset: number): number {
  return layerIndex * LAYER_ORDER_DEPTH_STEP + depthOffset;
}

export function resolveLayeredAnimationFrame(
  animation: NormalizedLayeredAnimationDocument,
  timelineFrame: number,
): readonly ResolvedAnimationVisualLayer[] {
  const frameCount = layeredTimelineFrameCount(animation);
  if (!Number.isInteger(timelineFrame) || timelineFrame < 0 || timelineFrame >= frameCount) return [];

  const resolved: ResolvedAnimationVisualLayer[] = [];
  animation.layers.forEach((layer, layerIndex) => {
    const blockIndex = activeAnimationBlockIndex(layer, timelineFrame);
    if (blockIndex < 0) return;
    const block = layer.blocks[blockIndex];
    resolved.push({
      layerId: layer.layerId,
      displayName: layer.displayName,
      assetId: layer.assetId,
      sourceFrame: block.sourceFrame,
      layerIndex,
      blockIndex,
      relativeDepth: animationLayerRelativeDepth(layerIndex, layer.depthOffset),
      layerTransform: layer.transform,
      blockTransform: block.transform,
    });
  });
  return resolved;
}
