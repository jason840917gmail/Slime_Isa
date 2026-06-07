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

    // Purple edible berry texture (collected by player)
    graphics.fillStyle(0x8e44ad, 1);
    graphics.fillCircle(8, 8, 6);
    graphics.fillStyle(0xffffff, 0.65);
    graphics.fillCircle(6, 6, 2);
    graphics.generateTexture('purple-berry', 16, 16);
    graphics.clear();

    // Big blue house texture (larger decorative house for player)
    graphics.fillStyle(0x2b69d1, 1);
    graphics.fillRoundedRect(0, 28, 128, 80, 10);
    graphics.fillStyle(0x1f4ea0, 1);
    graphics.fillTriangle(0, 28, 64, 0, 128, 28);
    // door
    graphics.fillStyle(0x5c3d2e, 1);
    graphics.fillRect(56, 72, 16, 36);
    // windows
    graphics.fillStyle(0xfff1b8, 1);
    graphics.fillRoundedRect(24, 48, 20, 16, 4);
    graphics.fillRoundedRect(84, 48, 20, 16, 4);
    graphics.generateTexture('big-blue-house', 128, 128);
    graphics.clear();

    // Smaller house texture used for friend homes.
    graphics.fillStyle(0x9a6a3a, 1);
    graphics.fillRoundedRect(4, 24, 56, 36, 8);
    graphics.fillStyle(0x6f3f25, 1);
    graphics.fillTriangle(0, 26, 32, 4, 64, 26);
    graphics.fillStyle(0x4a2b1d, 1);
    graphics.fillRect(27, 40, 10, 20);
    graphics.fillStyle(0xffe4a3, 1);
    graphics.fillRoundedRect(12, 34, 10, 9, 3);
    graphics.fillRoundedRect(42, 34, 10, 9, 3);
    graphics.generateTexture('house', 64, 64);
    graphics.clear();

    // Bed texture
    graphics.fillStyle(0x2b69d1, 1);
    graphics.fillRoundedRect(0, 0, 48, 20, 6);
    graphics.fillStyle(0xffffff, 0.9);
    graphics.fillRect(4, 4, 16, 12);
    graphics.generateTexture('bed', 48, 20);
    graphics.clear();

    graphics.fillStyle(0x8ca76a, 1);
    graphics.fillRoundedRect(0, 0, 32, 18, 9);
    graphics.fillStyle(0x6f8452, 1);
    graphics.fillRoundedRect(4, 4, 24, 10, 6);
    graphics.generateTexture('stone', 32, 18);
    graphics.clear();

    // Friend face variants (multiple expressions)
    const faceCount = 4;
    for (let f = 0; f < faceCount; f += 1) {
      graphics.clear();
      // base head
      graphics.fillStyle(0xffc86b, 1);
      graphics.fillCircle(12, 12, 10);

      // eyes / mouth variants
      graphics.fillStyle(0x2b2b2b, 1);

      if (f === 0) {
        // neutral
        graphics.fillCircle(9, 11, 2);
        graphics.fillCircle(15, 11, 2);
        graphics.fillRect(11, 15, 2, 1);
      } else if (f === 1) {
        // happy
        graphics.fillCircle(8, 11, 2);
        graphics.fillCircle(16, 11, 2);
        graphics.fillRect(9, 15, 6, 2);
      } else if (f === 2) {
        // wink
        graphics.fillRect(7, 11, 4, 2);
        graphics.fillCircle(16, 11, 2);
        graphics.fillRect(10, 15, 4, 1);
      } else {
        // surprised
        graphics.fillCircle(9, 11, 2);
        graphics.fillCircle(15, 11, 2);
        graphics.fillStyle(0xff6b6b, 1);
        graphics.fillCircle(12, 15, 2);
      }

      graphics.generateTexture(`friend-face-${f}`, 24, 24);
    }

    // Ear variants (animal ears)
    const earTypes = ['cat', 'bunny', 'dog', 'fox'];
    for (const t of earTypes) {
      graphics.clear();

      if (t === 'cat' || t === 'fox') {
        // pointy ears (two triangles)
        graphics.fillStyle(0xffc86b, 1);
        graphics.fillTriangle(4, 10, 12, 0, 20, 10);
        graphics.fillTriangle(20, 10, 12, 0, 4, 10);
        if (t === 'fox') {
          graphics.fillStyle(0xffffff, 0.9);
          graphics.fillTriangle(7, 8, 12, 2, 11, 8);
          graphics.fillTriangle(17, 8, 12, 2, 13, 8);
        } else {
          graphics.fillStyle(0xff9f9f, 0.7);
          graphics.fillTriangle(7, 8, 12, 2, 11, 8);
          graphics.fillTriangle(17, 8, 12, 2, 13, 8);
        }
      } else if (t === 'bunny') {
        // long rounded ears
        graphics.fillStyle(0xffc86b, 1);
        graphics.fillRoundedRect(4, 0, 6, 18, 4);
        graphics.fillRoundedRect(14, 0, 6, 18, 4);
        graphics.fillStyle(0xffffff, 0.9);
        graphics.fillRoundedRect(6, 2, 4, 14, 3);
        graphics.fillRoundedRect(16, 2, 4, 14, 3);
      } else if (t === 'dog') {
        // floppy ears as ellipses
        graphics.fillStyle(0xffc86b, 1);
        graphics.fillEllipse(6, 12, 10, 14);
        graphics.fillEllipse(18, 12, 10, 14);
        graphics.fillStyle(0x8b5a3c, 0.6);
        graphics.fillEllipse(6, 14, 6, 10);
        graphics.fillEllipse(18, 14, 6, 10);
      }

      graphics.generateTexture(`friend-ear-${t}`, 24, 24);
    }

    // keep an alias 'friend' referencing the neutral face
    graphics.clear();
    graphics.fillStyle(0xffc86b, 1);
    graphics.fillCircle(12, 12, 10);
    graphics.fillStyle(0x2b2b2b, 1);
    graphics.fillCircle(9, 11, 2);
    graphics.fillCircle(15, 11, 2);
    graphics.fillRect(11, 15, 2, 1);
    graphics.generateTexture('friend', 24, 24);
    
    // --- Player skin accessory textures ---
    // Helmet / cap (white shapes so player tint can recolor)
    graphics.clear();
    graphics.fillStyle(0xffffff, 1);
    graphics.fillRoundedRect(16, 36, 96, 44, 20);
    graphics.fillRect(28, 48, 72, 12);
    graphics.generateTexture('skin-helmet', 128, 128);
    graphics.clear();

    // Spots (random white spots) — will be tinted by player skin
    graphics.fillStyle(0xffffff, 1);
    for (let i = 0; i < 12; i += 1) {
      const x = Phaser.Math.Between(24, 104);
      const y = Phaser.Math.Between(36, 104);
      const r = Phaser.Math.Between(4, 10);
      graphics.fillCircle(x, y, r);
    }
    graphics.generateTexture('skin-spots', 128, 128);
    graphics.clear();

    // Stripe (horizontal band)
    graphics.fillStyle(0xffffff, 1);
    graphics.fillRect(0, 56, 128, 16);
    graphics.generateTexture('skin-stripe', 128, 128);
    graphics.clear();

    // Halo (outline circle over head)
    graphics.lineStyle(6, 0xffffff, 1);
    graphics.strokeCircle(64, 36, 28);
    graphics.generateTexture('skin-halo', 128, 128);

    graphics.destroy();
  }
}
