import type { AnimationJsonValue, AnimationPlaybackContext } from '../../../shared/animation';

export interface UniversalAnimationEvent {
  readonly at: number;
  readonly eventId: string;
  readonly payload?: AnimationJsonValue;
  readonly gameplay?: boolean;
}

export interface AnimationEventEmission {
  readonly animation: string;
  readonly event: UniversalAnimationEvent;
  readonly context: AnimationPlaybackContext;
}
