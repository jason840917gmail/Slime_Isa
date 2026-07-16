import Phaser from 'phaser';
import { gameEvents } from '../core/EventBus';
import { gameState } from '../core/GameState';
import { rollPerkChoices, getPerkDef } from '../systems/PlayerStats';
import type { PerkChoice } from '../core/types';

/**
 * Level-up modal. On the `level.up` event, rolls 3 perks and presents them
 * roguelite-style. While open, sets a "paused" flag on the scene via the
 * callback so the simulation freezes but UI keeps animating.
 *
 * Click a card or press 1/2/3 to pick. The game stays paused until a perk is chosen.
 */
const FONT = 'Aptos, Segoe UI Variable, sans-serif';

export interface LevelUpModalContext {
  scene: Phaser.Scene;
  onPausedChange: (paused: boolean) => void;
}

export class LevelUpModal {
  private ctx: LevelUpModalContext;
  private container?: Phaser.GameObjects.Container;
  private choices: PerkChoice[] = [];
  private cardKeys: Phaser.Input.Keyboard.Key[] = [];

  constructor(ctx: LevelUpModalContext) {
    this.ctx = ctx;
    gameEvents.on('level.up', this.open, this);
  }

  isOpen(): boolean {
    return !!this.container;
  }

  private open = (): void => {
    if (this.container) return;
    this.choices = rollPerkChoices();
    if (this.choices.length === 0) return;

    gameEvents.emit('levelup.modal.open', { choices: this.choices });
    this.ctx.onPausedChange(true);
    this.build();
  };

  private build(): void {
    const scene = this.ctx.scene;
    const cam = scene.cameras.main;
    const cx = cam.width / 2;
    const cy = cam.height / 2;

    const container = scene.add.container(cx, cy).setScrollFactor(0).setDepth(300);
    this.container = container;

    const dim = scene.add.rectangle(0, 0, cam.width, cam.height, 0x000000, 0.55).setOrigin(0.5);
    container.add(dim);

    container.add(
      scene.add
        .text(0, -130, 'LEVEL UP!', {
          fontFamily: FONT,
          fontSize: '32px',
          color: '#a3f0c0',
          stroke: '#0a1f15',
          strokeThickness: 6,
        })
        .setOrigin(0.5),
    );

    const cardW = 150;
    const cardH = 170;
    const gap = 16;
    const totalW = this.choices.length * cardW + (this.choices.length - 1) * gap;
    const startX = -totalW / 2 + cardW / 2;

    this.choices.forEach((choice, i) => {
      const x = startX + i * (cardW + gap);
      const card = scene.add.container(x, 10);

      const bg = scene.add.graphics();
      bg.fillStyle(0x0e2a1f, 0.96);
      bg.fillRoundedRect(-cardW / 2, -cardH / 2, cardW, cardH, 10);
      bg.lineStyle(2, 0x44cc88, 0.9);
      bg.strokeRoundedRect(-cardW / 2, -cardH / 2, cardW, cardH, 10);
      card.add(bg);

      const iconKey = choice.icon ?? 'perk-default';
      const icon = scene.add.image(0, -cardH / 2 + 32, iconKey).setDisplaySize(36, 36);
      card.add(icon);

      const rank = gameState.perkRank(choice.id);
      const def = getPerkDef(choice.id);
      const rankLabel = def ? `Rank ${rank}/${def.maxRank}` : `Rank ${rank}`;
      card.add(
        scene.add
          .text(0, -cardH / 2 + 60, rankLabel, {
            fontFamily: FONT,
            fontSize: '10px',
            color: '#88c899',
          })
          .setOrigin(0.5),
      );

      card.add(
        scene.add
          .text(0, -8, choice.title, {
            fontFamily: FONT,
            fontSize: '15px',
            color: '#f4fff7',
            stroke: '#0a1f15',
            strokeThickness: 3,
            align: 'center',
            wordWrap: { width: cardW - 16 },
          })
          .setOrigin(0.5),
      );

      card.add(
        scene.add
          .text(0, 40, choice.description, {
            fontFamily: FONT,
            fontSize: '11px',
            color: '#ccebd0',
            align: 'center',
            wordWrap: { width: cardW - 18 },
          })
          .setOrigin(0.5),
      );

      const numLabel = scene.add
        .text(0, cardH / 2 - 16, `[${i + 1}]`, {
          fontFamily: FONT,
          fontSize: '12px',
          color: '#ffd86b',
        })
        .setOrigin(0.5);
      card.add(numLabel);

      bg.setInteractive({
        hitArea: new Phaser.Geom.Rectangle(-cardW / 2, -cardH / 2, cardW, cardH),
        hitAreaCallback: Phaser.Geom.Rectangle.Contains,
        useHandCursor: true,
      });
      bg.on('pointerdown', () => this.pick(choice.id));
      bg.on('pointerover', () => card.setScale(1.05));
      bg.on('pointerout', () => card.setScale(1));

      container.add(card);
    });

    container.add(
      scene.add
        .text(0, 150, 'Press 1/2/3 to pick an ability', {
          fontFamily: FONT,
          fontSize: '12px',
          color: '#88c899',
        })
        .setOrigin(0.5),
    );

    const kb = scene.input.keyboard;
    if (kb) {
      this.cardKeys = [
        kb.addKey(Phaser.Input.Keyboard.KeyCodes.ONE),
        kb.addKey(Phaser.Input.Keyboard.KeyCodes.TWO),
        kb.addKey(Phaser.Input.Keyboard.KeyCodes.THREE),
      ];
      this.cardKeys.forEach((k, i) => {
        k.on('down', () => {
          if (this.choices[i]) this.pick(this.choices[i].id);
        });
      });
    }

    scene.tweens.add({
      targets: container,
      scale: { from: 0.85, to: 1 },
      alpha: { from: 0, to: 1 },
      duration: 220,
      ease: 'Back.Out',
    });
  }

  private pick(perkId: string): void {
    if (!this.container) return;
    gameState.spendSkillPoint(perkId);
    this.close(perkId);
  }

  private close(pickedPerkId: string): void {
    if (!this.container) return;
    this.cardKeys.forEach((k) => k.off('down'));
    this.cardKeys = [];

    this.ctx.scene.tweens.add({
      targets: this.container,
      scale: 0.9,
      alpha: 0,
      duration: 160,
      onComplete: () => {
        this.container?.destroy();
        this.container = undefined;
        this.ctx.onPausedChange(false);
        gameEvents.emit('levelup.modal.close', { pickedPerkId });
      },
    });
  }

  destroy(): void {
    gameEvents.off('level.up', this.open, this);
    this.cardKeys.forEach((k) => k.off('down'));
    this.container?.destroy();
  }
}
