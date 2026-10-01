import type { QuestDefinition, QuestState } from '../../../content/quests/types';

export type QuestStateReconciler = (state: QuestState, definition: QuestDefinition) => QuestState;

/** Explicit per-quest definition-version reconciliation hooks. */
export class QuestReconciliationRegistry {
  private readonly entries = new Map<string, QuestStateReconciler>();

  register(questId: string, fromVersion: number, toVersion: number, reconciler: QuestStateReconciler): void {
    this.entries.set(`${questId}:${fromVersion}->${toVersion}`, reconciler);
  }

  reconcile(state: QuestState, definition: QuestDefinition): QuestState {
    if (state.definitionVersion === definition.definitionVersion) return state;
    if (state.definitionVersion > definition.definitionVersion) {
      throw new Error(`Quest '${definition.id}' requires a newer definition version.`);
    }
    let current = state;
    for (let version = state.definitionVersion; version < definition.definitionVersion; version += 1) {
      const reconciler = this.entries.get(`${definition.id}:${version}->${version + 1}`);
      if (!reconciler) throw new Error(`Quest '${definition.id}' has no reconciliation from definition version ${version}.`);
      current = reconciler(current, definition);
    }
    return current;
  }
}

/** Keeps saved progress within the (possibly lowered) targets of a newer definition. */
export function clampProgressToTargets(state: QuestState, definition: QuestDefinition): QuestState {
  const targets = new Map(definition.stages.flatMap((stage) => stage.objectives).map((objective) => [objective.id, objective.target]));
  const progress = Object.fromEntries(Object.entries(state.progress).map(([id, value]) => [id, Math.min(value, targets.get(id) ?? value)]));
  return { ...state, definitionVersion: definition.definitionVersion, progress };
}

export const questReconciliationRegistry = new QuestReconciliationRegistry();

// Worm Trouble v2: five worm brawlers became three worm swordsmen.
questReconciliationRegistry.register('worm-trouble', 1, 2, clampProgressToTargets);

// Beyond the Verdant Gate v2: five weavers and three fangs (the fangs moved here from A Harder Pick).
questReconciliationRegistry.register('beyond-the-verdant-gate', 1, 2, clampProgressToTargets);

// A Harder Pick v2: no fang step any more; a run gathering fangs moves on to the pickaxe.
questReconciliationRegistry.register('a-harder-pick', 1, 2, (state, definition) => {
  const { 'collect-fangs': _fangs, ...progress } = state.progress;
  const { 'collect-fangs': _facts, ...consumedFactIds } = state.consumedFactIds ?? {};
  const moved = (stageId: string | null | undefined) => (stageId === 'gather-fangs' ? 'craft-pickaxe' : stageId);
  return {
    ...state,
    definitionVersion: definition.definitionVersion,
    activeStageId: moved(state.activeStageId) ?? null,
    progress,
    consumedFactIds,
    ...(state.resumeStageId ? { resumeStageId: moved(state.resumeStageId)! } : {}),
  };
});
