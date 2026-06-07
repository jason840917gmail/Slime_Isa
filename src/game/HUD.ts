import Phaser from 'phaser';

export class HUD {
  private coinsText: Phaser.GameObjects.Text;
  private friendCountText: Phaser.GameObjects.Text;

  constructor(scene: Phaser.Scene, coins: number, friendCount: number) {
    const font = 'Aptos, Segoe UI Variable, sans-serif';

    this.coinsText = scene.add
      .text(24, 140, `Coins: ${coins}`, {
        fontFamily: font,
        fontSize: '16px',
        color: '#ffd86b',
        stroke: '#163033',
        strokeThickness: 4,
      })
      .setScrollFactor(0)
      .setDepth(50) as Phaser.GameObjects.Text;

    this.friendCountText = scene.add
      .text(24, 168, `Friends: ${friendCount}`, {
        fontFamily: font,
        fontSize: '16px',
        color: '#ffd86b',
        stroke: '#163033',
        strokeThickness: 4,
      })
      .setScrollFactor(0)
      .setDepth(50) as Phaser.GameObjects.Text;
  }

  updateCoins(coins: number): void {
    this.coinsText.setText(`Coins: ${coins}`);
  }

  updateFriendCount(count: number): void {
    this.friendCountText.setText(`Friends: ${count}`);
  }

  flashCoins(scene: Phaser.Scene): void {
    scene.tweens.add({ targets: this.coinsText, scale: 1.08, duration: 120, yoyo: true });
  }

  destroy(): void {
    this.coinsText.destroy();
    this.friendCountText.destroy();
  }
}