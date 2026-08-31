import Phaser from 'phaser';
import type { QuestOfferView, QuestView } from '../content/quests/types';
import { questService, type QuestCommandResult } from '../quests/QuestService';
import { ModalStack, type ModalHandle } from './ModalStack';
import { resolveScreenUiDepth } from '../presentation/WorldDepth';

const FONT = 'Trebuchet MS, Segoe UI Variable, sans-serif';

export class QuestOfferModal {
  private readonly handle: ModalHandle;
  private container?: Phaser.GameObjects.Container;
  private errorText?: Phaser.GameObjects.Text;

  constructor(
    private readonly scene: Phaser.Scene,
    modalStack: ModalStack,
    private readonly onPausedChange: (paused: boolean) => void,
  ) {
    this.handle = modalStack.register('quest-offer', {
      isOpen: () => !!this.container,
      close: () => this.close(),
    });
  }

  openOffer(offer: QuestOfferView, onFinished?: () => void): void {
    this.close();
    const def = offer.quest.definition;
    this.build(def.title, offer.quest, offer.npcId, 'Accept quest', () => {
      this.runCommand(() => questService.accept(def.id, offer.npcId), onFinished);
    }, () => {
      this.runCommand(() => questService.decline(def.id, offer.npcId), onFinished);
    });
  }

  openTurnIn(quest: QuestView, npcId: string, onFinished?: () => void): void {
    this.close();
    this.build(`Complete: ${quest.definition.title}`, quest, npcId, 'Turn in and claim reward', () => {
      this.runCommand(() => questService.turnIn(quest.questId, npcId), onFinished);
    }, () => {
      onFinished?.();
      this.close();
    });
  }

  close(): void {
    if (!this.container) {
      this.handle.close();
      return;
    }
    this.handle.close();
    this.container.destroy();
    this.container = undefined;
    this.errorText = undefined;
    this.onPausedChange(false);
  }

  destroy(): void {
    const wasOpen = !!this.container;
    this.container?.destroy();
    this.container = undefined;
    this.errorText = undefined;
    this.handle.unregister();
    if (wasOpen) this.onPausedChange(false);
  }

  private build(
    title: string,
    quest: QuestView,
    _npcId: string,
    confirmLabel: string,
    confirm: () => void,
    decline: () => void,
  ): void {
    const cam = this.scene.cameras.main;
    const container = this.scene.add.container(cam.width / 2, cam.height / 2)
      .setScrollFactor(0).setDepth(resolveScreenUiDepth(130));
    this.container = container;
    const w = 560;
    const h = 360;
    const bg = this.scene.add.graphics();
    bg.fillStyle(0x101a31, 0.98);
    bg.fillRoundedRect(-w / 2, -h / 2, w, h, 16);
    bg.lineStyle(2, 0x73e2b1, 0.9);
    bg.strokeRoundedRect(-w / 2, -h / 2, w, h, 16);
    container.add(bg);
    container.add(this.scene.add.text(0, -h / 2 + 28, title, {
      fontFamily: FONT, fontSize: '22px', color: '#e7fff5', stroke: '#0b1020', strokeThickness: 4,
    }).setOrigin(0.5));
    container.add(this.scene.add.text(-w / 2 + 28, -h / 2 + 70, quest.definition.description, {
      fontFamily: FONT, fontSize: '14px', color: '#d7f6e9', wordWrap: { width: w - 56 },
    }));
    const stage = quest.visibleStages.at(-1) ?? quest.definition.stages[0];
    let y = -105;
    for (const objective of stage.objectives) {
      const progress = quest.progress[objective.id] ?? 0;
      container.add(this.scene.add.text(-w / 2 + 36, y, `• ${objective.label} (${progress}/${objective.target})`, {
        fontFamily: FONT, fontSize: '13px', color: '#ffdf8a',
      }));
      y += 22;
    }
    container.add(this.scene.add.text(-w / 2 + 36, 52, `Reward: ${quest.definition.rewards.coins ?? 0} coins · ${quest.definition.rewards.xp ?? 0} XP`, {
      fontFamily: FONT, fontSize: '13px', color: '#ffd277',
    }));
    this.errorText = this.scene.add.text(0, 88, '', {
      fontFamily: FONT, fontSize: '12px', color: '#ff9c9c', wordWrap: { width: w - 72 }, align: 'center',
    }).setOrigin(0.5).setVisible(false);
    container.add(this.errorText);
    const accept = this.button(confirmLabel, -100, 120, confirm);
    const cancel = this.button('Decline / close', 110, 120, decline);
    container.add([accept, cancel]);
    this.onPausedChange(true);
    this.handle.open();
  }

  private button(label: string, x: number, y: number, action: () => void): Phaser.GameObjects.Text {
    return this.scene.add.text(x, y, label, {
      fontFamily: FONT, fontSize: '14px', color: '#ffffff', backgroundColor: '#244664',
      padding: { left: 14, right: 14, top: 9, bottom: 9 },
    }).setOrigin(0.5).setInteractive({ useHandCursor: true }).on('pointerdown', action);
  }

  private runCommand(command: () => QuestCommandResult, onFinished?: () => void): void {
    try {
      const result = command();
      if (!result.ok) {
        this.showError(result.reason);
        return;
      }
      onFinished?.();
      this.close();
    } catch (error) {
      this.showError(error instanceof Error ? error.message : 'The quest action failed.');
    }
  }

  private showError(message: string): void {
    this.errorText?.setText(message).setVisible(true);
  }
}
