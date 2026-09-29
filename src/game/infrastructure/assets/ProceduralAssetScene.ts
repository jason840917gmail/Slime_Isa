import Phaser from 'phaser';
import proceduralWeaponIcons from '../../content/weapons/procedural-weapon-icons.json';
import { assertAssetBundleTextures, loadAssetBundle } from './AssetLoader';

export class ProceduralAssetScene extends Phaser.Scene {
  /**
   * @param nextSceneKey Scene started once boot textures exist. Embedded hosts
   * (Scene Studio preview) pass their own scene; the game uses map routing.
   */
  constructor(private readonly nextSceneKey?: string) {
    super('boot');
  }

  preload(): void {
    loadAssetBundle(this, 'boot');
    loadAssetBundle(this, 'interiors');
    loadAssetBundle(this, 'audio');
    loadAssetBundle(this, 'music');
  }

  create(): void {
    this.createProceduralTextures();
    assertAssetBundleTextures(this, 'boot');
    assertAssetBundleTextures(this, 'interiors');
    assertAssetBundleTextures(this, 'audio');
    assertAssetBundleTextures(this, 'music');
    if (this.nextSceneKey) {
      this.scene.start(this.nextSceneKey);
      return;
    }
    const editorMapId = import.meta.env.DEV
      ? new URLSearchParams(window.location.search).get('editor')
      : null;
    this.scene.start(editorMapId ? 'map-editor-load' : 'map-load');
  }

  private createProceduralTextures(): void {
    const graphics = this.add.graphics();

    graphics.fillStyle(0x8ca76a, 1);
    graphics.fillRoundedRect(0, 0, 32, 18, 9);
    graphics.fillStyle(0x6f8452, 1);
    graphics.fillRoundedRect(4, 4, 24, 10, 6);
    graphics.generateTexture('stone', 32, 18);
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
    graphics.generateTexture(proceduralWeaponIcons.gauntlet, 32, 32);
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
    graphics.generateTexture(proceduralWeaponIcons.generic, 32, 32);
    graphics.clear();

    // Splat Spear â€” brown shaft + tip
    graphics.fillStyle(0x8b5a3c, 1);
    graphics.fillRect(14, 6, 4, 18);
    graphics.fillStyle(0xc0c0c0, 1);
    graphics.fillTriangle(16, 2, 20, 8, 12, 8);
    graphics.generateTexture(proceduralWeaponIcons.spear, 32, 32);
    graphics.clear();

    // Slam Hammer â€” big head + handle
    graphics.fillStyle(0x4a4a4a, 1);
    graphics.fillRect(8, 6, 16, 10);
    graphics.fillStyle(0x6a6a6a, 1);
    graphics.fillRect(10, 8, 12, 6);
    graphics.fillStyle(0x8b5a3c, 1);
    graphics.fillRect(14, 16, 4, 12);
    graphics.generateTexture(proceduralWeaponIcons.hammer, 32, 32);
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
