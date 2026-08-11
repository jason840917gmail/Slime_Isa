import Phaser from 'phaser';
import { assertAssetBundleTextures, loadAssetBundle } from './AssetLoader';

export class ProceduralAssetScene extends Phaser.Scene {
  constructor() {
    super('boot');
  }

  preload(): void {
    loadAssetBundle(this, 'boot');
  }

  create(): void {
    this.createTerrainTextures();
    assertAssetBundleTextures(this, 'boot');
    const editorMapId = import.meta.env.DEV
      ? new URLSearchParams(window.location.search).get('editor')
      : null;
    this.scene.start(editorMapId ? 'map-editor-load' : 'map-load');
  }

  private createTerrainTextures(): void {
    const graphics = this.add.graphics();

    // Gloop Forest tiles
    graphics.fillStyle(0x244d34, 1);
    graphics.fillRect(0, 0, 64, 64);
    graphics.fillStyle(0x2f6b42, 1);
    graphics.fillCircle(18, 18, 12);
    graphics.fillCircle(48, 38, 14);
    graphics.fillStyle(0x163320, 0.8);
    graphics.fillEllipse(34, 50, 28, 10);
    graphics.generateTexture('forest-floor', 64, 64);
    graphics.clear();

    graphics.fillStyle(0x1d422d, 1);
    graphics.fillRect(0, 0, 64, 64);
    graphics.fillStyle(0x3f8f52, 0.95);
    graphics.fillCircle(16, 44, 12);
    graphics.fillCircle(42, 18, 15);
    graphics.fillCircle(50, 50, 9);
    graphics.generateTexture('forest-moss', 64, 64);
    graphics.clear();

    graphics.fillStyle(0x15311f, 1);
    graphics.fillRect(0, 0, 64, 64);
    graphics.fillStyle(0x2b5a34, 1);
    graphics.fillRoundedRect(6, 4, 52, 56, 18);
    graphics.fillStyle(0x18351f, 1);
    graphics.fillRect(28, 22, 8, 34);
    graphics.fillStyle(0x4fa85e, 0.85);
    graphics.fillCircle(22, 20, 12);
    graphics.fillCircle(42, 22, 13);
    graphics.fillCircle(32, 12, 14);
    graphics.generateTexture('tree-wall', 64, 64);
    graphics.clear();

    // Crystal Caverns tiles
    graphics.fillStyle(0x25324a, 1);
    graphics.fillRect(0, 0, 64, 64);
    graphics.fillStyle(0x334766, 1);
    graphics.fillCircle(18, 18, 10);
    graphics.fillCircle(44, 42, 12);
    graphics.generateTexture('cavern-floor', 64, 64);
    graphics.clear();

    graphics.fillStyle(0x263c5d, 1);
    graphics.fillRect(0, 0, 64, 64);
    graphics.fillStyle(0x72d8ff, 0.55);
    graphics.fillTriangle(16, 48, 26, 14, 34, 48);
    graphics.fillTriangle(38, 52, 46, 24, 56, 52);
    graphics.fillStyle(0xffffff, 0.35);
    graphics.fillCircle(22, 28, 3);
    graphics.generateTexture('crystal-floor', 64, 64);
    graphics.clear();

    graphics.fillStyle(0x1c2638, 1);
    graphics.fillRect(0, 0, 64, 64);
    graphics.fillStyle(0x3c5578, 1);
    graphics.fillRoundedRect(5, 6, 54, 52, 12);
    graphics.fillStyle(0x8ce8ff, 0.8);
    graphics.fillTriangle(12, 50, 24, 12, 34, 50);
    graphics.fillTriangle(32, 54, 44, 18, 56, 54);
    graphics.generateTexture('crystal-wall', 64, 64);
    graphics.clear();

    // Meadow water remains procedural while meadow ground comes from the
    // Highland Green manifest spritesheet.
    for (const [key, baseColor, rippleColor] of [
      ['water', 0x2f7190, 0x62b7cf],
      ['water-1', 0x326d88, 0x70c1d6],
      ['water-2', 0x2a6782, 0x58a9c2],
    ] as const) {
      graphics.fillStyle(baseColor, 1);
      graphics.fillRect(0, 0, 64, 64);
      graphics.lineStyle(2, rippleColor, 0.65);
      graphics.beginPath();
      graphics.moveTo(8, 18);
      graphics.lineTo(24, 18);
      graphics.moveTo(34, 38);
      graphics.lineTo(56, 38);
      graphics.strokePath();
      graphics.generateTexture(key, 64, 64);
      graphics.clear();
    }

    graphics.fillStyle(0x172438, 1);
    graphics.fillRect(0, 0, 64, 64);
    graphics.fillStyle(0x223d5a, 0.9);
    graphics.fillEllipse(22, 26, 30, 18);
    graphics.fillEllipse(46, 42, 24, 16);
    graphics.generateTexture('deep-water', 64, 64);
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

    // Grape chip bag texture â€” small purple snack bag with crinkly top
    graphics.fillStyle(0x4a1f5e, 1);
    graphics.fillRoundedRect(2, 3, 12, 11, 1.5);
    // bag seal
    graphics.fillStyle(0x2c0e3a, 1);
    graphics.fillRect(2, 2, 12, 2);
    // diagonal crinkle marks
    graphics.lineStyle(1, 0x2c0e3a, 1);
    graphics.beginPath();
    graphics.moveTo(4, 3);
    graphics.lineTo(5, 4);
    graphics.moveTo(7, 3);
    graphics.lineTo(8, 4);
    graphics.moveTo(10, 3);
    graphics.lineTo(11, 4);
    graphics.strokePath();
    // grape graphic on bag
    graphics.fillStyle(0x8e44ad, 1);
    graphics.fillCircle(6, 9, 1.2);
    graphics.fillCircle(7.5, 9.5, 1.2);
    graphics.fillCircle(9, 9, 1.2);
    graphics.fillStyle(0x6c3483, 1);
    graphics.fillCircle(7, 7.5, 1);
    // highlight
    graphics.fillStyle(0xffffff, 0.35);
    graphics.fillRect(3, 5, 1.5, 5);
    graphics.generateTexture('grape-chip', 16, 16);
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

    // Spots (random white spots) â€” will be tinted by player skin
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
    graphics.clear();

    // â”€â”€ Phase 1: consumables, materials, XP orbs, perk icons â”€â”€

    // HP potion â€” small red vial with cork
    graphics.fillStyle(0x2b1a1a, 1);
    graphics.fillRoundedRect(3, 6, 10, 12, 2);
    graphics.fillStyle(0xff4d5a, 1);
    graphics.fillRoundedRect(4, 8, 8, 9, 2);
    graphics.fillStyle(0x8b5a3c, 1);
    graphics.fillRect(5, 4, 6, 3);
    graphics.fillStyle(0xffffff, 0.55);
    graphics.fillRect(5, 9, 2, 4);
    graphics.generateTexture('hp-potion', 16, 20);
    graphics.clear();

    // Energy potion â€” small yellow vial, fizzy bubbles
    graphics.fillStyle(0x2b2a1a, 1);
    graphics.fillRoundedRect(3, 6, 10, 12, 2);
    graphics.fillStyle(0xffdf8a, 1);
    graphics.fillRoundedRect(4, 8, 8, 9, 2);
    graphics.fillStyle(0x8b5a3c, 1);
    graphics.fillRect(5, 4, 6, 3);
    graphics.fillStyle(0xffffff, 0.7);
    graphics.fillCircle(6, 11, 1);
    graphics.fillCircle(9, 13, 1);
    graphics.fillCircle(7, 14, 0.8);
    graphics.generateTexture('energy-potion', 16, 20);
    graphics.clear();

    // Sticky silk clump â€” white-ish webby blob
    graphics.fillStyle(0xeaf4f0, 0.95);
    graphics.fillCircle(8, 8, 6);
    graphics.lineStyle(1, 0xb8c9c1, 0.9);
    graphics.beginPath();
    graphics.moveTo(2, 8); graphics.lineTo(14, 8);
    graphics.moveTo(8, 2); graphics.lineTo(8, 14);
    graphics.moveTo(4, 4); graphics.lineTo(12, 12);
    graphics.moveTo(12, 4); graphics.lineTo(4, 12);
    graphics.strokePath();
    graphics.generateTexture('silk-clump', 16, 16);
    graphics.clear();

    // Crystal shard â€” faceted cyan crystal
    graphics.fillStyle(0x72d8ff, 1);
    graphics.fillTriangle(8, 1, 14, 8, 8, 15);
    graphics.fillTriangle(8, 1, 2, 8, 8, 15);
    graphics.fillStyle(0xffffff, 0.55);
    graphics.fillTriangle(8, 1, 11, 6, 8, 8);
    graphics.generateTexture('shard', 16, 16);
    graphics.clear();

    // Crystal Caverns trial switch â€” dim and lit variants.
    graphics.fillStyle(0x16212f, 1);
    graphics.fillRoundedRect(2, 10, 28, 14, 5);
    graphics.lineStyle(2, 0x3f5870, 1);
    graphics.strokeRoundedRect(2, 10, 28, 14, 5);
    graphics.fillStyle(0x2c6f82, 0.8);
    graphics.fillCircle(16, 12, 5);
    graphics.generateTexture('crystal-switch-off', 32, 32);
    graphics.clear();

    graphics.fillStyle(0x183344, 1);
    graphics.fillRoundedRect(2, 12, 28, 12, 5);
    graphics.lineStyle(2, 0x9cf0ff, 1);
    graphics.strokeRoundedRect(2, 12, 28, 12, 5);
    graphics.fillStyle(0x9cf0ff, 1);
    graphics.fillCircle(16, 12, 6);
    graphics.fillStyle(0xffffff, 0.75);
    graphics.fillCircle(14, 10, 2);
    graphics.generateTexture('crystal-switch-on', 32, 32);
    graphics.clear();

    // Crystal trial chest â€” locked and opened reward state.
    graphics.fillStyle(0x1b2638, 1);
    graphics.fillRoundedRect(4, 16, 40, 24, 5);
    graphics.fillStyle(0x4d6f86, 1);
    graphics.fillRoundedRect(6, 10, 36, 16, 5);
    graphics.lineStyle(2, 0x9cf0ff, 0.9);
    graphics.strokeRoundedRect(4, 10, 40, 30, 5);
    graphics.fillStyle(0xffdf8a, 1);
    graphics.fillRoundedRect(21, 22, 6, 8, 2);
    graphics.generateTexture('crystal-chest-closed', 48, 48);
    graphics.clear();

    graphics.fillStyle(0x1b2638, 1);
    graphics.fillRoundedRect(4, 18, 40, 22, 5);
    graphics.fillStyle(0x4d6f86, 1);
    graphics.fillRoundedRect(6, 5, 36, 12, 5);
    graphics.lineStyle(2, 0x9cf0ff, 0.9);
    graphics.strokeRoundedRect(4, 5, 40, 35, 5);
    graphics.fillStyle(0xfff4a3, 0.85);
    graphics.fillTriangle(12, 20, 36, 20, 24, 34);
    graphics.generateTexture('crystal-chest-open', 48, 48);
    graphics.clear();

    // XP orb â€” glowing green orb with bright core
    graphics.fillStyle(0x1a3a24, 1);
    graphics.fillCircle(8, 8, 7);
    graphics.fillStyle(0x7be08a, 1);
    graphics.fillCircle(8, 8, 5);
    graphics.fillStyle(0xffffff, 0.85);
    graphics.fillCircle(7, 7, 2);
    graphics.generateTexture('xp-orb', 16, 16);
    graphics.clear();

    // Perk icons (32x32)
    graphics.fillStyle(0x7be08a, 1);
    graphics.fillCircle(16, 16, 12);
    graphics.fillStyle(0x0b1020, 1);
    graphics.fillRect(14, 8, 4, 16);
    graphics.generateTexture('perk-tanky', 32, 32);
    graphics.clear();

    graphics.fillStyle(0xff6f88, 1);
    graphics.fillTriangle(16, 4, 26, 24, 6, 24);
    graphics.fillStyle(0xffffff, 0.8);
    graphics.fillTriangle(16, 8, 22, 22, 10, 22);
    graphics.generateTexture('perk-fangs', 32, 32);
    graphics.clear();

    graphics.fillStyle(0x8b5a3c, 1);
    graphics.fillRoundedRect(6, 6, 20, 20, 6);
    graphics.fillStyle(0xc89878, 0.8);
    graphics.fillRoundedRect(9, 9, 14, 14, 4);
    graphics.generateTexture('perk-skin', 32, 32);
    graphics.clear();

    graphics.fillStyle(0x72d8ff, 1);
    graphics.fillCircle(16, 16, 11);
    graphics.fillStyle(0xffffff, 0.8);
    graphics.fillTriangle(16, 6, 22, 18, 10, 18);
    graphics.generateTexture('perk-quick', 32, 32);
    graphics.clear();

    graphics.fillStyle(0xffdf8a, 1);
    const starPoints: Phaser.Math.Vector2[] = [];
    for (let i = 0; i < 10; i += 1) {
      const r = i % 2 === 0 ? 12 : 5;
      const a = (-90 + i * 36) * (Math.PI / 180);
      starPoints.push(new Phaser.Math.Vector2(16 + Math.cos(a) * r, 16 + Math.sin(a) * r));
    }
    graphics.fillPoints(starPoints, true);
    graphics.generateTexture('perk-crit', 32, 32);
    graphics.clear();

    graphics.fillStyle(0xffad66, 1);
    graphics.fillRoundedRect(6, 10, 20, 14, 4);
    graphics.fillStyle(0x4a2a10, 1);
    graphics.fillRect(8, 14, 16, 2);
    graphics.fillRect(8, 18, 16, 2);
    graphics.generateTexture('perk-well', 32, 32);
    graphics.clear();

    // Quick Recovery â€” lightning bolt
    graphics.fillStyle(0xffdf8a, 1);
    graphics.fillTriangle(14, 4, 20, 14, 15, 14);
    graphics.fillTriangle(15, 14, 12, 28, 18, 16);
    graphics.generateTexture('perk-recovery', 32, 32);
    graphics.clear();

    // Vampiric Goo â€” red drop
    graphics.fillStyle(0xc8324a, 1);
    graphics.fillCircle(16, 19, 8);
    graphics.fillTriangle(16, 4, 8, 19, 24, 19);
    graphics.fillStyle(0xffffff, 0.55);
    graphics.fillCircle(13, 16, 2);
    graphics.generateTexture('perk-lifesteal', 32, 32);
    graphics.clear();

    // Default perk icon (fallback)
    graphics.fillStyle(0x88c899, 1);
    graphics.fillRoundedRect(6, 6, 20, 20, 6);
    graphics.fillStyle(0x0b1020, 1);
    graphics.fillCircle(16, 16, 4);
    graphics.generateTexture('perk-default', 32, 32);
    graphics.clear();

    // â”€â”€ Phase 2: weapon icons (32x32) â”€â”€

    // Goo Gauntlet â€” green slime fist
    graphics.fillStyle(0x86f0c3, 1);
    graphics.fillRoundedRect(8, 8, 16, 16, 4);
    graphics.fillStyle(0x4b844b, 1);
    graphics.fillRoundedRect(10, 10, 12, 12, 3);
    graphics.fillStyle(0xffffff, 0.4);
    graphics.fillCircle(13, 13, 2);
    graphics.generateTexture('weapon-gauntlet', 32, 32);
    graphics.clear();

    // Generic sword — used by authored sword weapons without a dedicated UI icon
    graphics.fillStyle(0xd9edf2, 1);
    graphics.fillTriangle(17, 3, 20, 17, 14, 17);
    graphics.fillStyle(0x7ea6b4, 1);
    graphics.fillRect(15, 16, 4, 8);
    graphics.fillStyle(0xffd277, 1);
    graphics.fillRect(10, 20, 14, 3);
    graphics.fillStyle(0x8b5a3c, 1);
    graphics.fillRect(15, 23, 4, 6);
    graphics.generateTexture('weapon-generic', 32, 32);
    graphics.clear();

    // Splat Spear â€” brown shaft + tip
    graphics.fillStyle(0x8b5a3c, 1);
    graphics.fillRect(14, 6, 4, 18);
    graphics.fillStyle(0xc0c0c0, 1);
    graphics.fillTriangle(16, 2, 20, 8, 12, 8);
    graphics.generateTexture('weapon-spear', 32, 32);
    graphics.clear();

    // Bouncy Bow â€” curved arc
    graphics.lineStyle(3, 0x8b5a3c, 1);
    graphics.beginPath();
    graphics.arc(16, 16, 10, -Math.PI / 3, Math.PI / 3, false);
    graphics.strokePath();
    graphics.lineStyle(1, 0xffdf8a, 1);
    graphics.beginPath();
    graphics.moveTo(21, 7);
    graphics.lineTo(21, 25);
    graphics.strokePath();
    graphics.generateTexture('weapon-bow', 32, 32);
    graphics.clear();

    // Sticky Whip â€” coiled line
    graphics.lineStyle(3, 0xeaf4f0, 1);
    graphics.beginPath();
    graphics.moveTo(6, 16);
    graphics.lineTo(12, 10);
    graphics.lineTo(18, 22);
    graphics.lineTo(24, 12);
    graphics.strokePath();
    graphics.generateTexture('weapon-whip', 32, 32);
    graphics.clear();

    // Bubble Wand â€” wand + bubble
    graphics.fillStyle(0x8b5a3c, 1);
    graphics.fillRect(14, 14, 4, 14);
    graphics.fillStyle(0x72d8ff, 0.6);
    graphics.fillCircle(16, 8, 6);
    graphics.fillStyle(0xffffff, 0.5);
    graphics.fillCircle(14, 6, 2);
    graphics.generateTexture('weapon-wand', 32, 32);
    graphics.clear();

    // Slam Hammer â€” big head + handle
    graphics.fillStyle(0x4a4a4a, 1);
    graphics.fillRect(8, 6, 16, 10);
    graphics.fillStyle(0x6a6a6a, 1);
    graphics.fillRect(10, 8, 12, 6);
    graphics.fillStyle(0x8b5a3c, 1);
    graphics.fillRect(14, 16, 4, 12);
    graphics.generateTexture('weapon-hammer', 32, 32);
    graphics.clear();

    // Target dummy texture (for combat practice)
    graphics.fillStyle(0x9a6a3a, 1);
    graphics.fillRoundedRect(8, 4, 16, 24, 4);
    graphics.fillStyle(0xffd277, 1);
    graphics.fillCircle(16, 12, 4);
    graphics.fillStyle(0x2b2b2b, 1);
    graphics.fillCircle(14, 11, 1);
    graphics.fillCircle(18, 11, 1);
    graphics.fillRect(14, 14, 4, 1);
    graphics.generateTexture('target-dummy', 32, 32);
    graphics.clear();

    graphics.destroy();
  }
}
