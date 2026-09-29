import { gameEvents } from '../../core/EventBus';
import { getQuestDefinition } from '../../content/quests/QuestCatalog';

export interface QuestNotificationContext {
  readonly getPosition: () => { x: number; y: number };
  readonly show: (x: number, y: number, message: string, color: 'white' | 'yellow' | 'green' | 'red', important?: boolean) => void;
  /** Large centered title card, used when a quest opens a new chapter. */
  readonly showBanner?: (title: string) => void;
}

/** Presentation-only quest toasts; it never mutates quest state. */
export class QuestNotificationPresenter {
  constructor(private readonly ctx: QuestNotificationContext) {
    gameEvents.on('quest.available', this.onAvailable, this);
    gameEvents.on('quest.accepted', this.onAccepted, this);
    gameEvents.on('quest.stage-completed', this.onStageCompleted, this);
    gameEvents.on('quest.failed', this.onFailed, this);
    gameEvents.on('quest.abandoned', this.onAbandoned, this);
  }

  destroy(): void {
    gameEvents.off('quest.available', this.onAvailable, this);
    gameEvents.off('quest.accepted', this.onAccepted, this);
    gameEvents.off('quest.stage-completed', this.onStageCompleted, this);
    gameEvents.off('quest.failed', this.onFailed, this);
    gameEvents.off('quest.abandoned', this.onAbandoned, this);
  }

  private notify(message: string, color: 'white' | 'yellow' | 'green' | 'red', important = false, lift = 70): void {
    const { x, y } = this.ctx.getPosition();
    this.ctx.show(x, y - lift, message, color, important);
  }

  private title(questId: string): string { return getQuestDefinition(questId)?.title ?? questId; }
  // Lifted above the completion card, which usually unlocks this quest in the same frame.
  private readonly onAvailable = ({ questId }: { questId: string }): void => this.notify(`New quest available: ${this.title(questId)}`, 'yellow', true, 112);
  private readonly onAccepted = ({ questId }: { questId: string }): void => {
    const chapter = getQuestDefinition(questId)?.chapter;
    if (chapter) this.ctx.showBanner?.(chapter);
    this.notify(`Quest accepted: ${this.title(questId)}`, 'green', true);
  };
  private readonly onStageCompleted = ({ questId }: { questId: string }): void => this.notify(`Stage complete: ${this.title(questId)}`, 'green');
  private readonly onFailed = ({ questId, reason }: { questId: string; reason: string }): void => this.notify(`Quest failed: ${this.title(questId)} (${reason})`, 'red', true);
  private readonly onAbandoned = ({ questId }: { questId: string }): void => this.notify(`Quest abandoned: ${this.title(questId)}`, 'red');
}
