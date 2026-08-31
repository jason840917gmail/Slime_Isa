import Phaser from 'phaser';
import { gameEvents } from '../core/EventBus';
import { getQuestDefinition } from '../content/quests/QuestCatalog';
import type { QuestState } from '../content/quests/types';
import { questService, type QuestCommandResult } from '../quests/QuestService';
import { resolveScreenUiDepth } from '../presentation/WorldDepth';
import { ModalStack, type ModalHandle } from './ModalStack';

const FONT = 'Trebuchet MS, Segoe UI Variable, sans-serif';

export interface QuestJournalContext {
  scene: Phaser.Scene;
  modalStack: ModalStack;
  onPausedChange: (paused: boolean) => void;
}

export class QuestJournal {
  private ctx: QuestJournalContext;
  private readonly modalHandle: ModalHandle;
  private container?: Phaser.GameObjects.Container;
  private commandMessage?: { readonly text: string; readonly color: string };

  constructor(ctx: QuestJournalContext) {
    this.ctx = ctx;
    this.modalHandle = ctx.modalStack.register('quest-journal', {
      isOpen: () => this.isOpen(),
      close: () => this.close(),
    });
    gameEvents.on('quest.changed', this.refresh, this);
    gameEvents.on('quest.completed', this.refresh, this);
  }

  isOpen(): boolean {
    return !!this.container;
  }

  toggle(): void {
    if (this.container) this.close();
    else this.open();
  }

  private open(): void {
    this.build();
    this.ctx.onPausedChange(true);
    this.modalHandle.open();
  }

  private refresh = (): void => {
    if (!this.container) return;
    this.container.destroy();
    this.container = undefined;
    this.build();
  };

