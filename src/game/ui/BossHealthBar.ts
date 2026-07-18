import Phaser from 'phaser';
import type { Enemy } from '../enemies/Enemy';

const FONT = 'Aptos, Segoe UI Variable, sans-serif';

export class BossHealthBar {
  private scene: Phaser.Scene;
  private boss: Enemy;
  private container: Phaser.GameObjects.Container;
  private fill: Phaser.GameObjects.Rectangle;
  private hpText: Phaser.GameObjects.Text;

  constructor(scene: Phaser.Scene, boss: Enemy, name: string) {
    this.scene = scene;
    this.boss = boss;

    const cam = scene.cameras.main;
    this.container = scene.add.container(cam.width / 2, cam.height - 74).setScrollFactor(0).setDepth(220);

    const width = 520;
    const bg = scene.add.graphics();
    bg.fillStyle(0x071612, 0.94);
    bg.fillRoundedRect(-width / 2 - 14, -28, width + 28, 56, 12);
    bg.lineStyle(2, 0x8b2f2f, 0.9);
    bg.strokeRoundedRect(-width / 2 - 14, -28, width + 28, 56, 12);
    this.container.add(bg);

    this.container.add(scene.add.text(-width / 2, -17, name, {
      fontFamily: FONT,
      fontSize: '16px',
      color: '#ffe0d0',
      stroke: '#1f0808',
      strokeThickness: 4,
    }).setOrigin(0, 0.5));

    this.container.add(scene.add.rectangle(0, 9, width, 14, 0x240909, 1).setOrigin(0.5));
    this.fill = scene.add.rectangle(-width / 2, 9, width, 14, 0xff5a5a, 1).setOrigin(0, 0.5);
    this.container.add(this.fill);

    this.hpText = scene.add.text(width / 2, -17, '', {
      fontFamily: FONT,
      fontSize: '12px',
      color: '#ffd0c0',
    }).setOrigin(1, 0.5);
    this.container.add(this.hpText);

    scene.tweens.add({ targets: this.container, y: { from: cam.height - 40, to: cam.height - 74 }, alpha: { from: 0, to: 1 }, duration: 260, ease: 'Cubic.Out' });
    this.update();
  }

  update(): void {
    if (!this.boss.active && !this.boss.dead) return;
    const pct = this.boss.maxHp > 0 ? Phaser.Math.Clamp(this.boss.hp / this.boss.maxHp, 0, 1) : 0;
    this.fill.width = 520 * pct;
    this.fill.fillColor = pct <= 0.25 ? 0xff3030 : pct <= 0.5 ? 0xff8a3c : 0xff5a5a;
    this.hpText.setText(`${Math.max(0, this.boss.hp)} / ${this.boss.maxHp}`);
  }

  defeat(): void {
    this.scene.tweens.add({
      targets: this.container,
      alpha: 0,
      y: this.scene.cameras.main.height - 40,
      duration: 500,
      ease: 'Cubic.In',
      onComplete: () => this.destroy(),
    });
  }

  destroy(): void {
    this.container.destroy();
  }
}
