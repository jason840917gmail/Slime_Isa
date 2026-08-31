import type {
  CollectObjective,
  CraftItemObjective,
  DefeatBossObjective,
  DiscoverAreaObjective,
  EscortCharacterObjective,
  KillObjective,
  QuestInputEventName,
  QuestInputEvents,
  QuestObjectiveDefinition,
  QuestObjectiveKind,
  ActivateObjectObjective,
  SurviveDurationObjective,
  TalkToNpcObjective,
} from '../../content/quests/types';

export type ObjectiveMatchResult =
  | { readonly matched: false }
  | { readonly matched: true; readonly amount: number; readonly factId?: string };

export interface ObjectiveMatchContext {
  readonly isFactConsumed: (objectiveId: string, factId: string) => boolean;
}

export interface ObjectiveMatcher {
  readonly kind: QuestObjectiveKind;
  readonly event: QuestInputEventName;
  readonly match: (
    objective: QuestObjectiveDefinition,
    payload: unknown,
    context: ObjectiveMatchContext,
  ) => ObjectiveMatchResult;
}

function matched(amount = 1, factId?: string): ObjectiveMatchResult {
  return factId ? { matched: true, amount, factId } : { matched: true, amount };
}

function valuesInclude(values: readonly string[] | undefined, value: string): boolean {
  return values === undefined || values.includes(value);
}

function tagsIncludeAll(values: readonly string[] | undefined, tags: readonly string[] | undefined): boolean {
  return values === undefined || (tags !== undefined && values.every((tag) => tags.includes(tag)));
}

function collectMatch(objective: CollectObjective, payload: QuestInputEvents['collectible.collected']): ObjectiveMatchResult {
  return objective.itemIds.includes(payload.itemId) && Number.isInteger(payload.quantity) && payload.quantity > 0
    ? matched(payload.quantity)
    : { matched: false };
}

function killMatch(objective: KillObjective, payload: QuestInputEvents['enemy.died']): ObjectiveMatchResult {
  return valuesInclude(objective.enemyKinds, payload.kind)
    && valuesInclude(objective.areaIds, payload.areaId)
    && tagsIncludeAll(objective.enemyTags, payload.tags)
    ? matched()
    : { matched: false };
}

function talkMatch(objective: TalkToNpcObjective, payload: QuestInputEvents['npc.talked']): ObjectiveMatchResult {
  return objective.npcIds.includes(payload.npcId) ? matched() : { matched: false };
}

function craftMatch(objective: CraftItemObjective, payload: QuestInputEvents['craft.completed']): ObjectiveMatchResult {
  return objective.itemIds.includes(payload.itemId)
    && valuesInclude(objective.recipeIds, payload.recipeId)
    && Number.isInteger(payload.quantity)
    && payload.quantity > 0
    ? matched(payload.quantity)
    : { matched: false };
}

function escortMatch(objective: EscortCharacterObjective, payload: QuestInputEvents['escort.completed']): ObjectiveMatchResult {
  const escortMatches = objective.escortIds === undefined || objective.escortIds.includes(payload.escortId);
  const characterMatches = objective.characterIds === undefined || objective.characterIds.includes(payload.characterId);
  const destinationMatches = valuesInclude(objective.destinationIds, payload.destinationId ?? '');
  if (!escortMatches || !characterMatches || !destinationMatches) return { matched: false };
  return matched(1, payload.runId ?? payload.escortId);
}

function bossMatch(objective: DefeatBossObjective, payload: QuestInputEvents['boss.defeated']): ObjectiveMatchResult {
  return objective.bossIds.includes(payload.bossId) ? matched(1, payload.factId ?? payload.bossId) : { matched: false };
}

function objectMatch(objective: ActivateObjectObjective, payload: QuestInputEvents['object.activated']): ObjectiveMatchResult {
  const objectMatches = objective.objectIds === undefined || objective.objectIds.includes(payload.objectId);
  const instanceMatches = objective.instanceIds === undefined || objective.instanceIds.includes(payload.instanceId);
  const areaMatches = valuesInclude(objective.areaIds, payload.areaId);
  return objectMatches && instanceMatches && areaMatches
    ? matched(1, payload.instanceId)
    : { matched: false };
}

