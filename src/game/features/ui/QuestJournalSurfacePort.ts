import type { JsonValue } from '../../content/scenes/types';
import type { QuestView } from '../../content/quests/types';
import { getNpcDefinition } from '../../content/npcs/NpcCatalog';
import { gameEvents } from '../../core/EventBus';
import { questService, type QuestCommandResult } from '../../quests/QuestService';
import type { ModalHandle, ModalStack } from '../../ui/ModalStack';
import { questRewardSummary } from '../quests/QuestRewardText';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';
import { objectiveLabel } from './QuestTrackerSurfacePort';

export interface QuestJournalSurfaceOptions {
  readonly modalStack: ModalStack;
  readonly uiRoot: HTMLElement;
  readonly onPausedChange: (paused: boolean) => void;
  readonly confirmAbandon?: (title: string) => boolean;
}

/** Readable quest state and journal commands for the authored modal. */
export class QuestJournalSurfacePort implements UiSurfacePort {
  private readonly modalHandle: ModalHandle;
  private readonly listeners = new Set<(model: UiPresentationModel) => void>();
  private readonly resizeObserver: ResizeObserver;
  private selectedQuestId?: string;
  private status = '';
  private openValue = false;
  private stopped = false;

  constructor(private readonly options: QuestJournalSurfaceOptions) {
    this.modalHandle = options.modalStack.register('quest-journal', {
      isOpen: () => this.isOpen(), close: () => this.close(),
    });
    gameEvents.on('quest.changed', this.publish, this);
    gameEvents.on('quest.completed', this.publish, this);
    this.resizeObserver = new ResizeObserver(this.publish);
    this.resizeObserver.observe(options.uiRoot);
  }

  isOpen(): boolean { return this.openValue; }
  toggle(): void { if (this.openValue) this.close(); else this.open(); }
  open(): void {
    if (this.openValue || this.stopped) return;
    this.openValue = true;
    this.status = '';
    // Each time the book opens it shows the first quest listed: the main story's.
    this.selectedQuestId = undefined;
    this.options.onPausedChange(true);
    this.modalHandle.open();
    this.publish();
  }
  close(): void {
    if (!this.openValue) { this.modalHandle.close(); return; }
    this.openValue = false;
    this.modalHandle.close();
    this.options.onPausedChange(false);
    this.status = '';
    this.publish();
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== 'quest-journal' || this.stopped) return {};
    const quests = listedQuests();
    const selected = quests.find((quest) => quest.questId === this.selectedQuestId) ?? quests[0];
    this.selectedQuestId = selected?.questId;
    const action = selected ? actionFor(selected) : undefined;
    const width = Math.min(940, Math.max(1, this.options.uiRoot.clientWidth - 32));
    const height = Math.min(620, Math.max(1, this.options.uiRoot.clientHeight - 32));
    return {
      open: this.openValue,
      offsetMin: [-Math.round(width / 2), -Math.round(height / 2)],
      offsetMax: [Math.round(width / 2), Math.round(height / 2)],
      quests: quests.map((quest) => ({
        id: quest.questId,
        label: `${questMarker(quest)} ${quest.definition.title}\n${questState(quest)}`,
        // Finished quests stay readable but step back visually.
        ...(isFinished(quest) ? { metadata: { locked: true } } : {}),
      })),
      selectedIndex: selected ? quests.indexOf(selected) : -1,
      details: selected ? detailsFor(selected) : 'No quests yet.',
      status: this.status,
      actionLabel: action === 'abandon' ? 'Abandon' : action === 'retry' ? 'Retry' : 'No action',
      actionDisabled: !action,
    };
  }

  subscribe(surfaceId: string, listener: (model: UiPresentationModel) => void): () => void {
    if (surfaceId !== 'quest-journal' || this.stopped) return () => undefined;
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  invoke(surfaceId: string, actionId: string, payload?: JsonValue): void {
    if (surfaceId !== 'quest-journal' || this.stopped) return;
    if (actionId === 'close') { this.close(); return; }
    if (!this.openValue) return;
    if (actionId === 'select-quest') {
      const index = selectionIndex(payload);
      const quest = index === undefined ? undefined : listedQuests()[index];
      if (!quest) return;
      this.selectedQuestId = quest.questId;
      this.status = '';
      this.publish();
      return;
    }
    if (actionId !== 'quest-action') return;
    const quest = listedQuests().find((entry) => entry.questId === this.selectedQuestId);
    if (!quest) return;
    const action = actionFor(quest);
    let result: QuestCommandResult | undefined;
    if (action === 'abandon') {
      const confirmed = this.options.confirmAbandon?.(quest.definition.title)
        ?? window.confirm(`Abandon "${quest.definition.title}"? You can retry it later.`);
      if (!confirmed) return;
      result = questService.abandon(quest.questId);
    } else if (action === 'retry') {
      result = quest.status === 'failed' ? questService.retryFailed(quest.questId)
        : questService.retryAbandonedAutomatic(quest.questId);
    }
    if (!result) return;
    this.status = result.ok ? action === 'abandon' ? 'Quest abandoned.' : 'Quest restarted.' : result.reason;
    this.publish();
  }

  destroy(): void {
    if (this.stopped) return;
    this.close();
    this.stopped = true;
    gameEvents.off('quest.changed', this.publish, this);
    gameEvents.off('quest.completed', this.publish, this);
    this.resizeObserver.disconnect();
    this.modalHandle.unregister();
    this.listeners.clear();
  }

  private readonly publish = (): void => {
    if (this.stopped) return;
    const model = this.snapshot('quest-journal');
    for (const listener of this.listeners) listener(model);
  };
}

