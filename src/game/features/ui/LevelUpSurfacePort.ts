import type { JsonValue } from '../../content/scenes/types';
import type { PerkChoice } from '../../core/types';
import { gameEvents } from '../../core/EventBus';
import { gameState } from '../../core/GameState';
import { getPerkDef, rollPerkChoices } from '../../systems/PlayerStats';
import { canReopenPendingLevelUp, reopenPendingLevelUpWhenIdle } from '../../ui/LevelUpReopenPolicy';
import type { ModalHandle, ModalStack } from '../../ui/ModalStack';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

export interface LevelUpSurfaceOptions {
  readonly modalStack: ModalStack;
  readonly uiRoot: HTMLElement;
  readonly onPausedChange: (paused: boolean) => void;
}

/** Pending perk choices and selection for the authored level-up modal. */
export class LevelUpSurfacePort implements UiSurfacePort {
  private readonly handle: ModalHandle;
  private readonly listeners = new Set<(model: UiPresentationModel) => void>();
  private readonly resizeObserver: ResizeObserver;
  private choices: PerkChoice[] = [];
  private openValue = false;
  private stopped = false;

  constructor(private readonly options: LevelUpSurfaceOptions) {
    this.handle = options.modalStack.register('level-up', {
      isOpen: () => this.isOpen(), close: () => this.close(),
    });
    gameEvents.on('level.up', this.onLevelUp, this);
    document.addEventListener('keydown', this.handleKeyDown, { capture: true });
    this.resizeObserver = new ResizeObserver(this.publish);
    this.resizeObserver.observe(options.uiRoot);
  }

  isOpen(): boolean { return this.openValue; }
  reopenPending(): boolean {
    if (!canReopenPendingLevelUp({ isOpen: this.openValue, isClosing: false, choiceCount: this.choices.length })) return false;
    gameEvents.emit('levelup.modal.open', { choices: this.choices });
    this.openValue = true;
    this.options.onPausedChange(true);
    this.handle.open();
    this.publish();
    return true;
  }
  close(pickedPerkId: string | null = null): void {
    if (!this.openValue) { this.handle.close(); return; }
    this.openValue = false;
    this.handle.close();
    this.options.onPausedChange(false);
    gameEvents.emit('levelup.modal.close', { pickedPerkId });
    this.publish();
  }

  snapshot(surfaceId: string): UiPresentationModel {
    if (surfaceId !== 'level-up-modal' || this.stopped) return {};
    const width = Math.min(720, Math.max(1, this.options.uiRoot.clientWidth - 32));
    const height = Math.min(520, Math.max(1, this.options.uiRoot.clientHeight - 32));
    return {
      open: this.openValue,
      offsetMin: [-Math.round(width / 2), -Math.round(height / 2)],
      offsetMax: [Math.round(width / 2), Math.round(height / 2)],
      title: `LEVEL UP! · Level ${gameState.level}`,
      choices: this.choices.map((choice, index) => {
        const rank = gameState.perkRank(choice.id);
        const maxRank = getPerkDef(choice.id)?.maxRank;
        return { id: choice.id, label: `[${index + 1}] ${choice.title}\nRank ${rank}${maxRank ? `/${maxRank}` : ''}\n${choice.description}` };
      }),
    };
  }

  subscribe(surfaceId: string, listener: (model: UiPresentationModel) => void): () => void {
    if (surfaceId !== 'level-up-modal' || this.stopped) return () => undefined;
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  invoke(surfaceId: string, actionId: string, payload?: JsonValue): void {
    if (surfaceId !== 'level-up-modal' || this.stopped) return;
    if (actionId === 'close') { this.close(); return; }
    if (actionId !== 'choose-upgrade' || !this.openValue) return;
    const index = selectionIndex(payload);
    if (index !== undefined) this.choose(index);
  }

  destroy(): void {
    if (this.stopped) return;
    this.close();
    this.stopped = true;
    gameEvents.off('level.up', this.onLevelUp, this);
    document.removeEventListener('keydown', this.handleKeyDown, { capture: true });
    this.resizeObserver.disconnect();
    this.handle.unregister();
    this.listeners.clear();
    this.choices = [];
  }

  private readonly onLevelUp = (): void => {
    if (this.stopped || this.openValue || this.choices.length > 0) return;
    this.choices = rollPerkChoices();
    if (this.choices.length > 0) this.reopenPending();
  };

  private choose(index: number): void {
    const choice = this.choices[index];
    if (!choice || !gameState.spendSkillPoint(choice.id)) return;
    this.choices = [];
    this.close(choice.id);
  }

  private readonly handleKeyDown = (event: KeyboardEvent): void => {
    if (event.repeat || event.ctrlKey || event.altKey || event.metaKey) return;
    if (this.openValue && /^[1-3]$/.test(event.key)) {
      this.choose(Number(event.key) - 1);
      event.preventDefault();
      event.stopPropagation();
      return;
    }
    if (!this.openValue && event.key.toLowerCase() === 'p' && reopenPendingLevelUpWhenIdle(this.options.modalStack, this)) {
      event.preventDefault();
      event.stopPropagation();
    }
  };

  private readonly publish = (): void => {
    if (this.stopped) return;
    const model = this.snapshot('level-up-modal');
    for (const listener of this.listeners) listener(model);
  };
}

function selectionIndex(payload: JsonValue | undefined): number | undefined {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return undefined;
  const index = (payload as Readonly<Record<string, JsonValue>>).index;
  return typeof index === 'number' && Number.isSafeInteger(index) && index >= 0 ? index : undefined;
}