function survivalMatch(objective: SurviveDurationObjective, payload: QuestInputEvents['survival.completed']): ObjectiveMatchResult {
  return objective.encounterIds.includes(payload.encounterId)
    && Number.isFinite(payload.durationMs)
    && payload.durationMs >= objective.requiredDurationMs
    ? matched(1, payload.factId ?? payload.encounterId)
    : { matched: false };
}

function areaMatch(objective: DiscoverAreaObjective, payload: QuestInputEvents['area.enter']): ObjectiveMatchResult {
  return objective.areaIds.includes(payload.areaId) ? matched(1, payload.areaId) : { matched: false };
}

export const OBJECTIVE_MATCHERS: readonly ObjectiveMatcher[] = [
  { kind: 'collect', event: 'collectible.collected', match: (objective, payload) => collectMatch(objective as CollectObjective, payload as QuestInputEvents['collectible.collected']) },
  { kind: 'kill', event: 'enemy.died', match: (objective, payload) => killMatch(objective as KillObjective, payload as QuestInputEvents['enemy.died']) },
  { kind: 'talk-to-npc', event: 'npc.talked', match: (objective, payload) => talkMatch(objective as TalkToNpcObjective, payload as QuestInputEvents['npc.talked']) },
  { kind: 'craft-item', event: 'craft.completed', match: (objective, payload) => craftMatch(objective as CraftItemObjective, payload as QuestInputEvents['craft.completed']) },
  { kind: 'escort-character', event: 'escort.completed', match: (objective, payload) => escortMatch(objective as EscortCharacterObjective, payload as QuestInputEvents['escort.completed']) },
  { kind: 'defeat-boss', event: 'boss.defeated', match: (objective, payload) => bossMatch(objective as DefeatBossObjective, payload as QuestInputEvents['boss.defeated']) },
  { kind: 'activate-object', event: 'object.activated', match: (objective, payload) => objectMatch(objective as ActivateObjectObjective, payload as QuestInputEvents['object.activated']) },
  { kind: 'survive-duration', event: 'survival.completed', match: (objective, payload) => survivalMatch(objective as SurviveDurationObjective, payload as QuestInputEvents['survival.completed']) },
  { kind: 'discover-area', event: 'area.enter', match: (objective, payload) => areaMatch(objective as DiscoverAreaObjective, payload as QuestInputEvents['area.enter']) },
];

export class QuestObjectiveRegistry {
  private readonly byKind = new Map(OBJECTIVE_MATCHERS.map((matcher) => [matcher.kind, matcher]));

  constructor() {
    const kinds = new Set<QuestObjectiveKind>([
      'collect', 'kill', 'talk-to-npc', 'craft-item', 'escort-character',
      'defeat-boss', 'activate-object', 'survive-duration', 'discover-area',
    ]);
    if (this.byKind.size !== kinds.size || [...kinds].some((kind) => !this.byKind.has(kind))) {
      throw new Error('Quest objective matcher registry is incomplete.');
    }
  }

  resolve(objective: QuestObjectiveDefinition): ObjectiveMatcher | undefined {
    return this.byKind.get(objective.kind);
  }
}

export const questObjectiveRegistry = new QuestObjectiveRegistry();

export function matchObjective(
  objective: QuestObjectiveDefinition,
  event: QuestInputEventName,
  payload: QuestInputEvents[QuestInputEventName],
  context: ObjectiveMatchContext,
): ObjectiveMatchResult {
  const matcher = questObjectiveRegistry.resolve(objective);
  if (!matcher || matcher.event !== event) return { matched: false };
  const result = matcher.match(objective, payload, context);
  if (!result.matched || !result.factId || !context.isFactConsumed(objective.id, result.factId)) return result;
  return { matched: false };
}
