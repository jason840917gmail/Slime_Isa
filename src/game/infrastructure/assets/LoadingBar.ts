import type Phaser from 'phaser';

/** A centred progress bar for the boot and map loading screens. */
export interface LoadingBar {
  /** 0..1 */
  setProgress(value: number): void;
  destroy(): void;
}

const WIDTH = 360;
const HEIGHT = 16;
const TRACK = 0x1c2b33;
const FILL = 0x86f0c3;
const EDGE = 0x3f6b5c;

export function createLoadingBar(scene: Phaser.Scene, label: string): LoadingBar {
  const camera = scene.cameras.main;
  const x = camera.centerX - WIDTH / 2;
  const y = camera.centerY - HEIGHT / 2;
  const text = scene.add.text(camera.centerX, y - 22, label, {
    fontFamily: 'Trebuchet MS, Segoe UI Variable, sans-serif',
    fontSize: '18px',
    color: '#d8fbff',
  }).setOrigin(0.5).setScrollFactor(0);
  const percent = scene.add.text(camera.centerX, y + HEIGHT + 16, '0%', {
    fontFamily: 'Trebuchet MS, Segoe UI Variable, sans-serif',
    fontSize: '13px',
    color: '#9fc9bb',
  }).setOrigin(0.5).setScrollFactor(0);
  const graphics = scene.add.graphics().setScrollFactor(0);
  const draw = (value: number) => {
    const clamped = Math.max(0, Math.min(1, value));
    graphics.clear();
    graphics.fillStyle(TRACK, 1).fillRoundedRect(x, y, WIDTH, HEIGHT, HEIGHT / 2);
    if (clamped > 0) graphics.fillStyle(FILL, 1).fillRoundedRect(x, y, Math.max(HEIGHT, WIDTH * clamped), HEIGHT, HEIGHT / 2);
    graphics.lineStyle(2, EDGE, 1).strokeRoundedRect(x, y, WIDTH, HEIGHT, HEIGHT / 2);
    percent.setText(`${Math.round(clamped * 100)}%`);
  };
  draw(0);
  return {
    setProgress: draw,
    destroy: () => {
      graphics.destroy();
      text.destroy();
      percent.destroy();
    },
  };
}
