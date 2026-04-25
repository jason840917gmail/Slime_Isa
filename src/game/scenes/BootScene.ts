import Phaser from 'phaser';

/** Each cell on the normalised sheet is 256 × 256 px, 8 columns × 8 rows. */
const CELL_SIZE = 256;

const slimeSheetUrl = new URL('../../../asset/slime_normalized.png', import.meta.url).href;

export class BootScene extends Phaser.Scene {
  constructor() {
    super('boot');
  }

  preload(): void {
    this.load.spritesheet('slime', slimeSheetUrl, {
      frameWidth: CELL_SIZE,
      frameHeight: CELL_SIZE,
    });
  }

  create(): void {
    this.createTerrainTextures();
    this.scene.start('world');
  }

  private createTerrainTextures(): void {
    const graphics = this.add.graphics();

    graphics.fillStyle(0x457d46, 1);
    graphics.fillRect(0, 0, 64, 64);
    graphics.fillStyle(0x508c4f, 1);
    graphics.fillCircle(16, 16, 12);
    graphics.fillCircle(44, 22, 10);
    graphics.fillCircle(32, 46, 14);
    graphics.generateTexture('grass-a', 64, 64);
    graphics.clear();

    graphics.fillStyle(0x4b844b, 1);
    graphics.fillRect(0, 0, 64, 64);
    graphics.fillStyle(0x5ea45f, 1);
    graphics.fillCircle(20, 20, 9);
    graphics.fillCircle(46, 18, 13);
    graphics.fillCircle(38, 44, 11);
    graphics.fillStyle(0x73ba6d, 0.7);
    graphics.fillCircle(10, 48, 8);
    graphics.generateTexture('grass-b', 64, 64);
    graphics.clear();

    graphics.fillStyle(0x2b4f57, 1);
    graphics.fillRect(0, 0, 64, 64);
    graphics.fillStyle(0x3d7280, 0.8);
    graphics.fillEllipse(22, 26, 28, 18);
    graphics.fillEllipse(45, 42, 24, 16);
    graphics.generateTexture('water', 64, 64);
    graphics.clear();

    graphics.fillStyle(0x3f4844, 1);
    graphics.fillRect(0, 0, 64, 64);
    graphics.fillStyle(0x57645e, 1);
    graphics.fillRoundedRect(4, 6, 56, 52, 18);
    graphics.fillStyle(0x70807a, 1);
    graphics.fillRoundedRect(10, 10, 20, 18, 8);
    graphics.fillRoundedRect(34, 14, 18, 16, 7);
    graphics.fillRoundedRect(18, 32, 28, 18, 9);
    graphics.fillStyle(0x7bb26d, 0.9);
    graphics.fillEllipse(18, 20, 12, 8);
    graphics.fillEllipse(43, 36, 14, 9);
    graphics.generateTexture('rock-wall', 64, 64);
    graphics.clear();

    graphics.fillStyle(0x95d66a, 1);
    graphics.fillCircle(8, 8, 6);
    graphics.fillStyle(0xffd36a, 1);
    graphics.fillCircle(8, 8, 2);
    graphics.generateTexture('flower', 16, 16);
    graphics.clear();

    graphics.fillStyle(0x8ca76a, 1);
    graphics.fillRoundedRect(0, 0, 32, 18, 9);
    graphics.fillStyle(0x6f8452, 1);
    graphics.fillRoundedRect(4, 4, 24, 10, 6);
    graphics.generateTexture('stone', 32, 18);
    graphics.destroy();
  }
}