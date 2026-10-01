import { getQuestDefinition, RETIRED_QUEST_IDS } from '../../../content/quests/QuestCatalog';
import type { QuestDefinition, QuestState } from '../../../content/quests/types';
import { validateQuestState } from '../../../content/quests/validateQuestCatalog';
import { questReconciliationRegistry } from './QuestReconciliationRegistry';

export interface QuestStateRepair {
  readonly states: readonly QuestState[];
  /** One line per quest whose saved state had to change ("quest 'x': restarted its stage"). */
  readonly repairs: readonly string[];
}

/**
 * Fits saved quest states to the current quest catalog so a save from an older
 * build still loads (playtest 2026-10-01: one stale objective id made the whole
 * load fail and left a blank screen). A quest keeps what still fits: progress on
 * objectives that still exist (within their targets), its stage if the stage
 * still exists, and a completed quest stays completed. What cannot be kept
 * restarts that quest only; states that already fit are returned unchanged.
 */
export function repairQuestStates(states: readonly QuestState[]): QuestStateRepair {
  const repaired: QuestState[] = [];
  const repairs: string[] = [];
  for (const state of states) {
    const definition = getQuestDefinition(state.questId);
    if (!definition) {
      if (!RETIRED_QUEST_IDS.has(state.questId)) repairs.push(`quest '${state.questId}': no longer exists, dropped`);
      else repaired.push(state);
      continue;
    }
    const result = repairQuestState(state, definition);
    repaired.push(result.state);
    if (result.repair) repairs.push(`quest '${state.questId}': ${result.repair}`);
  }
  return { states: repaired, repairs };
}

function repairQuestState(state: QuestState, definition: QuestDefinition): { state: QuestState; repair?: string } {
  let reconciled: QuestState;
  let adopted = false;
  try {
    reconciled = questReconciliationRegistry.reconcile(state, definition);
  } catch {
    reconciled = { ...state, definitionVersion: definition.definitionVersion };
    adopted = true;
  }
  if (validateQuestState(reconciled, definition).length === 0) {
    return adopted ? { state: reconciled, repair: `moved to definition version ${definition.definitionVersion}` } : { state: reconciled };
  }

  const objectives = new Map(definition.stages.flatMap((stage) => stage.objectives).map((objective) => [objective.id, objective.target]));
  const stageIds = new Set(definition.stages.map((stage) => stage.id));
  const progress = Object.fromEntries(Object.entries(reconciled.progress).flatMap(([id, value]) => {
    const target = objectives.get(id);
    return target === undefined || !Number.isInteger(value) || value < 0 ? [] : [[id, Math.min(value, target)]];
  }));
  const consumedFactIds = Object.fromEntries(Object.entries(reconciled.consumedFactIds ?? {})
    .filter(([id, facts]) => objectives.has(id) && Array.isArray(facts) && facts.every((fact) => typeof fact === 'string')));
  const active = reconciled.status === 'active';
  const stageKept = !!reconciled.activeStageId && stageIds.has(reconciled.activeStageId);
  const { resumeStageId, ...rest } = reconciled;
  const keepResume = (reconciled.status === 'failed' || reconciled.status === 'abandoned') && !!resumeStageId && stageIds.has(resumeStageId);
  const fitted: QuestState = {
    ...rest,
    activeStageId: active ? (stageKept ? reconciled.activeStageId : definition.stages[0]!.id) : null,
    progress: active && !stageKept ? {} : progress,
    consumedFactIds: active && !stageKept ? {} : consumedFactIds,
    rewardsGranted: reconciled.status === 'completed',
    ...(keepResume ? { resumeStageId } : {}),
  };
  if (validateQuestState(fitted, definition).length === 0) {
    return { state: fitted, repair: active && !stageKept ? 'restarted its first stage' : 'dropped progress that no longer fits' };
  }
  // Nothing else fits: a finished quest stays finished, anything else starts over.
  const completed = reconciled.status === 'completed';
  return {
    state: {
      questId: definition.id,
      definitionVersion: definition.definitionVersion,
      status: completed ? 'completed' : 'locked',
      activeStageId: null,
      progress: {},
      consumedFactIds: {},
      rewardsGranted: completed,
    },
    repair: completed ? 'kept as completed' : 'started over',
  };
}
