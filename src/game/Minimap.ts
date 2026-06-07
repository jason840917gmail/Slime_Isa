import Phaser from 'phaser';
import { WORLD_WIDTH, WORLD_HEIGHT } from './terrainNoise';

const MINIMAP_SIZE = 180;
const MINIMAP_MARGIN = 16;

export class Minimap {
  private graphics: Phaser.GameObjects.Graphics;
  private size = MINIMAP_SIZE;

  constructor(scene: Phaser.Scene) {
    this.graphics = scene.add.graphics();
    this.graphics.setScrollFactor(0);
    this.graphics.setDepth(80);
  }

  update(
    camera: Phaser.Cameras.Scene2D.Camera,
    player: Phaser.Physics.Arcade.Sprite | undefined,
    friends: Phaser.Physics.Arcade.Group | undefined,
  ): void {
    const g = this.graphics;
    g.clear();

    const viewW = camera.width / camera.zoom;
    const viewH = camera.height / camera.zoom;
    const baseX = MINIMAP_MARGIN;
    const baseY = camera.height - MINIMAP_MARGIN - this.size;

    // Background with bright border
    const pad = 6;
    g.fillStyle(0x0a1f15, 0.95);
    g.fillRoundedRect(
      baseX - pad,
      baseY - pad,
      this.size + pad * 2,
      this.size + pad * 2,
      8,
    );
    g.lineStyle(3, 0x44cc88, 1);
    g.strokeRoundedRect(
      baseX - pad,
      baseY - pad,
      this.size + pad * 2,
      this.size + pad * 2,
      8,
    );

    // Inner map area
    g.fillStyle(0x122a1e, 0.85);
    g.fillRect(baseX, baseY, this.size, this.size);

    const toMinimap = (wx: number, wy: number) => ({
      mx: baseX + (wx / WORLD_WIDTH) * this.size,
      my: baseY + (wy / WORLD_HEIGHT) * this.size,
    });

    // Friend dots
    if (friends) {
      const children = friends.getChildren() as Phaser.GameObjects.GameObject[];
      for (const c of children) {
        const fx = (c as any).x as number;
        const fy = (c as any).y as number;
        const p = toMinimap(fx, fy);
        g.fillStyle(0xffb347, 1);
        g.fillCircle(p.mx, p.my, 3);
      }
    }

    // Player dot
    if (player) {
      const p = toMinimap(player.x, player.y);
      g.fillStyle(0x6be0ff, 1);
      g.fillCircle(p.mx, p.my, 4);
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

  destroy(): void {
    this.graphics.destroy();
  }
}
