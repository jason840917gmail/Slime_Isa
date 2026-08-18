import Phaser from 'phaser';
import { resolveWorldDepth } from '../presentation/WorldDepth';
import { attackIntersectsCombatBody, resolveCombatBodyGeometry } from './CombatBodyGeometry';

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
  /** Authored hit shape. */
  shape?: 'rect' | 'sector' | 'circle' | 'ellipse';
  originX?: number;
  originY?: number;
  angle?: number;
  arcWidth?: number;
  innerRadius?: number;
  outerRadius?: number;
  radiusX?: number;
  radiusY?: number;
  /** Track-driven hitboxes stay active until their span closes. */
  autoDeactivate?: boolean;
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

export type HitboxTargetGroup =
  | Phaser.GameObjects.Group
  | Phaser.Physics.Arcade.Group
  | Phaser.Physics.Arcade.StaticGroup;
export type HitboxTargets = HitboxTargetGroup | readonly HitboxTargetGroup[];

export interface HitboxActivationHandle {
  readonly isActive: boolean;
  deactivate(): void;
}

interface PooledHitbox {
  scene: Phaser.Scene;
  zone: Phaser.GameObjects.Zone;
  vfx: Phaser.GameObjects.Graphics;
  active: boolean;
  config: HitboxConfig | null;
  handler: HitHandler | null;
  hitSet: Set<Phaser.GameObjects.GameObject>;
  removeTimer: Phaser.Time.TimerEvent | null;
  targets: HitboxTargets | null;
  activationToken: number;
  sortId: string;
}

class HitboxPoolImpl {
  private pools = new Map<Phaser.Scene, PooledHitbox[]>();
  spawn(
    scene: Phaser.Scene,
    targets: HitboxTargets,
    config: HitboxConfig,
    handler: HitHandler,
  ): HitboxActivationHandle {
    const pool = this.getPool(scene);
    let slot = pool.find((p) => !p.active);

    if (!slot) {
      slot = this.createSlot(scene, pool);
    }

    this.activate(scene, slot, targets, config, handler);
    const token = slot.activationToken;
    return {
      get isActive(): boolean { return slot.active && slot.activationToken === token; },
      deactivate: () => {
        if (slot.active && slot.activationToken === token) this.deactivate(slot);
      },
    };
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

    const vfx = scene.add.graphics().setVisible(false);

    const slot: PooledHitbox = {
      scene,
      zone,
      vfx,
      active: false,
      config: null,
      handler: null,
      hitSet: new Set(),
      removeTimer: null,
      targets: null,
      activationToken: 0,
      sortId: `hitbox:${pool.length}`,
    };
    pool.push(slot);
    return slot;
  }

  private activate(
    scene: Phaser.Scene,
    slot: PooledHitbox,
    targets: HitboxTargets,
    config: HitboxConfig,
    handler: HitHandler,
  ): void {
    slot.active = true;
    slot.activationToken += 1;
    slot.config = config;
    slot.handler = handler;
    slot.hitSet = config.hitSet ?? new Set();
    slot.targets = targets;
    slot.vfx.setDepth(resolveWorldDepth(config.y, {
      stableId: slot.sortId,
      attachmentSlot: 2,
    }).depth);

    const body = slot.zone.body as Phaser.Physics.Arcade.StaticBody;
    body.setSize(config.width, config.height);
    body.updateFromGameObject();
    slot.zone.setPosition(config.x, config.y);
    body.x = config.x - config.width / 2;
    body.y = config.y - config.height / 2;
    slot.zone.setVisible(false);

    // VFX slash rect.
    if (config.showVfx ?? true) {
      const color = config.vfxColor ?? 0x86f0c3;
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

    // Check immediately; update() continues checking while active.
    this.checkOverlap(slot);

    if (slot.removeTimer) slot.removeTimer.remove();
    if (config.autoDeactivate ?? true) {
      slot.removeTimer = scene.time.delayedCall(config.durationMs, () => this.deactivate(slot));
    }
  }

  update(scene: Phaser.Scene): void {
    const pool = this.pools.get(scene);
    if (!pool) return;
    for (const slot of pool) this.checkOverlap(slot);
  }

  private checkOverlap(slot: PooledHitbox): void {
    if (!slot.active || !slot.config || !slot.handler || !slot.targets) return;
    const groups = Array.isArray(slot.targets) ? slot.targets : [slot.targets];
    const visited = new Set<Phaser.GameObjects.GameObject>();
    for (const group of groups) for (const child of group.getChildren()) {
      if (visited.has(child)) continue;
      visited.add(child);
      if (slot.hitSet.has(child)) continue;
      const targetGeometry = resolveCombatBodyGeometry(child as Phaser.Physics.Arcade.Sprite);
      if (!attackIntersectsCombatBody(slot.config, targetGeometry)) continue;
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

  private deactivate(slot: PooledHitbox): void {
    slot.active = false;
    slot.config = null;
    slot.handler = null;
    slot.targets = null;
    slot.hitSet.clear();
    slot.scene.tweens.killTweensOf(slot.vfx);
    slot.vfx.clear();
    slot.vfx.setAlpha(1);
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
