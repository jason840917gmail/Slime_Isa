import Phaser from 'phaser';
import proceduralWeaponIcons from '../../content/weapons/procedural-weapon-icons.json';
import { assertAssetBundleTextures, assertAssetsLoaded, loadAssetBundle, queueAssets } from './AssetLoader';
import { createLoadingBar } from './LoadingBar';
import { removeBootLoader } from '../../presentation/BootLoader';
import { bootImageAssetIds } from './WorldAssetSets';

export class ProceduralAssetScene extends Phaser.Scene {
  /**
   * @param nextSceneKey Scene started once boot textures exist. Embedded hosts
   * (Scene Studio preview) pass their own scene; the game uses map routing.
   */
  constructor(private readonly nextSceneKey?: string) {
    super('boot');
  }

  /** Embedded hosts (Scene Studio) load every image; the game leaves each world's own images to MapLoadScene. */
  private get loadsEverything(): boolean {
    return this.nextSceneKey !== undefined;
  }

  preload(): void {
    removeBootLoader();
    const bar = createLoadingBar(this, 'Loading Slime Isa…');
    this.load.on(Phaser.Loader.Events.PROGRESS, (value: number) => bar.setProgress(value));
    this.load.once(Phaser.Loader.Events.COMPLETE, () => bar.destroy());
    if (this.loadsEverything) {
      loadAssetBundle(this, 'boot');
      loadAssetBundle(this, 'interiors');
    } else {
      queueAssets(this, bootImageAssetIds());
    }
    loadAssetBundle(this, 'audio');
    loadAssetBundle(this, 'music');
  }

  create(): void {
    this.createProceduralTextures();
    if (this.loadsEverything) {
      assertAssetBundleTextures(this, 'boot');
      assertAssetBundleTextures(this, 'interiors');
    } else {
      assertAssetsLoaded(this, bootImageAssetIds(), 'Boot images');
    }
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

    // Goo dust: glowing green orb with a bright core (dodge and landing puffs)
    graphics.fillStyle(0x1a3a24, 1);
    graphics.fillCircle(8, 8, 7);
    graphics.fillStyle(0x7be08a, 1);
    graphics.fillCircle(8, 8, 5);
    graphics.fillStyle(0xffffff, 0.85);
    graphics.fillCircle(7, 7, 2);
    graphics.generateTexture('goo-dust', 16, 16);
    graphics.clear();

    // Dust puff: a soft sandy cloud (a building being restored)
    for (const [radius, alpha] of [[15, 0.18], [12, 0.28], [9, 0.4], [6, 0.5]] as const) {
      graphics.fillStyle(0xd9c8a4, alpha);
      graphics.fillCircle(16, 16, radius);
    }
    graphics.fillStyle(0xf3ead6, 0.45);
    graphics.fillCircle(13, 13, 4);
    graphics.generateTexture('dust-puff', 32, 32);
    graphics.clear();

    // Particle presets (roadmap 9.3): a hit spark, a goo droplet and a loot sparkle.
    graphics.fillStyle(0xfff2b8, 0.55);
    graphics.fillCircle(8, 8, 7);
    graphics.fillStyle(0xffffff, 1);
    graphics.fillCircle(8, 8, 3.5);
    graphics.generateTexture('fx-spark', 16, 16);
    graphics.clear();

    graphics.fillStyle(0x2f8f3a, 1);
    graphics.fillCircle(8, 9, 6);
    graphics.fillStyle(0x7be08a, 1);
    graphics.fillCircle(8, 8, 5);
    graphics.fillStyle(0xffffff, 0.8);
    graphics.fillCircle(6, 6, 1.6);
    graphics.generateTexture('fx-goo-drop', 16, 16);
    graphics.clear();

    graphics.fillStyle(0xffe89a, 1);
    graphics.fillTriangle(8, 0, 10, 8, 6, 8);
    graphics.fillTriangle(8, 16, 10, 8, 6, 8);
    graphics.fillTriangle(0, 8, 8, 6, 8, 10);
    graphics.fillTriangle(16, 8, 8, 6, 8, 10);
    graphics.fillStyle(0xffffff, 1);
    graphics.fillCircle(8, 8, 2);
    graphics.generateTexture('fx-sparkle', 16, 16);
    graphics.clear();

    // Slime trail mark (roadmap 9.4): a flat translucent goo smear.
    graphics.fillStyle(0x3f9a4a, 0.55);
    graphics.fillEllipse(14, 8, 26, 13);
    graphics.fillStyle(0x7be08a, 0.7);
    graphics.fillEllipse(13, 7, 18, 8);
    graphics.fillStyle(0xd8ffd8, 0.6);
    graphics.fillEllipse(10, 5, 6, 2.5);
    graphics.generateTexture('fx-goo-mark', 28, 16);
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
