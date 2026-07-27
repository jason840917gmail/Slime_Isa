import Phaser from 'phaser';
import { resolveBodyCenterY, resolveWorldDepth } from '../presentation/WorldDepth';

/**
 * Pooled projectile system. Supports both enemy projectiles (damage player)
 * and player projectiles (damage enemies, for the Bouncy Bow in Phase 2+).
 *
 * Projectiles are simple physics images with velocity + lifetime. On overlap
 * with the target group, the callback fires and the projectile is recycled.
 */

export type ProjectileOwner = 'enemy' | 'player';

interface PooledProjectile {
  sprite: Phaser.Physics.Arcade.Image;
  active: boolean;
  owner: ProjectileOwner;
  damage: number;
  knockbackStrength: number;
  lifetimeTimer: Phaser.Time.TimerEvent | null;
  sortId: string;
  lastGroundY: number;
}

class ProjectilePoolImpl {
  private pools = new Map<Phaser.Scene, PooledProjectile[]>();
  private groups = new Map<Phaser.Scene, { enemy: Phaser.Physics.Arcade.Group; player: Phaser.Physics.Arcade.Group }>();

  ensureGroups(scene: Phaser.Scene): { enemy: Phaser.Physics.Arcade.Group; player: Phaser.Physics.Arcade.Group } {
    let groups = this.groups.get(scene);
    if (!groups) {
      groups = {
        enemy: scene.physics.add.group(),
        player: scene.physics.add.group(),
      };
      this.groups.set(scene, groups);
    }
    return groups;
  }

  fire(
    scene: Phaser.Scene,
    x: number,
    y: number,
    dx: number,
    dy: number,
    speed: number,
    textureKey: string,
    owner: ProjectileOwner,
    damage: number,
    knockbackStrength: number,
    lifetimeMs = 3000,
  ): void {
    const groups = this.ensureGroups(scene);
    const pool = this.getPool(scene);
    let slot = pool.find((p) => !p.active && p.owner === owner);

    if (!slot) {
      const sprite = scene.physics.add.image(x, y, textureKey) as Phaser.Physics.Arcade.Image;
      const group = owner === 'enemy' ? groups.enemy : groups.player;
      group.add(sprite);
      slot = {
        sprite,
        active: false,
        owner,
        damage: 0,
        knockbackStrength: 0,
        lifetimeTimer: null,
        sortId: `projectile:${owner}:${pool.length}`,
        lastGroundY: Number.NaN,
      };
      pool.push(slot);
    }

    this.activate(
      scene,
      slot,
      x,
      y,
      dx,
      dy,
      speed,
      textureKey,
      damage,
      knockbackStrength,
      lifetimeMs,
    );
  }

  private getPool(scene: Phaser.Scene): PooledProjectile[] {
    let pool = this.pools.get(scene);
    if (!pool) {
      pool = [];
      this.pools.set(scene, pool);
    }
    return pool;
  }

  private activate(
    scene: Phaser.Scene,
    slot: PooledProjectile,
    x: number,
    y: number,
    dx: number,
    dy: number,
    speed: number,
    textureKey: string,
    damage: number,
    knockbackStrength: number,
    lifetimeMs: number,
  ): void {
    slot.active = true;
    slot.damage = damage;
    slot.knockbackStrength = knockbackStrength;
    slot.sprite.setTexture(textureKey);
    slot.sprite.setPosition(x, y);
    slot.sprite.clearTint().setOrigin(0.5).setActive(true).setVisible(true).setAlpha(1);
    slot.sprite.setScale(1).setRotation(Math.atan2(dy, dx));
    const body = slot.sprite.body as Phaser.Physics.Arcade.Body;
    body.enable = true;
    body.setSize(slot.sprite.width, slot.sprite.height, true);
    slot.sprite.setVelocity(dx * speed, dy * speed);
    slot.lastGroundY = Number.NaN;
    this.updateDepth(slot);

    if (slot.lifetimeTimer) slot.lifetimeTimer.remove();
    slot.lifetimeTimer = scene.time.delayedCall(lifetimeMs, () => {
      this.deactivate(slot);
    });
  }

  private deactivate(slot: PooledProjectile): void {
    slot.active = false;
    slot.sprite.setActive(false).setVisible(false).setVelocity(0, 0);
    (slot.sprite.body as Phaser.Physics.Arcade.Body).enable = false;
    if (slot.lifetimeTimer) {
      slot.lifetimeTimer.remove();
      slot.lifetimeTimer = null;
    }
  }

  update(scene: Phaser.Scene): void {
    for (const slot of this.pools.get(scene) ?? []) {
      if (!slot.active) continue;
      const body = slot.sprite.body as Phaser.Physics.Arcade.Body;
      const groundY = resolveBodyCenterY(body);
      if (groundY !== slot.lastGroundY) this.updateDepth(slot, groundY);
    }
  }

  damageFor(sprite: Phaser.Physics.Arcade.Image): number {
    return this.getPool(sprite.scene).find((slot) => slot.sprite === sprite)?.damage ?? 0;
  }

  knockbackFor(sprite: Phaser.Physics.Arcade.Image): number {
    return this.getPool(sprite.scene).find(
      (slot) => slot.sprite === sprite,
    )?.knockbackStrength ?? 0;
  }

  recycle(sprite: Phaser.Physics.Arcade.Image): void {
    const slot = this.getPool(sprite.scene).find((candidate) => candidate.sprite === sprite);
    if (slot) this.deactivate(slot);
  }

  private updateDepth(slot: PooledProjectile, groundY?: number): void {
    const body = slot.sprite.body as Phaser.Physics.Arcade.Body;
    const nextGroundY = groundY ?? resolveBodyCenterY(body);
    slot.lastGroundY = nextGroundY;
    slot.sprite.setDepth(resolveWorldDepth(nextGroundY, { stableId: slot.sortId }).depth);
  }

  /** Get the enemy-projectile group for overlap setup. */
  enemyGroup(scene: Phaser.Scene): Phaser.Physics.Arcade.Group {
    return this.ensureGroups(scene).enemy;
  }

  /** Get the player-projectile group for overlap setup. */
  playerGroup(scene: Phaser.Scene): Phaser.Physics.Arcade.Group {
    return this.ensureGroups(scene).player;
  }

  clearScene(scene: Phaser.Scene): void {
    const pool = this.pools.get(scene);
    if (pool) {
      for (const p of pool) {
        if (p.lifetimeTimer) p.lifetimeTimer.remove();
        p.sprite.destroy();
      }
      this.pools.delete(scene);
    }
    this.groups.delete(scene);
  }
}

export const projectilePool = new ProjectilePoolImpl();
