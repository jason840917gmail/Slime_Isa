import { isKnownItemId } from '../items/ItemCatalog';
import {
  getObjectArchetype,
  hasObjectVisual,
  isObjectArchetypeId,
  type ObjectArchetypeId,
} from './ObjectCatalog';

export const COLLECTIBLE_INITIAL_STATE_KEYS = ['quantity', 'remaining'] as const;
export const RESOURCE_INITIAL_STATE_KEYS = ['health', 'dropObjectId', 'dropVisualId', 'dropPieces'] as const;

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function gameplayInitialStateKeys(objectId: ObjectArchetypeId): readonly string[] {
  const definition = getObjectArchetype(objectId);
  if (definition.collectible) return COLLECTIBLE_INITIAL_STATE_KEYS;
  if (definition.resourceNode) return RESOURCE_INITIAL_STATE_KEYS;
  if (definition.destructible) return ['health'];
  return [];
}

export function validateObjectInitialState(objectId: string, value: unknown): readonly string[] {
  if (value === undefined) return [];
  if (!isRecord(value)) return ['initialState must be an object'];
  if (!isObjectArchetypeId(objectId)) return [`unknown object '${objectId}'`];

  const definition = getObjectArchetype(objectId);
  const allowed = new Set(gameplayInitialStateKeys(objectId));
  const issues = Object.keys(value)
    .filter((key) => !allowed.has(key))
    .map((key) => `initialState.${key} is not supported by '${objectId}'`);

  if (definition.collectible) {
    if (!isKnownItemId(definition.collectible.itemId)) {
      issues.push(`collectible item '${definition.collectible.itemId}' is unknown`);
    }
    const quantity = value.quantity ?? definition.collectible.quantity;
    if (!Number.isInteger(quantity) || (quantity as number) < 1) {
      issues.push('initialState.quantity must be an integer of at least 1');
    }
    if (value.remaining !== undefined && (!Number.isInteger(value.remaining)
      || (value.remaining as number) < 0
      || (Number.isInteger(quantity) && (value.remaining as number) > (quantity as number)))) {
      issues.push('initialState.remaining must be an integer from 0 through the starting quantity');
    }
    return issues;
  }

  if (definition.resourceNode) {
    if (value.health !== undefined && (!Number.isInteger(value.health)
      || (value.health as number) < 0
      || (value.health as number) > definition.resourceNode.health)) {
      issues.push(`initialState.health must be an integer from 0 through ${definition.resourceNode.health}`);
    }
    const dropObjectId = typeof value.dropObjectId === 'string'
      ? value.dropObjectId
      : definition.resourceNode.drop.objectId;
    if (!isObjectArchetypeId(dropObjectId) || !getObjectArchetype(dropObjectId).collectible) {
      issues.push('initialState.dropObjectId must reference a collectible archetype');
    }
    const dropVisualId = typeof value.dropVisualId === 'string'
      ? value.dropVisualId
      : typeof value.dropObjectId === 'string' && isObjectArchetypeId(dropObjectId)
        ? getObjectArchetype(dropObjectId).variants[0]?.frames[0]?.visualId ?? ''
        : definition.resourceNode.drop.visualId;
    if (isObjectArchetypeId(dropObjectId) && !hasObjectVisual(dropObjectId, dropVisualId)) {
      issues.push(`initialState.dropVisualId '${dropVisualId}' does not belong to '${dropObjectId}'`);
    }
    if (value.dropPieces !== undefined && (!Number.isInteger(value.dropPieces) || (value.dropPieces as number) < 1)) {
      issues.push('initialState.dropPieces must be an integer of at least 1');
    }
    return issues;
  }

  if (definition.destructible) {
    if (value.health !== undefined && (!Number.isInteger(value.health)
      || (value.health as number) < 0
      || (value.health as number) > definition.destructible.health)) {
      issues.push(`initialState.health must be an integer from 0 through ${definition.destructible.health}`);
    }
    return issues;
  }

  if (Object.keys(value).length > 0) issues.push(`'${objectId}' does not support gameplay initial state`);
  return issues;
}