  private build(): void {
    const scene = this.ctx.scene;
    const cam = scene.cameras.main;
    const panelW = 620;
    const panelH = 520;
    const container = scene.add.container(cam.width / 2, cam.height / 2).setScrollFactor(0).setDepth(resolveScreenUiDepth(115));
    this.container = container;

    container.add(scene.add.rectangle(0, 0, cam.width, cam.height, 0x080f20, 0.7).setOrigin(0.5));
    const bg = scene.add.graphics();
    bg.fillStyle(0x101a31, 0.98);
    bg.fillRoundedRect(-panelW / 2, -panelH / 2, panelW, panelH, 16);
    bg.lineStyle(2, 0x73e2b1, 0.85);
    bg.strokeRoundedRect(-panelW / 2, -panelH / 2, panelW, panelH, 16);
    container.add(bg);

    container.add(scene.add.text(0, -panelH / 2 + 28, 'Quest Journal', {
      fontFamily: FONT,
      fontSize: '24px',
      color: '#e7fff5',
      stroke: '#0b1020',
      strokeThickness: 5,
    }).setOrigin(0.5));

    container.add(scene.add.text(panelW / 2 - 18, -panelH / 2 + 20, 'U / Esc to close', {
      fontFamily: FONT,
      fontSize: '12px',
      color: '#88c899',
    }).setOrigin(1, 0));

    if (this.commandMessage) {
      container.add(scene.add.text(0, -panelH / 2 + 62, this.commandMessage.text, {
        fontFamily: FONT,
        fontSize: '12px',
        color: this.commandMessage.color,
      }).setOrigin(0.5));
    }

    const active = questService.list('active');
    const completed = questService.list('completed');
    const available = questService.list('available');
    const history = [...questService.list('failed'), ...questService.list('abandoned')];
    let y = -140;

    container.add(scene.add.text(-panelW / 2 + 28, y, 'Available', {
      fontFamily: FONT,
      fontSize: '16px',
      color: '#ffdf8a',
    }).setOrigin(0, 0.5));
    y += 28;
    if (available.length === 0) {
      container.add(scene.add.text(-panelW / 2 + 32, y, 'No available quests.', {
        fontFamily: FONT,
        fontSize: '13px',
        color: '#88c899',
      }).setOrigin(0, 0.5));
      y += 24;
    } else {
      for (const quest of available) y = this.drawQuest(container, quest, y, true) + 8;
    }
    y += 12;

    container.add(scene.add.text(-panelW / 2 + 28, y, 'Active', {
      fontFamily: FONT,
      fontSize: '16px',
      color: '#ffdf8a',
    }).setOrigin(0, 0.5));
    y += 28;

    if (active.length === 0) {
      container.add(scene.add.text(-panelW / 2 + 32, y, 'No active quests.', {
        fontFamily: FONT,
        fontSize: '13px',
        color: '#88c899',
      }).setOrigin(0, 0.5));
      y += 28;
    } else {
      for (const state of active) {
        y = this.drawQuest(container, state, y, false) + 14;
      }
    }

    y += 12;
    container.add(scene.add.text(-panelW / 2 + 28, y, 'Completed', {
      fontFamily: FONT,
      fontSize: '16px',
      color: '#86f0c3',
    }).setOrigin(0, 0.5));
    y += 28;

    if (completed.length === 0) {
      container.add(scene.add.text(-panelW / 2 + 32, y, 'Completed quests will appear here.', {
        fontFamily: FONT,
        fontSize: '13px',
        color: '#668070',
      }).setOrigin(0, 0.5));
    } else {
      for (const state of completed.slice(-4)) {
        y = this.drawQuest(container, state, y, true) + 8;
      }
    }

    y += 12;
    container.add(scene.add.text(-panelW / 2 + 28, y, 'Failed / Abandoned', {
      fontFamily: FONT,
      fontSize: '16px',
      color: '#ffb0a8',
    }).setOrigin(0, 0.5));
    y += 28;
    if (history.length === 0) {
      container.add(scene.add.text(-panelW / 2 + 32, y, 'No quest history.', {
        fontFamily: FONT,
        fontSize: '13px',
        color: '#668070',
      }).setOrigin(0, 0.5));
    } else {
      for (const quest of history.slice(-4)) {
        y = this.drawQuest(container, quest, y, true) + 8;
      }
    }

    scene.tweens.add({ targets: container, alpha: { from: 0, to: 1 }, scale: { from: 0.97, to: 1 }, duration: 140 });
  }

