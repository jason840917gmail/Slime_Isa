import Phaser from 'phaser';
import { gameEvents } from '../core/EventBus';
import { gameState } from '../core/GameState';

/**
 * World-space health bar that floats above a target sprite (the player).
 * Auto-hides when full HP and not recently damaged, fades back in on hit.
 */
export class HealthBar {
  private scene: Phaser.Scene;
  private target: Phaser.Physics.Arcade.Sprite;
  private graphics: Phaser.GameObjects.Graphics;
  private offsetY: number;
  private visibleTimer = 0;
  private readonly showMs = 1800;

  constructor(scene: Phaser.Scene, target: Phaser.Physics.Arcade.Sprite, offsetY = -48) {
    this.scene = scene;
    this.target = target;
    this.offsetY = offsetY;
    this.graphics = scene.add.graphics().setDepth(40);

    gameEvents.on('hp.changed', this.onChange, this);
    this.draw();
  }

  flash(): void {
    this.visibleTimer = this.scene.time.now + this.showMs;
    this.draw();
  }

  update(): void {
    this.graphics.clear();
    if (this.scene.time.now > this.visibleTimer) return;
    if (gameState.isDead()) return;
    this.draw();
  }

  private onChange = (): void => {
    this.visibleTimer = this.scene.time.now + this.showMs;
  };

  private draw(): void {
    const g = this.graphics;
    const x = this.target.x - 22;
    const y = this.target.y + this.offsetY;
    const w = 44;
    const h = 6;

    g.fillStyle(0x0a1f15, 0.85);
    g.fillRoundedRect(x, y, w, h, 3);
    g.lineStyle(1, 0x2b4f57, 0.8);
    g.strokeRoundedRect(x, y, w, h, 3);

    const pct = gameState.maxHp > 0 ? Phaser.Math.Clamp(gameState.hp / gameState.maxHp, 0, 1) : 0;
    const fill = pct <= 0.25 ? 0xff5a5a : pct <= 0.5 ? 0xff9a3c : 0x7be08a;
    g.fillStyle(fill, 1);
    g.fillRoundedRect(x + 1, y + 1, Math.max(0, (w - 2) * pct), h - 2, 2);
  }

  destroy(): void {
    gameEvents.off('hp.changed', this.onChange, this);
    this.graphics.destroy();
  }
}
