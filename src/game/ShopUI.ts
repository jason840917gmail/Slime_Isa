import Phaser from 'phaser';
import { resolveScreenUiDepth } from './presentation/WorldDepth';

export interface ShopCallbacks {
  onBuyBoost: () => void;
  onBuyFriend: () => void;
  onCoinsChanged: (coins: number) => void;
}

export class ShopUI {
  private container: Phaser.GameObjects.Container;
  private visible = false;
  private callbacks: ShopCallbacks;

  constructor(scene: Phaser.Scene, x: number, y: number, callbacks: ShopCallbacks) {
    this.callbacks = callbacks;

    const bg = scene.add.graphics();
    bg.fillStyle(0x101a31, 0.92);
    bg.fillRoundedRect(-140, -90, 280, 180, 10);
    bg.lineStyle(2, 0x3b5c78, 0.6);
    bg.strokeRoundedRect(-140, -90, 280, 180, 10);

    this.container = scene.add.container(x, y);
    this.container.add(bg);

    const font = 'Trebuchet MS, Segoe UI Variable, sans-serif';

    this.container.add(
      scene.add
        .text(-120, -78, 'Mini Shop', {
          fontFamily: font,
          fontSize: '18px',
          color: '#d7f6e9',
        })
        .setDepth(resolveScreenUiDepth(40)),
    );

    const boostBtn = scene.add
      .text(-120, 20, 'Boost +50 speed â€” 25c', {
        fontFamily: font,
        fontSize: '14px',
        color: '#e6f5df',
      })
      .setInteractive({ useHandCursor: true })
      .on('pointerdown', () => this.callbacks.onBuyBoost());

    this.container.add(boostBtn);

    const friendBtn = scene.add
      .text(-120, -10, 'Spawn Friend â€” 15c', {
        fontFamily: font,
        fontSize: '14px',
        color: '#e6f5df',
      })
      .setInteractive({ useHandCursor: true })
      .on('pointerdown', () => this.callbacks.onBuyFriend());

    this.container.add(friendBtn);

    const closeBtn = scene.add
      .text(-36, 56, 'Close', {
        fontFamily: font,
        fontSize: '14px',
        color: '#ffd277',
      })
      .setInteractive({ useHandCursor: true })
      .on('pointerdown', () => this.hide());

    this.container.add(closeBtn);

    this.container.setScrollFactor(0);
    this.container.setDepth(resolveScreenUiDepth(40));
    this.container.setVisible(false);
  }

  show(_coins: number): void {
    this.container.setVisible(true);
    this.visible = true;
  }

  hide(): void {
    this.container.setVisible(false);
    this.visible = false;
  }

  isOpen(): boolean {
    return this.visible;
  }

  setPosition(x: number, y: number): void {
    this.container.setPosition(x, y);
  }

  destroy(): void {
    this.container.destroy();
  }
}
