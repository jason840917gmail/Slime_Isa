import { layeredTimelineFrameCount, type LayeredAnimationDocument } from '../shared/animation';
import { animationTimelineRulerLabelStride, formatAnimationTimelineSeconds, type AnimationTimelineRulerTickView } from './AnimationTimelineView';

export interface LayeredAnimationBlockView {
  readonly layerId: string;
  readonly blockIndex: number;
  readonly sourceFrame: number;
  readonly from: number;
  readonly through: number;
  readonly hold: number;
  readonly gridColumnStart: number;
  readonly gridColumnSpan: number;
  readonly startTimeLabel: string;
  readonly holdTimeLabel: string;
}

export interface LayeredAnimationLaneView {
  readonly layerId: string;
  readonly displayName: string;
  readonly assetId: string;
  readonly depthOffset: number;
  readonly blocks: readonly LayeredAnimationBlockView[];
}

export interface LayeredAnimationTimelineViewModel {
  readonly timelineFrames: number;
  readonly framesPerSecond: number;
  readonly effectiveDurationSeconds: number;
  readonly rulerTicks: readonly AnimationTimelineRulerTickView[];
  readonly lanes: readonly LayeredAnimationLaneView[];
}

export function createLayeredAnimationTimelineView(animation: LayeredAnimationDocument): LayeredAnimationTimelineViewModel {
  const timelineFrames = layeredTimelineFrameCount(animation);
  const stride = animationTimelineRulerLabelStride(timelineFrames);
  const labels = new Set<number>();
  for (let frame = 0; frame < timelineFrames; frame += stride) labels.add(frame);
  labels.add(timelineFrames - 1);
  return {
    timelineFrames,
    framesPerSecond: animation.framesPerSecond,
    effectiveDurationSeconds: animation.durationSeconds,
    rulerTicks: Array.from({ length: timelineFrames }, (_, frame) => ({
      frame,
      gridColumn: frame + 1,
      timeLabel: labels.has(frame) ? `${formatAnimationTimelineSeconds(frame / animation.framesPerSecond, animation.framesPerSecond)}s` : undefined,
    })),
    lanes: animation.layers.map((layer) => ({
      layerId: layer.layerId,
      displayName: layer.displayName,
      assetId: layer.assetId,
      depthOffset: layer.depthOffset,
      blocks: layer.blocks.map((block, blockIndex) => ({
        layerId: layer.layerId,
        blockIndex,
        sourceFrame: block.sourceFrame,
        from: block.from,
        through: block.through,
        hold: block.through - block.from + 1,
        gridColumnStart: block.from + 1,
        gridColumnSpan: block.through - block.from + 1,
        startTimeLabel: `${formatAnimationTimelineSeconds(block.from / animation.framesPerSecond, animation.framesPerSecond)}s`,
        holdTimeLabel: `${formatAnimationTimelineSeconds((block.through - block.from + 1) / animation.framesPerSecond, animation.framesPerSecond)}s`,
      })),
    })),
  };
}

export function renderLayeredBlockHoldControls(layerId: string, blockIndex: number, hold: number): string {
  return `<span class="timeline-frame-hold-controls" aria-label="Adjust block duration"><button type="button" data-layer-id="${layerId}" data-block-index="${blockIndex}" data-block-hold-delta="-1" aria-label="Decrease duration" ${hold <= 1 ? 'disabled' : ''}>−</button><button type="button" data-layer-id="${layerId}" data-block-index="${blockIndex}" data-block-hold-delta="1" aria-label="Increase duration">+</button></span>`;
}

export function renderLayeredBlockResizeHandle(layerId: string, blockIndex: number, hold: number): string {
  return `<span class="timeline-frame-resize-handle" role="separator" tabindex="0" aria-orientation="vertical" aria-valuemin="1" aria-valuenow="${hold}" data-layer-resize-handle data-layer-id="${layerId}" data-block-index="${blockIndex}"><i aria-hidden="true"></i></span>`;
}
