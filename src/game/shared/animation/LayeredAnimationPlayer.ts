import { AnimationClock, type AnimationClockFrameState } from './clock';
import { resolveLayeredAnimationFrame } from './layered';
import type {
  AnimationPlaybackContext,
  NormalizedLayeredAnimationDocument,
  ResolvedAnimationVisualLayer,
} from './types';

export interface LayeredAnimationPlaybackState extends AnimationClockFrameState {
  readonly layers: readonly ResolvedAnimationVisualLayer[];
}

export type LayeredAnimationFrameCallback = (
  state: LayeredAnimationPlaybackState,
  context: AnimationPlaybackContext,
) => void;

/** Resolves layered visual state from an externally owned shared clock. */
export class LayeredAnimationPlayer {
  private animation: NormalizedLayeredAnimationDocument;
  private currentLayers: readonly ResolvedAnimationVisualLayer[] = [];
  private readonly unsubscribe: () => void;
  private destroyed = false;

  constructor(
    clock: AnimationClock,
    animation: NormalizedLayeredAnimationDocument,
    private readonly onFrame: LayeredAnimationFrameCallback,
  ) {
    this.animation = animation;
    this.unsubscribe = clock.subscribeFrame('visual', (state, context) => {
      if (this.destroyed) return;
      this.currentLayers = resolveLayeredAnimationFrame(this.animation, state.timelineFrame);
      this.onFrame({ ...state, layers: this.currentLayers }, context);
    });
  }

  get layers(): readonly ResolvedAnimationVisualLayer[] {
    return this.currentLayers;
  }

  setAnimation(animation: NormalizedLayeredAnimationDocument): void {
    this.animation = animation;
    this.currentLayers = [];
  }

  resolve(timelineFrame: number): readonly ResolvedAnimationVisualLayer[] {
    this.currentLayers = resolveLayeredAnimationFrame(this.animation, timelineFrame);
    return this.currentLayers;
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.unsubscribe();
    this.currentLayers = [];
  }
}
