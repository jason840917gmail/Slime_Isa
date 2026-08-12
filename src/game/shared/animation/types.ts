export type AnimationLoopMode = 'wrap' | 'ping-pong';

export type AnimationJsonValue =
  | null
  | boolean
  | number
  | string
  | AnimationJsonValue[]
  | { [key: string]: AnimationJsonValue };

/** Shared authored animation contract. Frame references stay local to the owning asset package. */
export interface AnimationClipDocument {
  readonly frames: readonly number[];
  readonly keyframeTimes?: readonly number[];
  readonly durationSeconds?: number;
  readonly framesPerSecond: number;
  readonly loop: boolean;
  readonly loopMode?: AnimationLoopMode;
}

export interface NormalizedAnimationClipDocument extends AnimationClipDocument {
  readonly keyframeTimes: readonly number[];
  readonly durationSeconds: number;
}

export interface AnimationEventDocument {
  readonly at: number;
  readonly eventId: string;
  readonly payload?: AnimationJsonValue;
}

export interface AnimationTrackDocument {
  readonly events?: readonly AnimationEventDocument[];
}

export interface AnimationPlaybackState {
  readonly timelineFrame: number;
  readonly keyframeIndex: number;
  readonly sourceFrame: number;
  readonly occurrenceIndex: number;
  readonly finished: boolean;
}

export interface AnimationPlaybackContext {
  readonly previousTimelineFrame: number | null;
  readonly timelineFrame: number;
  readonly direction: 1 | -1;
  readonly cycle: number;
  readonly isScrub: boolean;
}

export interface ExpandedAnimation {
  readonly sourceFrames: readonly number[];
  readonly occurrenceIndices: readonly number[];
  readonly timelineFrameCount: number;
  readonly effectiveDurationMs: number;
}

/** Occurrence-specific artwork edits inside one visual lane. */
export interface AnimationBlockTransformDocument {
  readonly offset?: readonly [number, number];
  readonly scale?: readonly [number, number];
  readonly rotationDeg?: number;
  readonly flipX?: boolean;
  readonly flipY?: boolean;
}

/** Stable placement shared by every block in a visual lane. */
export interface AnimationLayerTransformDocument extends AnimationBlockTransformDocument {
  readonly origin?: readonly [number, number];
}

/** Inclusive frame span that displays one source frame. */
export interface AnimationVisualBlockDocument {
  readonly from: number;
  readonly through: number;
  readonly sourceFrame: number;
  readonly transform?: AnimationBlockTransformDocument;
}

/** Ordered visual lane backed by its own spritesheet asset. */
export interface AnimationVisualLayerDocument {
  readonly layerId: string;
  readonly displayName: string;
  readonly assetId: string;
  readonly depthOffset: number;
  readonly transform?: AnimationLayerTransformDocument;
  readonly blocks: readonly AnimationVisualBlockDocument[];
}

/** Shared authored layered animation contract used by every domain adapter. */
export interface LayeredAnimationDocument {
  readonly version: 2;
  readonly durationSeconds: number;
  readonly framesPerSecond: number;
  readonly loop: boolean;
  readonly loopMode?: AnimationLoopMode;
  readonly layers: readonly AnimationVisualLayerDocument[];
}

export interface NormalizedAnimationBlockTransform {
  readonly offset: readonly [number, number];
  readonly scale: readonly [number, number];
  readonly rotationDeg: number;
  readonly flipX: boolean;
  readonly flipY: boolean;
}

export interface NormalizedAnimationLayerTransform extends NormalizedAnimationBlockTransform {
  readonly origin: readonly [number, number];
}

export interface NormalizedAnimationVisualBlockDocument extends AnimationVisualBlockDocument {
  readonly transform: NormalizedAnimationBlockTransform;
}

export interface NormalizedAnimationVisualLayerDocument extends AnimationVisualLayerDocument {
  readonly transform: NormalizedAnimationLayerTransform;
  readonly blocks: readonly NormalizedAnimationVisualBlockDocument[];
}

export interface NormalizedLayeredAnimationDocument extends LayeredAnimationDocument {
  readonly loopMode: AnimationLoopMode;
  readonly layers: readonly NormalizedAnimationVisualLayerDocument[];
}

export interface ResolvedAnimationVisualLayer {
  readonly layerId: string;
  readonly displayName: string;
  readonly assetId: string;
  readonly sourceFrame: number;
  readonly layerIndex: number;
  readonly blockIndex: number;
  readonly relativeDepth: number;
  readonly layerTransform: NormalizedAnimationLayerTransform;
  readonly blockTransform: NormalizedAnimationBlockTransform;
}