/**
 * Only quests the player has taken on: what to do now (main before side), then
 * history. Offers the player has not accepted stay with their quest giver.
 */
function listedQuests(): readonly QuestView[] {
  const mainFirst = (quests: readonly QuestView[]) => [...quests].sort((a, b) => (
    Number(b.definition.category === 'mandatory') - Number(a.definition.category === 'mandatory')
    || (b.acceptedAt ?? 0) - (a.acceptedAt ?? 0)
  ));
  return [
    ...mainFirst(questService.list('active')),
    ...mainFirst(questService.list('completed')),
    ...questService.list('failed'),
    ...questService.list('abandoned'),
  ];
}

function isFinished(quest: QuestView): boolean {
  return quest.status === 'completed' || quest.status === 'failed' || quest.status === 'abandoned';
}

function questMarker(quest: QuestView): string {
  if (quest.status === 'completed') return '✓';
  return quest.definition.category === 'mandatory' ? '★' : '◆';
}

function npcName(npcId: string | undefined): string {
  return npcId ? getNpcDefinition(npcId)?.displayName ?? npcId : 'the quest giver';
}

function stepOf(quest: QuestView): string {
  const stages = quest.definition.stages;
  const index = stages.findIndex((stage) => stage.id === quest.activeStageId);
  return stages.length > 1 && index >= 0 ? ` · Step ${index + 1}/${stages.length}` : '';
}

/** One short status line under each quest in the list. */
function questState(quest: QuestView): string {
  const kind = quest.definition.category === 'mandatory' ? 'Main' : 'Side';
  if (quest.status === 'active') return quest.readyToTurnIn ? `${kind} · Ready to turn in` : `${kind} · In progress${stepOf(quest)}`;
  if (quest.status === 'available') {
    const giver = quest.definition.acquisition.kind === 'npc' ? npcName(quest.definition.acquisition.npcIds[0]) : undefined;
    return giver ? `${kind} · Talk to ${giver}` : `${kind} · Available`;
  }
  if (quest.status === 'completed') return `${kind} · Done`;
  return `${kind} · ${quest.status === 'failed' ? 'Failed' : 'Abandoned'}`;
}

function actionFor(quest: QuestView): 'abandon' | 'retry' | undefined {
  const def = quest.definition;
  if (quest.status === 'active' && def.category === 'optional' && def.abandonmentPolicy.kind === 'retryable') return 'abandon';
  if (quest.status === 'failed' && def.failurePolicy.kind === 'retryable') return 'retry';
  if (quest.status === 'abandoned' && def.abandonmentPolicy.kind === 'retryable' && def.acquisition.kind === 'automatic') return 'retry';
  return undefined;
}

/** The book page: story first, then every step with each requirement on its own row. */
function detailsFor(quest: QuestView): string {
  const def = quest.definition;
  const visible = quest.visibleStages.length ? quest.visibleStages : def.stages.slice(0, 1);
  const activeIndex = def.stages.findIndex((stage) => stage.id === quest.activeStageId);
  const finished = quest.status === 'completed';
  const steps = visible.flatMap((stage) => {
    const index = def.stages.indexOf(stage);
    const done = finished || (activeIndex >= 0 && index < activeIndex);
    const current = !finished && index === activeIndex;
    const heading = def.stages.length > 1
      ? `${done ? '✓' : current ? '▶' : '○'} Step ${index + 1}: ${stage.title}`
      : undefined;
    const requirements = stage.objectives.map((objective) => {
      const progress = done ? objective.target : Math.min(objective.target, quest.progress[objective.id] ?? 0);
      const count = objective.target > 1 ? `  ${progress}/${objective.target}` : '';
      return `   ${progress >= objective.target ? '✓' : '•'} ${objectiveLabel(objective)}${count}`;
    });
    return [...(heading ? [heading] : []), ...requirements, ''];
  });
  const turnIn = quest.status === 'active' && quest.readyToTurnIn && def.completion.kind === 'npc-turn-in'
    ? [`? Return to ${npcName(def.completion.npcIds[0])} for your reward.`, '']
    : [];
  return [
    def.title,
    questState(quest),
    '',
    def.description,
    '',
    ...steps,
    ...turnIn,
    questRewardSummary(def.rewards),
    ...(quest.status === 'abandoned' && def.acquisition.kind === 'npc' ? ['', 'Return to the quest giver to continue.'] : []),
  ].join('\n');
}

function selectionIndex(payload: JsonValue | undefined): number | undefined {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return undefined;
  const index = (payload as Readonly<Record<string, JsonValue>>).index;
  return typeof index === 'number' && Number.isSafeInteger(index) && index >= 0 ? index : undefined;
}
