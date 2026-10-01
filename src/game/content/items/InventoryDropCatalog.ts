import { getObjectArchetype, hasObjectVisual, isObjectArchetypeId, type ObjectArchetypeId } from '../objects/ObjectCatalog';
import { getBaseItemDefinitions } from './ItemCatalog';

export interface InventoryDropDefinition {
  readonly objectId: ObjectArchetypeId;
  readonly visualId: string;
}

export function resolveInventoryDropDefinition(itemId: string): InventoryDropDefinition | undefined {
  const item = getBaseItemDefinitions()[itemId];
  const presentation = item?.worldDrop;
  if (!item || item.equipment || !presentation || !isObjectArchetypeId(presentation.objectId)) return undefined;
  const object = getObjectArchetype(presentation.objectId);
  if (object.behavior !== 'collectible.walk-over'
    || object.collectible?.itemId !== itemId
    || !hasObjectVisual(presentation.objectId, presentation.visualId)) return undefined;
  return { objectId: presentation.objectId, visualId: presentation.visualId };
}

/** The item a walk-over pile gives (`collectible.iron-ore-pile` → `iron-ore`), from items.json `worldDrop`. */
export function itemIdForWorldDrop(objectId: string): string | undefined {
  return Object.values(getBaseItemDefinitions()).find((item) => item.worldDrop?.objectId === objectId)?.id;
}