  private drawQuest(container: Phaser.GameObjects.Container, state: QuestState, y: number, compact: boolean): number {
    const scene = this.ctx.scene;
    const def = getQuestDefinition(state.questId);
    if (!def) return y;

    const left = -280;
    const status = state.status === 'completed' ? 'DONE' : state.status.toUpperCase();
    container.add(scene.add.text(left, y, `${def.title}  [${status}]`, {
      fontFamily: FONT,
      fontSize: compact ? '13px' : '15px',
      color: state.status === 'completed' ? '#86f0c3' : '#f5f7ff',
      stroke: '#0b1020',
      strokeThickness: 3,
    }).setOrigin(0, 0.5));
    if (!compact && state.status === 'active' && def.category === 'optional'
      && def.abandonmentPolicy.kind === 'retryable') {
      container.add(scene.add.text(left + 530, y, 'Abandon', {
        fontFamily: FONT,
        fontSize: '11px',
        color: '#ff9c9c',
      }).setOrigin(1, 0.5).setInteractive({ useHandCursor: true }).on('pointerdown', () => {
        if (!window.confirm(`Abandon "${def.title}"? You can retry it later.`)) return;
        this.handleCommand(questService.abandon(state.questId), 'Quest abandoned.');
      }));
    } else if (compact && state.status === 'failed' && def.failurePolicy.kind === 'retryable') {
      container.add(this.action(left + 530, y, 'Retry', () => {
        this.handleCommand(questService.retryFailed(state.questId), 'Quest restarted.');
      }));
    } else if (compact && state.status === 'abandoned'
      && def.abandonmentPolicy.kind === 'retryable'
      && def.acquisition.kind === 'automatic') {
      container.add(this.action(left + 530, y, 'Retry', () => {
        this.handleCommand(questService.retryAbandonedAutomatic(state.questId), 'Quest restarted.');
      }));
    } else if (compact && state.status === 'abandoned'
      && def.abandonmentPolicy.kind === 'retryable'
      && def.acquisition.kind === 'npc') {
      container.add(scene.add.text(left + 530, y, 'Return to quest giver', {
        fontFamily: FONT,
        fontSize: '11px',
        color: '#ffdf8a',
      }).setOrigin(1, 0.5));
    }
    y += compact ? 22 : 26;

    if (!compact) {
      container.add(scene.add.text(left + 10, y, def.description, {
        fontFamily: FONT,
        fontSize: '12px',
        color: '#d7f6e9',
        wordWrap: { width: 530 },
      }).setOrigin(0, 0));
      y += 42;
    }

    const activeIndex = state.activeStageId === null
      ? state.status === 'completed' ? def.stages.length - 1
        : state.resumeStageId ? def.stages.findIndex((stage) => stage.id === state.resumeStageId) : -1
      : def.stages.findIndex((stage) => stage.id === state.activeStageId);
    for (const [stageIndex, stage] of def.stages.slice(0, Math.max(0, activeIndex + 1)).entries()) {
      if (def.stages.length > 1) {
        container.add(scene.add.text(left + 8, y, `${stageIndex + 1}. ${stage.title}`, {
          fontFamily: FONT,
          fontSize: '12px',
          color: stageIndex < activeIndex ? '#86f0c3' : '#ffdf8a',
        }).setOrigin(0, 0.5));
        y += 18;
      }
      for (const obj of stage.objectives) {
        const progress = Math.min(obj.target, state.progress[obj.id] ?? 0);
        const done = progress >= obj.target;
        container.add(scene.add.text(left + 16, y, `${done ? '✓' : '•'} ${obj.label}: ${progress}/${obj.target}`, {
          fontFamily: FONT,
          fontSize: '12px',
          color: done ? '#86f0c3' : '#d8e8d0',
        }).setOrigin(0, 0.5));
        y += 20;
      }
    }

    if (!compact) {
      const reward = [`${def.rewards.coins ?? 0} coins`, `${def.rewards.xp ?? 0} XP`].join('  ·  ');
      container.add(scene.add.text(left + 16, y, `Reward: ${reward}`, {
        fontFamily: FONT,
        fontSize: '12px',
        color: '#ffd277',
      }).setOrigin(0, 0.5));
      y += 22;
    }

    return y;
  }

  public close(): void {
    if (!this.container) {
      this.modalHandle.close();
      this.commandMessage = undefined;
      return;
    }
    this.modalHandle.close();
    this.container.destroy();
    this.container = undefined;
    this.commandMessage = undefined;
    this.ctx.onPausedChange(false);
  }

  private action(x: number, y: number, label: string, execute: () => void): Phaser.GameObjects.Text {
    return this.ctx.scene.add.text(x, y, label, {
      fontFamily: FONT,
      fontSize: '11px',
      color: '#86f0c3',
    }).setOrigin(1, 0.5).setInteractive({ useHandCursor: true }).on('pointerdown', execute);
  }

  private handleCommand(result: QuestCommandResult, successMessage: string): void {
    this.commandMessage = result.ok
      ? { text: successMessage, color: '#86f0c3' }
      : { text: result.reason, color: '#ff9c9c' };
    this.refresh();
  }

  destroy(): void {
    gameEvents.off('quest.changed', this.refresh, this);
    gameEvents.off('quest.completed', this.refresh, this);
    this.modalHandle.unregister();
    const wasOpen = !!this.container;
    this.container?.destroy();
    this.container = undefined;
    if (wasOpen) this.ctx.onPausedChange(false);
  }
}
