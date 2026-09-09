import Phaser from 'phaser';
import type { WorldDimensions } from './world/WorldDimensions';
import { resolveScreenUiDepth } from './presentation/WorldDepth';
import { createUiSkinImage } from './presentation/UiSkin';

const MINIMAP_SIZE = 180;
const MINIMAP_MARGIN = 16;
const MINIMAP_TINT_ALPHA = 0.16;

export class Minimap {
  private graphics: Phaser.GameObjects.Graphics;
  private readonly frame?: Phaser.GameObjects.Image;
  private size = MINIMAP_SIZE;

  constructor(
    scene: Phaser.Scene,
    private readonly dimensions: WorldDimensions,
  ) {
    this.graphics = scene.add.graphics();
    this.graphics.setScrollFactor(0);
    this.graphics.setDepth(resolveScreenUiDepth(30));
    this.frame = createUiSkinImage(scene, 'ui.frame.organic-minimap', {
      x: 0,
      y: 0,
      width: MINIMAP_SIZE + 12,
      height: MINIMAP_SIZE + 12,
    });
    this.frame?.setScrollFactor(0).setDepth(resolveScreenUiDepth(29));
  }

  update(
    camera: Phaser.Cameras.Scene2D.Camera,
    player: Phaser.Physics.Arcade.Sprite | undefined,
    friends: Phaser.Physics.Arcade.Group | undefined,
    houses: ReadonlyArray<{ owner: 'player' | 'friend'; house: { sprite: { x: number; y: number } } }> | undefined,
  ): void {
    const g = this.graphics;
    g.clear();

    const viewW = camera.width / camera.zoom;
    const viewH = camera.height / camera.zoom;
    const viewportShortSide = Math.min(camera.width, camera.height);
    this.size = Phaser.Math.Clamp(viewportShortSide * 0.24, 128, MINIMAP_SIZE);
    const margin = Phaser.Math.Clamp(viewportShortSide * 0.025, 12, MINIMAP_MARGIN);
    const baseX = margin;
    const baseY = camera.height - margin - this.size;
    const pad = Phaser.Math.Clamp(this.size * 0.033, 4, 6);

    this.frame
      ?.setPosition(baseX + this.size / 2, baseY + this.size / 2)
      .setDisplaySize(this.size + pad * 2, this.size + pad * 2);

    // Transparent code-drawn fallback when the illustrated frame is unavailable.
    if (!this.frame) {
      g.lineStyle(1.5, 0x9be8b8, 0.72);
      g.strokeRoundedRect(
        baseX - pad + 0.75,
        baseY - pad + 0.75,
        this.size + pad * 2 - 1.5,
        this.size + pad * 2 - 1.5,
        8,
      );
    }

    // A soft tint keeps markers legible without hiding the world behind the map.
    g.fillStyle(0x182b46, MINIMAP_TINT_ALPHA);
    g.fillRect(baseX, baseY, this.size, this.size);
    g.lineStyle(1, 0xb9efca, 0.42);
    g.strokeRect(baseX + 0.5, baseY + 0.5, this.size - 1, this.size - 1);

    const toMinimap = (wx: number, wy: number) => ({
      mx: baseX + (wx / this.dimensions.width) * this.size,
      my: baseY + (wy / this.dimensions.height) * this.size,
    });

    // Friend dots
    if (friends) {
      const children = friends.getChildren() as Phaser.GameObjects.GameObject[];
      for (const c of children) {
        const fx = (c as any).x as number;
        const fy = (c as any).y as number;
        const p = toMinimap(fx, fy);
        this.drawMarker(g, p.mx, p.my, 3, 0xffb347);
      }
    }

    // Player dot
    if (player) {
      const p = toMinimap(player.x, player.y);
      this.drawMarker(g, p.mx, p.my, 4, 0x72d8ff);
    }

    // House dots (colored to match the house textures)
    if (houses) {
      for (const entry of houses) {
        const p = toMinimap(entry.house.sprite.x, entry.house.sprite.y);
        if (entry.owner === 'player') {
          this.drawMarker(g, p.mx, p.my, 4, 0x2b69d1);
        } else {
          this.drawMarker(g, p.mx, p.my, 3, 0x9a6a3a);
        }
      }
    }

    // Camera view rectangle
    const topLeft = toMinimap(camera.scrollX, camera.scrollY);
    const bottomRight = toMinimap(camera.scrollX + viewW, camera.scrollY + viewH);
    g.lineStyle(1.5, 0x88c899, 0.95);
    g.strokeRect(
      topLeft.mx,
      topLeft.my,
      Math.max(2, bottomRight.mx - topLeft.mx),
      Math.max(2, bottomRight.my - topLeft.my),
    );
  }

  private drawMarker(
    g: Phaser.GameObjects.Graphics,
    x: number,
    y: number,
    radius: number,
    color: number,
  ): void {
    g.fillStyle(0x081022, 0.88);
    g.fillCircle(x, y, radius + 1.25);
    g.fillStyle(color, 1);
    g.fillCircle(x, y, radius);
  }

  destroy(): void {
    this.graphics.destroy();
    this.frame?.destroy();
  }
}
