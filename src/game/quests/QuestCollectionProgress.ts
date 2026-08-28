import type { CollectibleCollectedPayload } from '../core/EventBus';
import type { QuestObjectiveDef } from './Quest';

/** Returns the transferred item quantity that should advance one objective. */
export function collectibleProgressAmount(
  objective: QuestObjectiveDef,
  payload: CollectibleCollectedPayload,
): number {
  if (objective.kind !== 'collect' || !objective.itemIds.includes(payload.itemId)) return 0;
  return Number.isInteger(payload.quantity) && payload.quantity > 0 ? payload.quantity : 0;
}
