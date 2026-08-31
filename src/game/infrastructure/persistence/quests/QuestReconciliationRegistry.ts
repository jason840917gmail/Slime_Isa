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

export const questReconciliationRegistry = new QuestReconciliationRegistry();
