import type { CollectibleCollectedPayload } from '../../core/EventBus';
import type { CollectibleEventPublisher } from './CollectibleController';
import type {
  CollectibleCollectedHandler,
  CollectibleEventSubscription,
} from './CollectibleReactionController';

export interface CollectibleEventBusPort {
  emit(event: 'collectible.collected', payload: CollectibleCollectedPayload): unknown;
  on(event: 'collectible.collected', handler: CollectibleCollectedHandler): unknown;
  off(event: 'collectible.collected', handler: CollectibleCollectedHandler): unknown;
}

/** Adapts the global typed event bus to the collectible feature's narrow ports. */
export class CollectibleEventChannel implements CollectibleEventPublisher, CollectibleEventSubscription {
  constructor(private readonly events: CollectibleEventBusPort) {}

  publishCollected(payload: CollectibleCollectedPayload): void {
    this.events.emit('collectible.collected', payload);
  }

  subscribeCollected(handler: CollectibleCollectedHandler): () => void {
    this.events.on('collectible.collected', handler);
    return () => { this.events.off('collectible.collected', handler); };
  }
}
