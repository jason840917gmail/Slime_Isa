import type { CollectibleCollectedPayload } from '../../core/EventBus';
import type { Disposable, DisposeAction } from '../../shared/lifecycle/Disposable';

export type CollectibleCollectedHandler = (payload: CollectibleCollectedPayload) => void;

export interface CollectibleEventSubscription {
  subscribeCollected(handler: CollectibleCollectedHandler): DisposeAction;
}

export interface CollectibleReactionContext {
  readonly events: CollectibleEventSubscription;
  readonly awardCoins: (amount: number) => void;
  readonly playEatAnimation: () => void;
  readonly flashCoins: () => void;
}

/** Owns scene-lifetime presentation and rewards triggered by collection events. */
export class CollectibleReactionController implements Disposable {
  private unsubscribe?: DisposeAction;

  constructor(private readonly ctx: CollectibleReactionContext) {
    this.unsubscribe = ctx.events.subscribeCollected(this.onCollected);
  }

  dispose(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
  }

  private onCollected = (payload: CollectibleCollectedPayload): void => {
    if (payload.itemId !== 'purple-berry-mat') return;
    this.ctx.playEatAnimation();
    this.ctx.awardCoins(5 * payload.quantity);
    this.ctx.flashCoins();
  };
}
