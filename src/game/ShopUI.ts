import Phaser from 'phaser';

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
    bg.fillStyle(0x071612, 0.92);
    bg.fillRoundedRect(-140, -90, 280, 180, 10);
    bg.lineStyle(2, 0x335c45, 0.6);
    bg.strokeRoundedRect(-140, -90, 280, 180, 10);

    this.container = scene.add.container(x, y);
    this.container.add(bg);

    const font = 'Aptos, Segoe UI Variable, sans-serif';

    this.container.add(
      scene.add
        .text(-120, -78, 'Mini Shop', {
          fontFamily: font,
          fontSize: '18px',
          color: '#ccebd0',
        })
        .setDepth(60),
    );

    const boostBtn = scene.add
      .text(-120, 20, 'Boost +50 speed — 25c', {
        fontFamily: font,
        fontSize: '14px',
        color: '#e6f5df',
      })
      .setInteractive({ useHandCursor: true })
      .on('pointerdown', () => this.callbacks.onBuyBoost());

    this.container.add(boostBtn);

    const friendBtn = scene.add
      .text(-120, -10, 'Spawn Friend — 15c', {
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
        color: '#ffd86b',
      })
      .setInteractive({ useHandCursor: true })
      .on('pointerdown', () => this.hide());

    this.container.add(closeBtn);

    this.container.setScrollFactor(0);
    this.container.setDepth(60);
    this.container.setVisible(false);
  }

  show(coins: number): void {
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