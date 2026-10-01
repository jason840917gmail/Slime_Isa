import type { RuntimeNodeId } from '../../content/scenes/identifiers';
import type { JsonValue } from '../../content/scenes/types';
import type { NodeConstructionContext } from '../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../runtime/scene/scripts/ScriptNode';

/** One material a restoration costs. */
export interface RestorationCost {
  readonly itemId: string;
  readonly count: number;
}

function requiredScriptId(context: NodeConstructionContext): string {
  if (!context.scriptId) throw new Error('RestorationSiteScript requires a registered script identity.');
  return context.scriptId;
}

function stringOr(value: JsonValue | undefined, fallback: string): string {
  return typeof value === 'string' && value ? value : fallback;
}

function positiveOr(value: JsonValue | undefined, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : fallback;
}

/** `{ "wood": 60, "stone": 40 }` → the positive whole costs, in authored order. */
function costsOf(value: JsonValue | undefined): readonly RestorationCost[] {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return [];
  return Object.entries(value)
    .filter((entry): entry is [string, number] => Number.isSafeInteger(entry[1]) && Number(entry[1]) > 0)
    .map(([itemId, count]) => ({ itemId, count }));
}

/**
 * A ruined building the player rebuilds (roadmap 6.3): interacting nearby pays its
 * materials. Restoring sets `flagId`; a `game.story-variant` on the same flag then
 * swaps the ruin for the restored building, and `objectId` is reported to quests
 * (`activate-object`). With `questId` set, only a player on that quest can
 * restore it; anyone else reads `lockedMessage`. Author it inside the ruined
 * variant, so it leaves the scene with the ruin.
 */
export class RestorationSiteScript extends ScriptNode {
  readonly prompt: string;
  readonly flagId: string;
  readonly objectId: string;
  readonly questId: string;
  readonly cost: readonly RestorationCost[];
  readonly lockedMessage: string;
  readonly restoredMessage: string;
  /** Distance from the site origin within which it can be used. */
  readonly interactRadius: number;
  /** How far above the site origin the interaction key badge floats. */
  readonly badgeRise: number;

  constructor(context: NodeConstructionContext) {
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: requiredScriptId(context), exportedProperties: context.properties });
    const { prompt, flagId, objectId, questId, cost, lockedMessage, restoredMessage } = context.properties;
    this.prompt = stringOr(prompt, 'Restore');
    this.flagId = stringOr(flagId, '');
    this.objectId = stringOr(objectId, '');
    this.questId = typeof questId === 'string' ? questId : '';
    this.cost = costsOf(cost);
    this.lockedMessage = stringOr(lockedMessage, 'It is in ruins.');
    this.restoredMessage = stringOr(restoredMessage, 'Restored!');
    this.interactRadius = positiveOr(context.properties.interactRadius, 150);
    this.badgeRise = positiveOr(context.properties.badgeRise, 200);
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): RestorationSiteScript {
    return new RestorationSiteScript({
      runtimeId,
      name: this.name,
      type: 'ScriptNode',
      scriptId: this.scriptId,
      properties: this.exportedProperties,
      resources: new Map(),
    });
  }
}
