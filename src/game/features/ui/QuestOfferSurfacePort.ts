import type { JsonValue } from '../../content/scenes/types';
import type { QuestOfferView, QuestView } from '../../content/quests/types';
import { questService, type QuestCommandResult } from '../../quests/QuestService';
import type { ModalHandle, ModalStack } from '../../ui/ModalStack';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';
import { questRewardSummary } from '../quests/QuestRewardText';

export interface QuestOfferSurfaceOptions {
  readonly modalStack: ModalStack;
  readonly uiRoot: HTMLElement;
  readonly onPausedChange: (paused: boolean) => void;
}

interface OfferSession {
  readonly quest: QuestView;
  readonly npcId: string;
  readonly kind: 'offer' | 'turn-in';
  readonly onFinished?: () => void;
  readonly onClosed?: () => void;
}

/** Quest NPC decision session backed by the authored offer/turn-in modal. */
export class QuestOfferSurfacePort implements UiSurfacePort {
  private readonly handle: ModalHandle;
  private readonly listeners = new Set<(model: UiPresentationModel) => void>();
  private readonly resizeObserver: ResizeObserver;
  private session?: OfferSession;
  private error = '';
  private stopped = false;

  constructor(private readonly options: QuestOfferSurfaceOptions) {
    this.handle = options.modalStack.register('quest-offer', {
      isOpen: () => this.isOpen(), close: () => this.close(),
    });
    this.resizeObserver = new ResizeObserver(this.publish);
    this.resizeObserver.observe(options.uiRoot);
  }

  isOpen(): boolean { return !!this.session; }

  openOffer(offer: QuestOfferView, onFinished?: () => void, onClosed?: () => void): void {
    this.openSession({ quest: offer.quest, npcId: offer.npcId, kind: 'offer', onFinished, onClosed });
  }

  openTurnIn(quest: QuestView, npcId: string, onFinished?: () => void, onClosed?: () => void): void {
    this.openSession({ quest, npcId, kind: 'turn-in', onFinished, onClosed });
  }

  close(): void {
    const session = this.session;
    if (!session) { this.handle.close(); return; }
    this.session = undefined;
    this.error = '';
    this.handle.close();
    try {
      this.options.onPausedChange(false);
    } finally {
      this.publish();
      session.onClosed?.();
    }
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== 'quest-offer-modal' || this.stopped) return {};
    const session = this.session;
    const quest = session?.quest;
    const stage = quest?.visibleStages.at(-1) ?? quest?.definition.stages[0];
    const objectives = stage?.objectives.map((objective) =>
      `• ${objective.label} (${quest?.progress[objective.id] ?? 0}/${objective.target})`) ?? [];
    const width = Math.min(720, Math.max(1, this.options.uiRoot.clientWidth - 32));
    const height = Math.min(460, Math.max(1, this.options.uiRoot.clientHeight - 32));
    return {
      open: !!session,
      offsetMin: [-Math.round(width / 2), -Math.round(height / 2)],
      offsetMax: [Math.round(width / 2), Math.round(height / 2)],
      title: session ? session.kind === 'turn-in' ? `Complete: ${quest!.definition.title}` : quest!.definition.title : '',
      description: quest ? [quest.definition.description, '', ...objectives, '',
        questRewardSummary(quest.definition.rewards)].join('\n') : '',
      acceptLabel: session?.kind === 'turn-in' ? 'Turn in and claim reward' : 'Accept quest',
      declineLabel: session?.kind === 'turn-in' ? 'Close' : 'Decline / close',
      error: this.error,
    };
  }

  subscribe(surfaceId: string, listener: (model: UiPresentationModel) => void): () => void {
    if (surfaceId !== 'quest-offer-modal' || this.stopped) return () => undefined;
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  invoke(surfaceId: string, actionId: string, _payload?: JsonValue): void {
    if (surfaceId !== 'quest-offer-modal' || this.stopped) return;
    if (actionId === 'close') { this.close(); return; }
    const session = this.session;
    if (!session) return;
    if (actionId === 'decline' && session.kind === 'turn-in') {
      try { session.onFinished?.(); } finally { this.close(); }
      return;
    }
    if (actionId !== 'accept' && actionId !== 'decline') return;
    this.runCommand(() => {
      if (session.kind === 'turn-in') return questService.turnIn(session.quest.questId, session.npcId);
      return actionId === 'accept'
        ? questService.accept(session.quest.questId, session.npcId)
        : questService.decline(session.quest.questId, session.npcId);
    }, session);
  }

  destroy(): void {
    if (this.stopped) return;
    this.close();
    this.stopped = true;
    this.resizeObserver.disconnect();
    this.handle.unregister();
    this.listeners.clear();
  }

  private openSession(session: OfferSession): void {
    if (this.stopped) return;
    this.close();
    this.session = session;
    this.error = '';
    this.options.onPausedChange(true);
    this.handle.open();
    this.publish();
  }

  private runCommand(command: () => QuestCommandResult, session: OfferSession): void {
    try {
      const result = command();
      if (!result.ok) { this.error = result.reason; this.publish(); return; }
      try { session.onFinished?.(); } finally { this.close(); }
    } catch (error) {
      this.error = error instanceof Error ? error.message : 'The quest action failed.';
      this.publish();
    }
  }

  private readonly publish = (): void => {
    if (this.stopped) return;
    const model = this.snapshot('quest-offer-modal');
    for (const listener of this.listeners) listener(model);
  };
}
