import Phaser from 'phaser';
import { resolveScreenUiDepth } from '../presentation/WorldDepth';
import { addUiSkin } from '../presentation/UiSkin';

const FONT = 'Trebuchet MS, Segoe UI Variable, sans-serif';

export function showAreaTitleCard(scene: Phaser.Scene, title: string, color: string): void {
  const cam = scene.cameras.main;
  const container = scene.add.container(cam.width / 2, 86).setScrollFactor(0).setDepth(resolveScreenUiDepth(80)).setAlpha(0);

  const bannerW = 380;
  const bannerH = 96;
  const skin = addUiSkin(scene, container, 'ui.banner.area-title', {
    x: 0,
    y: 0,
    width: bannerW,
    height: bannerH,
  });
  if (!skin) {
    const bg = scene.add.graphics();
    bg.fillStyle(0x101a31, 0.86);
    bg.fillRoundedRect(-bannerW / 2, -bannerH / 2, bannerW, bannerH, 12);
    bg.lineStyle(2, 0x73e2b1, 0.75);
    bg.strokeRoundedRect(-bannerW / 2, -bannerH / 2, bannerW, bannerH, 12);
    container.add(bg);
  }

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
