import Phaser from 'phaser';
import { resolveScreenUiDepth } from '../presentation/WorldDepth';

const FONT = 'Trebuchet MS, Segoe UI Variable, sans-serif';

export function showAreaTitleCard(scene: Phaser.Scene, title: string, color: string): void {
  const cam = scene.cameras.main;
  const container = scene.add.container(cam.width / 2, 86).setScrollFactor(0).setDepth(resolveScreenUiDepth(80)).setAlpha(0);

  const bg = scene.add.graphics();
  bg.fillStyle(0x101a31, 0.86);
  bg.fillRoundedRect(-170, -24, 340, 48, 12);
  bg.lineStyle(2, 0x73e2b1, 0.75);
  bg.strokeRoundedRect(-170, -24, 340, 48, 12);
  container.add(bg);

  container.add(
    scene.add.text(0, 0, title, {
      fontFamily: FONT,
      fontSize: '22px',
      color,
      stroke: '#0b1020',
      strokeThickness: 5,
    }).setOrigin(0.5),
  );

  scene.tweens.add({
    targets: container,
    y: 104,
    alpha: 1,
    duration: 320,
    ease: 'Cubic.Out',
    yoyo: true,
    hold: 1200,
    onComplete: () => container.destroy(),
  });
}
