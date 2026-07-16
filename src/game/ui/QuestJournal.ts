import Phaser from 'phaser';
import { gameEvents } from '../core/EventBus';
import { getQuestDef, type QuestState } from '../quests/Quest';
import { questTracker } from '../quests/QuestTracker';

const FONT = 'Aptos, Segoe UI Variable, sans-serif';

export interface QuestJournalContext {
  scene: Phaser.Scene;
  onPausedChange: (paused: boolean) => void;
}

export class QuestJournal {
  private ctx: QuestJournalContext;
  private container?: Phaser.GameObjects.Container;
  private escKey?: Phaser.Input.Keyboard.Key;

  constructor(ctx: QuestJournalContext) {
    this.ctx = ctx;
    gameEvents.on('quest.changed', this.refresh, this);
    gameEvents.on('quest.completed', this.refresh, this);

    const kb = ctx.scene.input.keyboard;
    if (kb) {
      this.escKey = kb.addKey(Phaser.Input.Keyboard.KeyCodes.ESC);
      this.escKey.on('down', () => {
        if (this.container) this.close();
      });
    }
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
    const panelH = 420;
    const container = scene.add.container(cam.width / 2, cam.height / 2).setScrollFactor(0).setDepth(315);
    this.container = container;

    container.add(scene.add.rectangle(0, 0, cam.width, cam.height, 0x020906, 0.7).setOrigin(0.5));
    const bg = scene.add.graphics();
    bg.fillStyle(0x071612, 0.98);
    bg.fillRoundedRect(-panelW / 2, -panelH / 2, panelW, panelH, 16);
    bg.lineStyle(2, 0x44cc88, 0.85);
    bg.strokeRoundedRect(-panelW / 2, -panelH / 2, panelW, panelH, 16);
    container.add(bg);

    container.add(scene.add.text(0, -panelH / 2 + 28, 'Quest Journal', {
      fontFamily: FONT,
      fontSize: '24px',
      color: '#dffff0',
      stroke: '#0a1f15',
      strokeThickness: 5,
    }).setOrigin(0.5));

    container.add(scene.add.text(panelW / 2 - 18, -panelH / 2 + 20, 'U / Esc to close', {
      fontFamily: FONT,
      fontSize: '12px',
      color: '#88c899',
    }).setOrigin(1, 0));

    const active = questTracker.active();
    const completed = questTracker.completed();
    let y = -140;

    container.add(scene.add.text(-panelW / 2 + 28, y, 'Active', {
      fontFamily: FONT,
      fontSize: '16px',
      color: '#ffe680',
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
      color: '#88ffaa',
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

    scene.tweens.add({ targets: container, alpha: { from: 0, to: 1 }, scale: { from: 0.97, to: 1 }, duration: 140 });
  }

  private drawQuest(container: Phaser.GameObjects.Container, state: QuestState, y: number, compact: boolean): number {
    const scene = this.ctx.scene;
    const def = getQuestDef(state.id);
    if (!def) return y;

    const left = -280;
    const status = state.status === 'completed' ? 'DONE' : 'ACTIVE';
    container.add(scene.add.text(left, y, `${def.title}  [${status}]`, {
      fontFamily: FONT,
      fontSize: compact ? '13px' : '15px',
      color: state.status === 'completed' ? '#88ffaa' : '#f4fff7',
      stroke: '#0a1f15',
      strokeThickness: 3,
    }).setOrigin(0, 0.5));
    y += compact ? 22 : 26;

    if (!compact) {
      container.add(scene.add.text(left + 10, y, def.description, {
        fontFamily: FONT,
        fontSize: '12px',
        color: '#ccebd0',
        wordWrap: { width: 530 },
      }).setOrigin(0, 0));
      y += 42;
    }

    for (const obj of def.objectives) {
      const progress = Math.min(obj.target, state.progress[obj.id] ?? 0);
      const done = progress >= obj.target;
      container.add(scene.add.text(left + 16, y, `${done ? '✓' : '•'} ${obj.label}: ${progress}/${obj.target}`, {
        fontFamily: FONT,
        fontSize: '12px',
        color: done ? '#88ffaa' : '#d8e8d0',
      }).setOrigin(0, 0.5));
      y += 20;
    }

    if (!compact) {
      const reward = [`${def.rewards.coins ?? 0} coins`, `${def.rewards.xp ?? 0} XP`].join('  ·  ');
      container.add(scene.add.text(left + 16, y, `Reward: ${reward}`, {
        fontFamily: FONT,
        fontSize: '12px',
        color: '#ffd86b',
      }).setOrigin(0, 0.5));
      y += 22;
    }

    return y;
  }

  private close(): void {
    if (!this.container) return;
    this.container.destroy();
    this.container = undefined;
    this.ctx.onPausedChange(false);
  }

  destroy(): void {
    gameEvents.off('quest.changed', this.refresh, this);
    gameEvents.off('quest.completed', this.refresh, this);
    this.escKey?.off('down');
    this.container?.destroy();
  }
}
