import type { JsonValue } from '../../content/scenes/types';
import type { QuestView } from '../../content/quests/types';
import { gameEvents } from '../../core/EventBus';
import { questService, type QuestCommandResult } from '../../quests/QuestService';
import type { ModalHandle, ModalStack } from '../../ui/ModalStack';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

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
      quests: quests.map((quest) => ({ id: quest.questId, label: `[${quest.status.toUpperCase()}] ${quest.definition.title}` })),
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

function listedQuests(): readonly QuestView[] {
  return [
    ...questService.list('available'),
    ...questService.list('active'),
    ...questService.list('completed'),
    ...questService.list('failed'),
    ...questService.list('abandoned'),
  ];
}

function actionFor(quest: QuestView): 'abandon' | 'retry' | undefined {
  const def = quest.definition;
  if (quest.status === 'active' && def.category === 'optional' && def.abandonmentPolicy.kind === 'retryable') return 'abandon';
  if (quest.status === 'failed' && def.failurePolicy.kind === 'retryable') return 'retry';
  if (quest.status === 'abandoned' && def.abandonmentPolicy.kind === 'retryable' && def.acquisition.kind === 'automatic') return 'retry';
  return undefined;
}

function detailsFor(quest: QuestView): string {
  const def = quest.definition;
  const stages = quest.visibleStages.length ? quest.visibleStages : def.stages.slice(0, 1);
  const progress = stages.flatMap((stage) => [
    ...(def.stages.length > 1 ? [stage.title] : []),
    ...stage.objectives.map((objective) => {
      const current = Math.min(objective.target, quest.progress[objective.id] ?? 0);
      return `${current >= objective.target ? '✓' : '•'} ${objective.label}: ${current}/${objective.target}`;
    }),
  ]);
  return [def.title, quest.status.toUpperCase(), '', def.description, '', ...progress, '',
    `Reward: ${def.rewards.coins ?? 0} coins · ${def.rewards.xp ?? 0} XP`,
    ...(quest.status === 'abandoned' && def.acquisition.kind === 'npc' ? ['', 'Return to the quest giver to continue.'] : []),
  ].join('\n');
}

function selectionIndex(payload: JsonValue | undefined): number | undefined {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return undefined;
  const index = (payload as Readonly<Record<string, JsonValue>>).index;
  return typeof index === 'number' && Number.isSafeInteger(index) && index >= 0 ? index : undefined;
}
