import Phaser from 'phaser';

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
  lifetimeTimer: Phaser.Time.TimerEvent | null;
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
    lifetimeMs = 3000,
  ): void {
    const groups = this.ensureGroups(scene);
    const pool = this.getPool(scene);
    let slot = pool.find((p) => !p.active && p.owner === owner);

    if (!slot) {
      const sprite = scene.physics.add.image(x, y, textureKey) as Phaser.Physics.Arcade.Image;
      sprite.setDepth(6);
      const group = owner === 'enemy' ? groups.enemy : groups.player;
      group.add(sprite);
      slot = { sprite, active: false, owner, damage: 0, lifetimeTimer: null };
      pool.push(slot);
    }

    this.activate(scene, slot, x, y, dx, dy, speed, textureKey, damage, lifetimeMs);
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
    lifetimeMs: number,
  ): void {
    slot.active = true;
    slot.damage = damage;
    slot.sprite.setTexture(textureKey);
    slot.sprite.setPosition(x, y);
    slot.sprite.setActive(true).setVisible(true).setAlpha(1);
    slot.sprite.setScale(1);
    slot.sprite.setVelocity(dx * speed, dy * speed);
    slot.sprite.setRotation(Math.atan2(dy, dx));

    if (slot.lifetimeTimer) slot.lifetimeTimer.remove();
    slot.lifetimeTimer = scene.time.delayedCall(lifetimeMs, () => {
      this.deactivate(slot);
    });
  }

  private deactivate(slot: PooledProjectile): void {
    slot.active = false;
    slot.sprite.setActive(false).setVisible(false).setVelocity(0, 0);
    if (slot.lifetimeTimer) {
      slot.lifetimeTimer.remove();
      slot.lifetimeTimer = null;
    }
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
