import { getNpcDefinition } from '../npcs/NpcCatalog';
import { isKnownItemId } from '../items/ItemCatalog';
import { RECIPE_CATALOG } from '../recipes/RecipeCatalog';
import type {
  QuestConditionDefinition,
  QuestDefinition,
  QuestObjectiveDefinition,
  QuestState,
  QuestStatus,
} from './types';

const ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const QUEST_STATUSES: readonly QuestStatus[] = ['locked', 'available', 'active', 'completed', 'failed', 'abandoned'];
const RECIPE_IDS = new Set(RECIPE_CATALOG.map((recipe) => recipe.id));

export class QuestCatalogValidationError extends Error {
  constructor(public readonly issues: readonly string[]) {
    super(`Invalid quest catalog:\n  - ${issues.join('\n  - ')}`);
    this.name = 'QuestCatalogValidationError';
  }
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function nonEmptyStringArray(value: unknown): value is readonly string[] {
  return Array.isArray(value) && value.length > 0 && value.every(nonEmptyString);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function validateCondition(condition: QuestConditionDefinition, path: string, issues: string[]): void {
  if (!condition || typeof condition !== 'object' || typeof condition.kind !== 'string') {
    issues.push(`${path}: expected a condition object`);
    return;
  }
  switch (condition.kind) {
    case 'quest-status':
      if (!nonEmptyString(condition.questId)) issues.push(`${path}.questId: required non-empty quest ID`);
      if (!QUEST_STATUSES.includes(condition.status)) issues.push(`${path}.status: unknown quest status`);
      break;
    case 'area-entered':
      if (!nonEmptyStringArray(condition.areaIds)) issues.push(`${path}.areaIds: expected a non-empty string array`);
      break;
    case 'player-level':
      if (!Number.isInteger(condition.minimumLevel) || condition.minimumLevel <= 0) {
        issues.push(`${path}.minimumLevel: expected a positive integer`);
      }
      break;
    case 'inventory-count':
      if (!isKnownItemId(condition.itemId)) issues.push(`${path}.itemId: unknown item '${condition.itemId}'`);
      if (!Number.isInteger(condition.minimumCount) || condition.minimumCount <= 0) {
        issues.push(`${path}.minimumCount: expected a positive integer`);
      }
      break;
    case 'world-flag':
      if (!nonEmptyString(condition.flagId)) issues.push(`${path}.flagId: required non-empty flag ID`);
      break;
    case 'npc-talked':
      if (!nonEmptyStringArray(condition.npcIds)) issues.push(`${path}.npcIds: expected a non-empty string array`);
      for (const npcId of condition.npcIds ?? []) {
        if (!getNpcDefinition(npcId)) issues.push(`${path}.npcIds: unknown NPC '${npcId}'`);
      }
      break;
    default:
      issues.push(`${path}.kind: unknown prerequisite condition`);
  }
}

function validateObjective(objective: QuestObjectiveDefinition, path: string, issues: string[]): void {
  if (!objective || typeof objective !== 'object') {
    issues.push(`${path}: expected an objective object`);
    return;
  }
  if (!nonEmptyString(objective.id) || !ID_PATTERN.test(objective.id)) issues.push(`${path}.id: invalid objective ID`);
  if (!nonEmptyString(objective.label)) issues.push(`${path}.label: required non-empty label`);
  if (!Number.isInteger(objective.target) || objective.target <= 0) issues.push(`${path}.target: expected a positive integer`);

  const validateValues = (values: unknown, field: string): void => {
    if (!nonEmptyStringArray(values)) issues.push(`${path}.${field}: expected a non-empty string array`);
  };

  switch (objective.kind) {
    case 'collect':
      validateValues(objective.itemIds, 'itemIds');
      for (const itemId of objective.itemIds ?? []) if (!isKnownItemId(itemId)) issues.push(`${path}.itemIds: unknown item '${itemId}'`);
      break;
    case 'kill':
      if (objective.enemyKinds !== undefined) validateValues(objective.enemyKinds, 'enemyKinds');
      if (objective.areaIds !== undefined) validateValues(objective.areaIds, 'areaIds');
      if (objective.enemyTags !== undefined) validateValues(objective.enemyTags, 'enemyTags');
      break;
    case 'talk-to-npc':
      validateValues(objective.npcIds, 'npcIds');
      for (const npcId of objective.npcIds ?? []) if (!getNpcDefinition(npcId)) issues.push(`${path}.npcIds: unknown NPC '${npcId}'`);
      break;
    case 'craft-item':
      validateValues(objective.itemIds, 'itemIds');
      for (const itemId of objective.itemIds ?? []) if (!isKnownItemId(itemId)) issues.push(`${path}.itemIds: unknown item '${itemId}'`);
      if (objective.recipeIds !== undefined) {
        validateValues(objective.recipeIds, 'recipeIds');
        for (const recipeId of objective.recipeIds ?? []) if (!RECIPE_IDS.has(recipeId)) issues.push(`${path}.recipeIds: unknown recipe '${recipeId}'`);
      }
      break;
    case 'escort-character':
      if (objective.escortIds === undefined && objective.characterIds === undefined) {
        issues.push(`${path}: expected escortIds or characterIds`);
      }
      if (objective.escortIds !== undefined) validateValues(objective.escortIds, 'escortIds');
      if (objective.characterIds !== undefined) validateValues(objective.characterIds, 'characterIds');
      if (objective.destinationIds !== undefined) validateValues(objective.destinationIds, 'destinationIds');
      break;
    case 'defeat-boss':
      validateValues(objective.bossIds, 'bossIds');
      break;
    case 'activate-object':
      if (objective.objectIds === undefined && objective.instanceIds === undefined) {
        issues.push(`${path}: expected objectIds or instanceIds`);
      }
      if (objective.objectIds !== undefined) validateValues(objective.objectIds, 'objectIds');
      if (objective.instanceIds !== undefined) validateValues(objective.instanceIds, 'instanceIds');
      if (objective.areaIds !== undefined) validateValues(objective.areaIds, 'areaIds');
      break;
    case 'survive-duration':
      validateValues(objective.encounterIds, 'encounterIds');
      if (!Number.isInteger(objective.requiredDurationMs) || objective.requiredDurationMs <= 0) {
        issues.push(`${path}.requiredDurationMs: expected a positive integer`);
      }
      break;
    case 'discover-area':
      validateValues(objective.areaIds, 'areaIds');
      break;
    default:
      issues.push(`${path}.kind: unknown objective kind`);
  }
}

function validateQuest(quest: QuestDefinition, index: number, ids: Set<string>, issues: string[]): void {
  const path = `quests[${index}]`;
  if (!quest || typeof quest !== 'object') {
    issues.push(`${path}: expected a quest object`);
    return;
  }
  if (!nonEmptyString(quest.id) || !ID_PATTERN.test(quest.id)) issues.push(`${path}.id: invalid quest ID`);
  else if (ids.has(quest.id)) issues.push(`${path}.id: duplicate quest ID '${quest.id}'`);
  else ids.add(quest.id);
  if (!Number.isInteger(quest.definitionVersion) || quest.definitionVersion <= 0) issues.push(`${path}.definitionVersion: expected a positive integer`);
  if (!nonEmptyString(quest.title)) issues.push(`${path}.title: required non-empty title`);
  if (!nonEmptyString(quest.description)) issues.push(`${path}.description: required non-empty description`);
  if (quest.category !== 'mandatory' && quest.category !== 'optional') issues.push(`${path}.category: expected mandatory or optional`);

  if (!Array.isArray(quest.prerequisites)) issues.push(`${path}.prerequisites: expected an array`);
  else quest.prerequisites.forEach((condition, conditionIndex) => validateCondition(condition, `${path}.prerequisites[${conditionIndex}]`, issues));

  if (!isRecord(quest.acquisition)) issues.push(`${path}.acquisition: expected an object`);
  else if (quest.acquisition.kind === 'npc') {
    if (!nonEmptyStringArray(quest.acquisition.npcIds)) issues.push(`${path}.acquisition.npcIds: expected a non-empty string array`);
    for (const npcId of quest.acquisition.npcIds ?? []) if (!getNpcDefinition(npcId)) issues.push(`${path}.acquisition.npcIds: unknown NPC '${npcId}'`);
  } else if (quest.acquisition.kind !== 'automatic') issues.push(`${path}.acquisition.kind: unknown acquisition kind`);

  if (!Array.isArray(quest.stages) || quest.stages.length === 0) {
    issues.push(`${path}.stages: expected a non-empty array`);
  } else {
    const stageIds = new Set<string>();
    const objectiveIds = new Set<string>();
    quest.stages.forEach((stage, stageIndex) => {
      const stagePath = `${path}.stages[${stageIndex}]`;
      if (!isRecord(stage)) {
        issues.push(`${stagePath}: expected a stage object`);
        return;
      }
      if (!nonEmptyString(stage.id) || !ID_PATTERN.test(stage.id)) issues.push(`${stagePath}.id: invalid stage ID`);
      else if (stageIds.has(stage.id)) issues.push(`${stagePath}.id: duplicate stage ID '${stage.id}'`);
      else stageIds.add(stage.id);
      if (!nonEmptyString(stage.title)) issues.push(`${stagePath}.title: required non-empty title`);
      if (!nonEmptyString(stage.description)) issues.push(`${stagePath}.description: required non-empty description`);
      const objectives = stage.objectives as readonly QuestObjectiveDefinition[] | undefined;
      if (!Array.isArray(objectives) || objectives.length === 0) issues.push(`${stagePath}.objectives: expected a non-empty array`);
      else objectives.forEach((objective, objectiveIndex) => {
        validateObjective(objective, `${stagePath}.objectives[${objectiveIndex}]`, issues);
        if (objectiveIds.has(objective.id)) issues.push(`${stagePath}.objectives[${objectiveIndex}].id: duplicate objective ID '${objective.id}'`);
        else objectiveIds.add(objective.id);
      });
    });
  }

  if (!isRecord(quest.completion)) issues.push(`${path}.completion: expected an object`);
  else if (quest.completion.kind === 'npc-turn-in') {
    if (!nonEmptyStringArray(quest.completion.npcIds)) issues.push(`${path}.completion.npcIds: expected a non-empty string array`);
    for (const npcId of quest.completion.npcIds ?? []) if (!getNpcDefinition(npcId)) issues.push(`${path}.completion.npcIds: unknown NPC '${npcId}'`);
  } else if (quest.completion.kind !== 'automatic') issues.push(`${path}.completion.kind: unknown completion kind`);

  if (!isRecord(quest.failurePolicy)) issues.push(`${path}.failurePolicy: expected an object`);
  if (!isRecord(quest.abandonmentPolicy)) issues.push(`${path}.abandonmentPolicy: expected an object`);
  if (quest.category === 'mandatory' && isRecord(quest.abandonmentPolicy) && quest.abandonmentPolicy.kind !== 'forbidden') {
    issues.push(`${path}.abandonmentPolicy: mandatory quests cannot be abandoned`);
  }
  if (isRecord(quest.failurePolicy) && quest.failurePolicy.kind !== 'permanent' && quest.failurePolicy.kind !== 'retryable') issues.push(`${path}.failurePolicy.kind: unknown failure policy`);
  if (isRecord(quest.failurePolicy) && quest.failurePolicy.kind === 'retryable' && quest.failurePolicy.reset !== 'quest' && quest.failurePolicy.reset !== 'current-stage') issues.push(`${path}.failurePolicy.reset: unknown reset policy`);
  if (isRecord(quest.abandonmentPolicy) && quest.abandonmentPolicy.kind !== 'forbidden' && quest.abandonmentPolicy.kind !== 'retryable') issues.push(`${path}.abandonmentPolicy.kind: unknown abandonment policy`);
  if (!isRecord(quest.rewards)) issues.push(`${path}.rewards: expected an object`);
  const rewards = isRecord(quest.rewards) ? quest.rewards : {};
  if (rewards.coins !== undefined && (typeof rewards.coins !== 'number' || !Number.isInteger(rewards.coins) || rewards.coins < 0)) issues.push(`${path}.rewards.coins: expected a non-negative integer`);
  if (rewards.xp !== undefined && (typeof rewards.xp !== 'number' || !Number.isInteger(rewards.xp) || rewards.xp < 0)) issues.push(`${path}.rewards.xp: expected a non-negative integer`);
  for (const reward of (Array.isArray(rewards.items) ? rewards.items : [])) {
    if (!isKnownItemId(reward.itemId)) issues.push(`${path}.rewards.items: unknown item '${reward.itemId}'`);
    if (!Number.isInteger(reward.count) || reward.count <= 0) issues.push(`${path}.rewards.items: counts must be positive integers`);
  }
}

function validatePrerequisiteReferences(quests: readonly QuestDefinition[], issues: string[]): void {
  const ids = new Set(quests.map((quest) => quest.id));
  const graph = new Map<string, string[]>();
  for (const quest of quests) {
    const dependencies = quest.prerequisites
      .filter((condition): condition is Extract<QuestConditionDefinition, { kind: 'quest-status' }> => condition.kind === 'quest-status')
      .map((condition) => condition.questId);
    graph.set(quest.id, dependencies);
    for (const dependency of dependencies) if (!ids.has(dependency)) issues.push(`quest '${quest.id}' prerequisite references unknown quest '${dependency}'`);
  }

  const visiting = new Set<string>();
  const visited = new Set<string>();
  const visit = (questId: string): void => {
    if (visited.has(questId) || !ids.has(questId)) return;
    if (visiting.has(questId)) {
      issues.push(`prerequisite dependency cycle includes '${questId}'`);
      return;
    }
    visiting.add(questId);
    for (const dependency of graph.get(questId) ?? []) visit(dependency);
    visiting.delete(questId);
    visited.add(questId);
  };
  for (const quest of quests) visit(quest.id);
}

export function validateQuestCatalog(quests: readonly QuestDefinition[]): void {
  const issues: string[] = [];
  if (!Array.isArray(quests)) issues.push('catalog: expected an array');
  const ids = new Set<string>();
  for (const [index, quest] of quests.entries()) validateQuest(quest, index, ids, issues);
  validatePrerequisiteReferences(quests, issues);
  if (issues.length > 0) throw new QuestCatalogValidationError(issues);
}

export function validateQuestState(state: QuestState, definition: QuestDefinition): readonly string[] {
  const issues: string[] = [];
  if (state.questId !== definition.id) issues.push(`questId: expected '${definition.id}'`);
  if (state.definitionVersion <= 0 || !Number.isInteger(state.definitionVersion)) issues.push('definitionVersion: expected a positive integer');
  if (state.definitionVersion !== definition.definitionVersion) issues.push(`definitionVersion: expected '${definition.definitionVersion}' after reconciliation`);
  if (!['locked', 'available', 'active', 'completed', 'failed', 'abandoned'].includes(state.status)) issues.push('status: unknown quest status');
  if (state.status === 'active' && !state.activeStageId) issues.push('activeStageId: required for active quests');
  if (state.status !== 'active' && state.activeStageId !== null) issues.push('activeStageId: must be null for inactive quests');
  if (state.activeStageId !== null && !definition.stages.some((stage) => stage.id === state.activeStageId)) {
    issues.push(`activeStageId: unknown stage '${state.activeStageId}'`);
  }
  if (state.resumeStageId !== undefined && !definition.stages.some((stage) => stage.id === state.resumeStageId)) {
    issues.push(`resumeStageId: unknown stage '${state.resumeStageId}'`);
  }
  if ((state.status !== 'failed' && state.status !== 'abandoned') && state.resumeStageId !== undefined) {
    issues.push('resumeStageId: only allowed for failed or abandoned quests');
  }
  if (state.rewardsGranted !== (state.status === 'completed')) {
    issues.push(`rewardsGranted: must be ${state.status === 'completed' ? 'true' : 'false'} for status '${state.status}'`);
  }
  for (const [objectiveId, value] of Object.entries(state.progress)) {
    if (!Number.isInteger(value) || value < 0) issues.push(`progress.${objectiveId}: expected a non-negative integer`);
    const objective = definition.stages.flatMap((stage) => stage.objectives).find((entry) => entry.id === objectiveId);
    if (!objective) issues.push(`progress.${objectiveId}: unknown objective`);
    else if (value > objective.target) issues.push(`progress.${objectiveId}: exceeds target ${objective.target}`);
  }
  for (const [objectiveId, facts] of Object.entries(state.consumedFactIds ?? {})) {
    if (!definition.stages.flatMap((stage) => stage.objectives).some((entry) => entry.id === objectiveId)) {
      issues.push(`consumedFactIds.${objectiveId}: unknown objective`);
    }
    if (!Array.isArray(facts) || facts.some((fact) => typeof fact !== 'string')) issues.push(`consumedFactIds.${objectiveId}: expected string array`);
  }
  return issues;
}
