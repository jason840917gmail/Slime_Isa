import type { NormalizedAnimationClipDocument } from '../shared/animation';
import { holdLengthAtKeyframe, timelineFrameCount } from '../shared/animation';

export interface AnimationTimelineKeyframeView {
  readonly index: number;
  readonly indexLabel: string;
  readonly sourceFrame: number;
  readonly start: number;
  readonly startFrameLabel: string;
  readonly startSeconds: number;
  readonly startTimeLabel: string;
  readonly hold: number;
  readonly holdSeconds: number;
  readonly holdTimeLabel: string;
  readonly through: number;
  readonly gridColumnStart: number;
  readonly gridColumnSpan: number;
  readonly tooltip: string;
}

export interface AnimationTimelineRulerTickView {
  readonly frame: number;
  readonly gridColumn: number;
  readonly timeLabel?: string;
}

export interface AnimationTimelineViewModel {
  readonly timelineFrames: number;
  readonly framesPerSecond: number;
  readonly effectiveDurationSeconds: number;
  readonly secondsPrecision: number;
  readonly rulerLabelStride: number;
  readonly rulerTicks: readonly AnimationTimelineRulerTickView[];
  readonly keyframes: readonly AnimationTimelineKeyframeView[];
}

export interface AnimationTimelinePreviewTarget {
  readonly keyframeIndex: number;
  readonly timelineFrame: number;
  readonly sourceFrame: number;
}

export function animationTimelineSecondsPrecision(framesPerSecond: number): number {
  return framesPerSecond <= 100 ? 2 : 3;
}

export function formatAnimationTimelineSeconds(seconds: number, framesPerSecond: number): string {
  return seconds.toFixed(animationTimelineSecondsPrecision(framesPerSecond));
}

export function animationTimelineIndexLabel(index: number): string {
  return String(index).padStart(2, '0');
}

export function animationTimelineRulerLabelStride(timelineFrames: number): number {
  return Math.max(1, Math.ceil(timelineFrames / 12));
}

export function createEmptyAnimationTimelineView(framesPerSecond = 1): AnimationTimelineViewModel {
  return {
    timelineFrames: 0,
    framesPerSecond,
    effectiveDurationSeconds: 0,
    secondsPrecision: animationTimelineSecondsPrecision(framesPerSecond),
    rulerLabelStride: 1,
    rulerTicks: [],
    keyframes: [],
  };
}

/** Shared editor view model for the ruler and duration-block visual track. */
export function createAnimationTimelineView(clip: NormalizedAnimationClipDocument): AnimationTimelineViewModel {
  const totalFrames = timelineFrameCount(clip);
  const framesPerSecond = clip.framesPerSecond;
  const secondsPrecision = animationTimelineSecondsPrecision(framesPerSecond);
  const rulerLabelStride = animationTimelineRulerLabelStride(totalFrames);
  const labelledFrames = new Set<number>();
  for (let frame = 0; frame < totalFrames; frame += rulerLabelStride) labelledFrames.add(frame);
  labelledFrames.add(totalFrames - 1);
  return {
    timelineFrames: totalFrames,
    framesPerSecond,
    effectiveDurationSeconds: totalFrames / framesPerSecond,
    secondsPrecision,
    rulerLabelStride,
    rulerTicks: Array.from({ length: totalFrames }, (_, frame) => ({
      frame,
      gridColumn: frame + 1,
      timeLabel: labelledFrames.has(frame) ? `${formatAnimationTimelineSeconds(frame / framesPerSecond, framesPerSecond)}s` : undefined,
    })),
    keyframes: clip.frames.map((sourceFrame, index) => {
      const start = clip.keyframeTimes[index];
      const hold = holdLengthAtKeyframe(clip, index);
      const startSeconds = start / framesPerSecond;
      const holdSeconds = hold / framesPerSecond;
      const indexLabel = animationTimelineIndexLabel(index);
      const startTimeLabel = `${formatAnimationTimelineSeconds(startSeconds, framesPerSecond)}s`;
      const holdTimeLabel = `${formatAnimationTimelineSeconds(holdSeconds, framesPerSecond)}s`;
      return {
        index,
        indexLabel,
        sourceFrame,
        start,
        startFrameLabel: `F${animationTimelineIndexLabel(start)}`,
        startSeconds,
        startTimeLabel,
        hold,
        holdSeconds,
        holdTimeLabel,
        through: start + hold - 1,
        gridColumnStart: start + 1,
        gridColumnSpan: hold,
        tooltip: `Keyframe ${indexLabel}. Start ${formatAnimationTimelineSeconds(startSeconds, framesPerSecond)} seconds (frame ${start}). Hold ${formatAnimationTimelineSeconds(holdSeconds, framesPerSecond)} seconds (${hold} frame${hold === 1 ? '' : 's'}). Source ${sourceFrame}.`,
      };
    }),
  };
}

export function toggleTimelineSelection(selected: readonly number[], index: number): number[] {
  const next = new Set(selected);
  if (next.has(index)) next.delete(index);
  else next.add(index);
  return [...next].sort((left, right) => left - right);
}

export function previewTargetAtKeyframe(clip: NormalizedAnimationClipDocument, keyframeIndex: number): AnimationTimelinePreviewTarget | undefined {
  if (!Number.isInteger(keyframeIndex) || keyframeIndex < 0 || keyframeIndex >= clip.frames.length) return undefined;
  return {
    keyframeIndex,
    timelineFrame: clip.keyframeTimes[keyframeIndex],
    sourceFrame: clip.frames[keyframeIndex],
  };
}

export function renderTimelineHoldControls(keyframeIndex: number, holdLength: number, disabled = false): string {
  const minimum = holdLength <= 1;
  return `<span class="timeline-frame-hold-controls" aria-label="Adjust hold length"><span role="button" tabindex="0" data-action="adjust-keyframe-hold" data-keyframe-index="${keyframeIndex}" data-hold-delta="-1" aria-label="Decrease hold length" aria-disabled="${disabled || minimum}">−</span><span role="button" tabindex="0" data-action="adjust-keyframe-hold" data-keyframe-index="${keyframeIndex}" data-hold-delta="1" aria-label="Increase hold length" aria-disabled="${disabled}">+</span></span>`;
}

export function renderTimelineKeyframeTimingLabels(keyframe: AnimationTimelineKeyframeView): string {
  return `<span class="timeline-frame-number">@${keyframe.startTimeLabel}</span><span class="timeline-frame-hold">${keyframe.holdTimeLabel} / ${keyframe.hold}F</span>`;
}

export function renderTimelineResizeHandle(keyframe: AnimationTimelineKeyframeView, disabled = false): string {
  if (disabled) return '';
  const valueText = `${keyframe.hold} frame${keyframe.hold === 1 ? '' : 's'}, ${keyframe.holdTimeLabel}`;
  return `<span class="timeline-frame-resize-handle" role="separator" tabindex="0" aria-orientation="vertical" aria-label="Resize keyframe ${keyframe.indexLabel} hold. Use Left and Right arrows; Home sets one frame." aria-valuemin="1" aria-valuemax="${Number.MAX_SAFE_INTEGER}" aria-valuenow="${keyframe.hold}" aria-valuetext="${valueText}" data-timeline-resize-handle data-keyframe-index="${keyframe.index}"><i aria-hidden="true"></i></span>`;
}
