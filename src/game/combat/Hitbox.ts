import Phaser from 'phaser';

/**
 * Pooled transient hitbox. A physics zone that appears at a position, deals
 * damage to overlapping targets, then despawns. Reused via pooling so heavy
 * combat doesn't create/destroy objects each swing.
 *
 * Damage application is delegated to a callback so the caller decides how to
 * process the hit (enemy vs friend vs boss).
 */

export interface HitboxConfig {
  /** World position. */
  x: number;
  y: number;
  /** Hitbox size. */
  width: number;
  height: number;
  /** Damage dealt on hit. */
  damage: number;
  /** How long the hitbox is active in ms. */
  durationMs: number;
  /** Knockback direction (normalized) + strength. */
  knockX?: number;
  knockY?: number;
  knockStrength?: number;
  /** Visual fill color for the debug/VFX rect. */
  vfxColor?: number;
  /** Show a visible slash rect (combat VFX). */
  showVfx?: boolean;
  /** Optional sector hit shape for crescent melee swings. */
  shape?: 'rect' | 'sector';
  originX?: number;
  originY?: number;
  angle?: number;
  arcWidth?: number;
  innerRadius?: number;
  outerRadius?: number;
  /** Unique set of target objects already hit (prevents multi-hit per swing). */
  hitSet?: Set<Phaser.GameObjects.GameObject>;
}

export type HitHandler = (
  target: Phaser.GameObjects.GameObject,
  damage: number,
  knockX: number,
  knockY: number,
  knockStrength: number,
) => void;

interface PooledHitbox {
  zone: Phaser.GameObjects.Zone;
  vfx: Phaser.GameObjects.Graphics;
  active: boolean;
  config: HitboxConfig | null;
  handler: HitHandler | null;
  hitSet: Set<Phaser.GameObjects.GameObject>;
  removeTimer: Phaser.Time.TimerEvent | null;
}

class HitboxPoolImpl {
  private pools = new Map<Phaser.Scene, PooledHitbox[]>();
  /** Active physics overlaps keyed by pool index. */
  private overlapClosures = new Map<PooledHitbox, (() => void) | null>();

  spawn(
    scene: Phaser.Scene,
    targets: Phaser.GameObjects.Group | Phaser.Physics.Arcade.Group | Phaser.Physics.Arcade.StaticGroup,
    config: HitboxConfig,
    handler: HitHandler,
  ): void {
    const pool = this.getPool(scene);
    let slot = pool.find((p) => !p.active);

    if (!slot) {
      slot = this.createSlot(scene, pool);
    }

    this.activate(scene, slot, targets, config, handler);
  }

  private getPool(scene: Phaser.Scene): PooledHitbox[] {
    let pool = this.pools.get(scene);
    if (!pool) {
      pool = [];
      this.pools.set(scene, pool);
    }
    return pool;
  }

  private createSlot(scene: Phaser.Scene, pool: PooledHitbox[]): PooledHitbox {
    const zone = scene.add.zone(0, 0, 1, 1);
    scene.physics.add.existing(zone, true);
    zone.setVisible(false);

    const vfx = scene.add.graphics().setDepth(45).setVisible(false);

    const slot: PooledHitbox = {
      zone,
      vfx,
      active: false,
      config: null,
      handler: null,
      hitSet: new Set(),
      removeTimer: null,
    };
    pool.push(slot);
    return slot;
  }

