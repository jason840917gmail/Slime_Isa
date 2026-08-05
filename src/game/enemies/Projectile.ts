import Phaser from 'phaser';
import { resolveBodyCenterY, resolveWorldDepth } from '../presentation/WorldDepth';
import { getProjectileDefinition } from '../content/projectiles/ProjectileCatalog';
import type { ProjectileAnimationDocument, ProjectileDefinition } from '../content/projectiles/types';
import { ASSET_MANIFEST, getAsset, type AssetId } from '../infrastructure/assets/manifest';
import { animationFrameIndexAtStep } from '../shared/animationLoop';
import { applyArcadeBodyGeometry } from '../shared/collisionShapes';

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
  visual: Phaser.GameObjects.Image;
  active: boolean;
  owner: ProjectileOwner;
  damage: number;
  knockbackStrength: number;
  lifetimeTimer: Phaser.Time.TimerEvent | null;
  sortId: string;
  lastGroundY: number;
  definition?: ProjectileDefinition;
  animationStartedAt: number;
  animationState: 'move' | 'impact';
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
    definition?: ProjectileDefinition,
  ): void {
    const groups = this.ensureGroups(scene);
    const pool = this.getPool(scene);
    let slot = pool.find((p) => !p.active && p.owner === owner);

    if (!slot) {
      const sprite = scene.physics.add.image(x, y, textureKey) as Phaser.Physics.Arcade.Image;
      const visual = scene.add.image(x, y, textureKey);
      const group = owner === 'enemy' ? groups.enemy : groups.player;
      group.add(sprite);
      slot = {
        sprite,
        visual,
        active: false,
        owner,
        damage: 0,
        knockbackStrength: 0,
        lifetimeTimer: null,
        sortId: `projectile:${owner}:${pool.length}`,
        lastGroundY: Number.NaN,
        animationStartedAt: 0,
        animationState: 'move',
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
      definition,
    );
  }

  fireDefinition(
    scene: Phaser.Scene,
    x: number,
    y: number,
    dx: number,
    dy: number,
    projectileId: string,
    owner: ProjectileOwner,
    damage: number,
    knockbackStrength: number,
    speed = getProjectileDefinition(projectileId).movement.defaultSpeed,
  ): void {
    const definition = getProjectileDefinition(projectileId);
    if (!(definition.assetId in ASSET_MANIFEST.assets)) throw new Error(`Projectile '${projectileId}' references unknown asset '${definition.assetId}'`);
    this.fire(
      scene,
      x,
      y,
      dx,
      dy,
      speed,
      getAsset(definition.assetId as AssetId).runtime.textureKey,
      owner,
      damage,
      knockbackStrength,
      definition.movement.lifetimeMs,
      definition,
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
    definition?: ProjectileDefinition,
  ): void {
    slot.active = true;
    slot.damage = damage;
    slot.knockbackStrength = knockbackStrength;
    slot.definition = definition;
    slot.animationStartedAt = scene.time.now;
    slot.animationState = 'move';
    slot.sprite.setTexture(textureKey);
    slot.sprite.setPosition(x, y);
    slot.sprite.clearTint().setOrigin(0.5).setActive(true).setVisible(false).setAlpha(0);
    slot.sprite.setScale(1).setRotation(definition?.movement.rotateToVelocity === false ? 0 : Math.atan2(dy, dx));
    slot.visual.setTexture(textureKey).clearTint().setOrigin(0.5).setActive(true).setVisible(true).setAlpha(1);
    slot.visual.setScale(1).setRotation(slot.sprite.rotation);
    const body = slot.sprite.body as Phaser.Physics.Arcade.Body;
    body.enable = true;
    applyArcadeBodyGeometry(body, slot.sprite.displayOriginX, slot.sprite.displayOriginY, definition?.body ?? {
      width: slot.sprite.width,
      height: slot.sprite.height,
      centerOffsetX: 0,
      centerOffsetY: 0,
    });
    this.updateAnimationFrame(slot, 0);
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
    slot.animationState = 'move';
    slot.sprite.setActive(false).setVisible(false).setVelocity(0, 0);
    slot.visual.setActive(false).setVisible(false);
    (slot.sprite.body as Phaser.Physics.Arcade.Body).enable = false;
    if (slot.lifetimeTimer) {
      slot.lifetimeTimer.remove();
      slot.lifetimeTimer = null;
    }
  }

  update(scene: Phaser.Scene): void {
    for (const slot of this.pools.get(scene) ?? []) {
      if (!slot.active) continue;
      const animation = this.animationFor(slot);
      if (animation) {
        const step = Math.floor(Math.max(0, scene.time.now - slot.animationStartedAt) / (1000 / animation.framesPerSecond));
        if (slot.animationState === 'impact' && !animation.loop && step >= animation.frames.length) {
          this.deactivate(slot);
          continue;
        }
        const position = animation.loop ? animationFrameIndexAtStep(animation, step) : Math.min(step, animation.frames.length - 1);
        this.updateAnimationFrame(slot, position);
      }
      this.syncVisual(slot);
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
    if (!slot || !slot.active || slot.animationState === 'impact') return;
    const impact = slot.definition?.animations?.impact;
    if (!impact || impact.frames.length === 0) {
      this.deactivate(slot);
      return;
    }
    slot.animationState = 'impact';
    slot.animationStartedAt = sprite.scene.time.now;
    slot.sprite.setVelocity(0, 0);
    (slot.sprite.body as Phaser.Physics.Arcade.Body).enable = false;
    if (slot.lifetimeTimer) {
      slot.lifetimeTimer.remove();
      slot.lifetimeTimer = null;
    }
    this.updateAnimationFrame(slot, 0);
  }

  private updateDepth(slot: PooledProjectile, groundY?: number): void {
    const body = slot.sprite.body as Phaser.Physics.Arcade.Body;
    const nextGroundY = groundY ?? resolveBodyCenterY(body);
    slot.lastGroundY = nextGroundY;
    const depth = resolveWorldDepth(nextGroundY, { stableId: slot.sortId }).depth;
    slot.sprite.setDepth(depth);
    slot.visual.setDepth(depth);
  }

  private updateAnimationFrame(slot: PooledProjectile, position: number): void {
    const definition = slot.definition;
    const animation = this.animationFor(slot);
    if (!definition || !animation || !(definition.assetId in ASSET_MANIFEST.assets)) return;
    const asset = getAsset(definition.assetId as AssetId);
    if (asset.source.kind !== 'spritesheet') return;
    const frame = animation.frames[Math.max(0, Math.min(position, animation.frames.length - 1))];
    if (frame !== undefined) {
      slot.sprite.setFrame(frame);
      slot.visual.setFrame(frame);
      this.syncVisual(slot, frame);
    }
  }

  private syncVisual(slot: PooledProjectile, frame?: number): void {
    const definition = slot.definition;
    if (!definition) return;
    const currentFrame = (frame ?? Number(slot.sprite.frame.name)) || 0;
    const offset = definition.visual?.frameOffsets?.[String(currentFrame)] ?? definition.visual?.sourceOffset ?? [0, 0];
    const rotation = slot.sprite.rotation;
    const cos = Math.cos(rotation);
    const sin = Math.sin(rotation);
    const offsetX = offset[0] * cos - offset[1] * sin;
    const offsetY = offset[0] * sin + offset[1] * cos;
    slot.visual
      .setPosition(slot.sprite.x + offsetX, slot.sprite.y + offsetY)
      .setRotation(rotation)
      .setDepth(slot.sprite.depth);
  }

  private animationFor(slot: PooledProjectile): ProjectileAnimationDocument | undefined {
    if (slot.animationState === 'impact') return slot.definition?.animations?.impact;
    return slot.definition?.animations?.move ?? slot.definition?.animation;
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
        p.visual.destroy();
      }
      this.pools.delete(scene);
    }
    this.groups.delete(scene);
  }
}

export const projectilePool = new ProjectilePoolImpl();