  private activate(
    scene: Phaser.Scene,
    slot: PooledHitbox,
    targets: Phaser.GameObjects.Group | Phaser.Physics.Arcade.Group | Phaser.Physics.Arcade.StaticGroup,
    config: HitboxConfig,
    handler: HitHandler,
  ): void {
    slot.active = true;
    slot.config = config;
    slot.handler = handler;
    slot.hitSet = config.hitSet ?? new Set();

    const body = slot.zone.body as Phaser.Physics.Arcade.StaticBody;
    body.setSize(config.width, config.height);
    body.updateFromGameObject();
    slot.zone.setPosition(config.x, config.y);
    body.x = config.x - config.width / 2;
    body.y = config.y - config.height / 2;
    slot.zone.setVisible(false);

    // VFX slash rect.
    if (config.showVfx ?? true) {
      const color = config.vfxColor ?? 0x88ffaa;
      slot.vfx.clear();
      slot.vfx.fillStyle(color, 0.35);
      slot.vfx.fillRoundedRect(
        config.x - config.width / 2,
        config.y - config.height / 2,
        config.width,
        config.height,
        6,
      );
      slot.vfx.lineStyle(2, color, 0.8);
      slot.vfx.strokeRoundedRect(
        config.x - config.width / 2,
        config.y - config.height / 2,
        config.width,
        config.height,
        6,
      );
      slot.vfx.setVisible(true);
      scene.tweens.add({
        targets: slot.vfx,
        alpha: { from: 1, to: 0 },
        duration: config.durationMs,
        ease: 'Quad.Out',
      });
    }

    // Overlap with targets.
    const overlapFn = () => {
      if (!slot.active || !slot.config || !slot.handler) return;
      const children = targets.getChildren();
      for (const child of children) {
        if (slot.hitSet.has(child)) continue;
        const childBody = (child as Phaser.Physics.Arcade.Sprite).body as Phaser.Physics.Arcade.Body | undefined;
        if (!childBody) continue;
        const hit = this.intersects(child as Phaser.Physics.Arcade.Sprite, slot.config);
        if (hit) {
          slot.hitSet.add(child);
          slot.handler(
            child,
            slot.config.damage,
            slot.config.knockX ?? 0,
            slot.config.knockY ?? 0,
            slot.config.knockStrength ?? 0,
          );
        }
      }
    };

    // Check overlap immediately + once more next frame.
    overlapFn();
    scene.time.delayedCall(16, overlapFn);

    if (slot.removeTimer) slot.removeTimer.remove();
    slot.removeTimer = scene.time.delayedCall(config.durationMs, () => {
      this.deactivate(slot);
    });
  }

  private intersects(target: Phaser.Physics.Arcade.Sprite, config: HitboxConfig): boolean {
    if (config.shape === 'sector') {
      return this.intersectsSector(target, config);
    }

    return Phaser.Geom.Intersects.RectangleToRectangle(
      new Phaser.Geom.Rectangle(config.x - config.width / 2, config.y - config.height / 2, config.width, config.height),
      target.getBounds(),
    );
  }

  private intersectsSector(target: Phaser.Physics.Arcade.Sprite, config: HitboxConfig): boolean {
    const originX = config.originX ?? config.x;
    const originY = config.originY ?? config.y;
    const angle = config.angle ?? 0;
    const arcHalf = (config.arcWidth ?? Math.PI / 2) / 2;
    const innerRadius = config.innerRadius ?? 0;
    const outerRadius = config.outerRadius ?? Math.max(config.width, config.height) / 2;
    const bounds = target.getBounds();
    const centerX = bounds.centerX;
    const centerY = bounds.centerY;
    const radius = Math.max(bounds.width, bounds.height) / 2;
    const dx = centerX - originX;
    const dy = centerY - originY;
    const dist = Math.hypot(dx, dy);

    if (dist > outerRadius + radius) return false;
    if (dist + radius < innerRadius) return false;

    if (dist <= radius) return true;

    const angleToTarget = Math.atan2(dy, dx);
    const angleDelta = Math.abs(Phaser.Math.Angle.Wrap(angleToTarget - angle));
    const anglePadding = Math.asin(Phaser.Math.Clamp(radius / Math.max(dist, 1), 0, 1));

    return angleDelta <= arcHalf + anglePadding;
  }

  private deactivate(slot: PooledHitbox): void {
    slot.active = false;
    slot.config = null;
    slot.handler = null;
    slot.hitSet.clear();
    slot.vfx.clear();
    slot.vfx.setVisible(false);
    slot.zone.setVisible(false);
    if (slot.removeTimer) {
      slot.removeTimer.remove();
      slot.removeTimer = null;
    }
  }

  clearScene(scene: Phaser.Scene): void {
    const pool = this.pools.get(scene);
    if (pool) {
      for (const p of pool) {
        this.deactivate(p);
        p.zone.destroy();
        p.vfx.destroy();
      }
      this.pools.delete(scene);
    }
  }

  getActiveConfigs(scene: Phaser.Scene): readonly HitboxConfig[] {
    return (this.pools.get(scene) ?? [])
      .filter((slot) => slot.active && slot.config)
      .map((slot) => slot.config!);
  }
}

export const hitboxPool = new HitboxPoolImpl();
