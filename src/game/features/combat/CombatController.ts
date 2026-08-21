import Phaser from 'phaser';
import { ComboSystem } from '../../combat/ComboSystem';
import { TargetDummy } from '../../combat/TargetDummy';
import { Weapon } from '../../combat/Weapon';
import { gameEvents } from '../../core/EventBus';
import { gameState } from '../../core/GameState';
import { Enemy, type ProjectileReference } from '../../enemies/Enemy';
import { EnemySpawner } from '../../enemies/EnemySpawner';
import type { AnimatedVisual } from '../visuals/AnimatedVisual';
import { getEnemyConfig } from '../../enemies/library/EnemyTypes';
import { projectilePool } from '../../enemies/Projectile';
import { UI_THEME } from '../../presentation/theme';
import { getStats } from '../../systems/PlayerStats';
import { playerInventory } from '../../systems/Inventory';
import { getAsset } from '../../infrastructure/assets/manifest';
import { floatingText } from '../../ui/FloatingText';
import { getWeaponDefinition } from '../../content/weapons/WeaponCatalog';
import type { WorldDimensions } from '../../world/WorldDimensions';
import type { MapEnemySafeZone, MapEnemySpawnArea, MapSpawns } from '../../content/maps/mapFormat';
import { resolveScreenUiDepth } from '../../presentation/WorldDepth';
import { hitboxPool } from '../../combat/Hitbox';
import { WeaponVisual } from './WeaponVisual';
import { ObjectAnimationAdapter } from '../objects/ObjectAnimationAdapter';
import { shouldSpawnConfirmedHitEffect } from '../../combat/ConfirmedHitEffect';
import { WorldEffectPool } from '../effects/WorldEffectPool';
import { resolveDamageModifier } from '../../combat/DamageModifiers';
import type { ResourceNodeController } from '../resources/ResourceNodeController';
import type { HitboxTargets } from '../../combat/Hitbox';
import { rejectedDamage } from '../../combat/DamageableTarget';

export interface CombatControllerContext {
  scene: Phaser.Scene;
  player: Phaser.Physics.Arcade.Sprite;
  collisionTiles: Phaser.Physics.Arcade.StaticGroup;
  dimensions: WorldDimensions;
  spawns?: MapSpawns;
  enemySpawnAreas: readonly MapEnemySpawnArea[];
  enemySafeZones: readonly MapEnemySafeZone[];
  areaId: string;
  getFacing: () => Phaser.Math.Vector2;
  getSafeZones: () => MapEnemySafeZone[];
  findSpawnPoint: (anchor: Phaser.Math.Vector2) => Phaser.Math.Vector2;
  playCharacterAction: (actionId: string) => void;
  setActionLocked: (locked: boolean) => void;
  canAttack: () => boolean;
  isDodging: () => boolean;
  applyPlayerDamage: (
    amount: number,
    source: string,
    impactX: number,
    impactY: number,
    knockbackStrength: number,
  ) => void;
  healPlayer: (amount: number) => number;
  spawnItemDropIcon: (x: number, y: number, itemId: string, count: number, index: number, total: number) => void;
  registerRevealActor?: (enemy: Enemy, visual: AnimatedVisual) => void;
  getResourceTargets?: () => Phaser.GameObjects.Group | null;
  resourceNodes?: ResourceNodeController;
}

export class CombatController {
  readonly targets: Phaser.Physics.Arcade.Group;
  private weapon: Weapon;
  private weaponVisual: WeaponVisual;
  private combo: ComboSystem;
  private spawner?: EnemySpawner;
  private comboText: Phaser.GameObjects.Text;
  private attacking = false;
  private readonly effects: WorldEffectPool;
  private readonly projectileWorldColliders: Phaser.Physics.Arcade.Collider[] = [];

  constructor(private readonly ctx: CombatControllerContext) {
    const { scene, player } = ctx;
    const spawnConfig = ctx.spawns;
    this.targets = scene.physics.add.group();
    this.effects = new WorldEffectPool(scene);
    this.comboText = scene.add.text(scene.cameras.main.width / 2, scene.cameras.main.height - 215, '', {
      fontFamily: UI_THEME.fontFamily,
      fontSize: '20px',
      color: '#ffdf8a',
      stroke: '#0b1020',
      strokeThickness: 4,
    }).setOrigin(0.5).setScrollFactor(0).setDepth(resolveScreenUiDepth(10)).setAlpha(0);

    this.combo = new ComboSystem(scene, {
      onComboHit: (count, multiplier) => {
        this.comboText.setText(`${count}x COMBO  Ã—${multiplier.toFixed(2)}`).setAlpha(1);
        scene.tweens.add({ targets: this.comboText, scale: { from: 1.2, to: 1 }, duration: 150, ease: 'Back.Out' });
      },
      onComboReset: () => this.comboText.setAlpha(0),
      onComboFinish: (count) => {
        floatingText.spawn(scene, player.x, player.y - 60, `${count}x FINISHER!`, 'yellow', true);
        scene.cameras.main.shake(120, 0.008);
      },
    });

    const initialWeapon = this.createWeaponRuntime(gameState.equippedWeaponId);
    this.weapon = initialWeapon.weapon;
    this.weaponVisual = initialWeapon.visual;

    if (ctx.enemySpawnAreas.length > 0 || spawnConfig) {
      this.spawner = new EnemySpawner({
        scene,
        getPlayer: () => player,
        maxPopulation: spawnConfig?.maxPopulation ?? 0,
        spawnRadius: spawnConfig?.radius.max ?? 0,
        despawnRadius: (spawnConfig?.radius.max ?? 0) + 300,
        minSpawnDistance: spawnConfig?.radius.min ?? 0,
        spawnIntervalMs: spawnConfig?.intervalMs ?? 0,
        spawnTable: spawnConfig?.enemies.map((entry) => ({
          config: getEnemyConfig(entry.type),
          weight: entry.weight,
          maxAlive: entry.maxAlive,
        })) ?? [],
        spawnAreas: ctx.enemySpawnAreas,
        createEnemyContext: (area) => this.enemyContext(area),
        worldWidth: ctx.dimensions.width,
        worldHeight: ctx.dimensions.height,
        targetGroup: this.targets,
        getSafeZones: () => this.safeZones(),
        enemyContext: this.enemyContext(),
      });

      this.spawner.seed(Math.min(8, spawnConfig?.maxPopulation ?? 8));
    }
    scene.physics.add.collider(this.targets, ctx.collisionTiles);
    scene.physics.add.collider(player, this.targets);
    const recycleOnWorldCollision: Phaser.Types.Physics.Arcade.ArcadePhysicsCallback = (projectile) => {
      projectilePool.recycle(projectile as Phaser.Physics.Arcade.Image);
    };
    this.projectileWorldColliders.push(
      scene.physics.add.collider(
        projectilePool.enemyGroup(scene),
        ctx.collisionTiles,
        recycleOnWorldCollision,
      ),
      scene.physics.add.collider(
        projectilePool.playerGroup(scene),
        ctx.collisionTiles,
        recycleOnWorldCollision,
      ),
    );
    scene.physics.add.overlap(player, projectilePool.enemyGroup(scene), (_player, projectile) => {
      const sprite = projectile as Phaser.Physics.Arcade.Image;
      if (!sprite.active) return;
      if (!ctx.isDodging()) {
        const velocity = (sprite.body as Phaser.Physics.Arcade.Body).velocity.clone();
        if (velocity.lengthSq() > 0) velocity.normalize();
        ctx.applyPlayerDamage(
          projectilePool.damageFor(sprite),
          'projectile',
          velocity.x,
          velocity.y,
          projectilePool.knockbackFor(sprite),
        );
      }
      projectilePool.recycle(sprite);
    });
  }

  update(time: number, delta: number): void {
    this.combo.update();
    this.spawner?.update(time, delta);
    this.weapon.update(delta);
    this.weaponVisual.update(delta);
    this.effects.update(delta);
    hitboxPool.update(this.ctx.scene);
    projectilePool.update(this.ctx.scene);
  }

  tryAttack(): boolean {
    if (this.attacking || !this.ctx.canAttack()) return false;
    return this.weapon.attack(this.ctx.scene.time.now);
  }

  equipWeapon(weaponId: string): boolean {
    if (this.attacking || weaponId === this.weapon.def.weaponId) return !this.attacking;
    let next: { weapon: Weapon; visual: WeaponVisual };
    try {
      next = this.createWeaponRuntime(weaponId);
    } catch {
      return false;
    }
    this.weapon.destroy();
    this.weaponVisual.destroy();
    this.weapon = next.weapon;
    this.weaponVisual = next.visual;
    this.ctx.playCharacterAction('idle');
    return true;
  }

  equippedWeaponId(): string {
    return this.weapon.def.weaponId;
  }

  spawnDummy(x: number, y: number): void {
    const dummy = new TargetDummy(this.ctx.scene, x, y);
    this.targets.add(dummy);
  }

  destroy(): void {
    this.weapon.destroy();
    this.weaponVisual.destroy();
    this.effects.destroy();
    this.ctx.setActionLocked(false);
    this.projectileWorldColliders.forEach((collider) => collider.destroy());
    this.spawner?.destroy();
    this.combo.reset();
    this.comboText.destroy();
  }

  private createWeaponRuntime(weaponId: string): { weapon: Weapon; visual: WeaponVisual } {
    const { scene, player } = this.ctx;
    const weapon = new Weapon(getWeaponDefinition(weaponId), {
      scene,
      getPlayer: () => player,
      getFacing: this.ctx.getFacing,
      getTargets: (): HitboxTargets => {
        const resourceTargets = this.ctx.getResourceTargets?.();
        return resourceTargets ? [this.targets, resourceTargets] : this.targets;
      },
      applyHit: ({ target, damage, knockX, knockY, knockStrength, attackDirection }) => {
        const isResourceTarget = this.ctx.resourceNodes?.isResourceTarget(target) === true;
        const targetTags = target instanceof Enemy
          ? ['enemy']
          : isResourceTarget
            ? this.ctx.resourceNodes!.tagsFor(target)
            : [];
        const damageModifier = resolveDamageModifier(weapon.def.damageModifiers, targetTags);
        if (damageModifier <= 0) return rejectedDamage('invalid');
        const comboDamage = damage * this.combo.registerHit();
        const finalDamage = Math.max(0, Math.round(comboDamage * damageModifier));
        if (finalDamage <= 0) return rejectedDamage('invalid');
        const resourceHitAnchor = isResourceTarget
          ? (() => {
              const image = target as Phaser.GameObjects.GameObject & { readonly x: number; readonly y: number; readonly depth: number };
              return { x: image.x, y: image.y, depth: image.depth };
            })()
          : undefined;
        let result;
        let hitTarget: Enemy | TargetDummy | undefined;
        if (target instanceof Enemy) {
          hitTarget = target;
          result = target.applyDamage({ amount: finalDamage, knockX, knockY, knockStrength });
          this.applyLifeSteal(result.actualDamage);
        } else if (target instanceof TargetDummy) {
          hitTarget = target;
          result = target.applyDamage({ amount: finalDamage, knockX, knockY, knockStrength });
        } else if (isResourceTarget) {
          result = this.ctx.resourceNodes!.applyDamage(target, finalDamage);
        } else {
          result = { status: 'rejected' as const, actualDamage: 0, defeated: false, reason: 'invalid' as const };
        }
        const resourceHitEffectId = 'resourceHitEffectId' in result
          && typeof result.resourceHitEffectId === 'string'
          ? result.resourceHitEffectId
          : undefined;
        const acceptedObjectEvent = isResourceTarget
          && result.status === 'accepted'
          && 'acceptedDamage' in result
          ? result
          : undefined;
        if (acceptedObjectEvent?.depleted) {
          const adapter = acceptedObjectEvent.target.getData('objectAnimationAdapter') as ObjectAnimationAdapter | undefined;
          const playbackStarted = acceptedObjectEvent.acceptedDamage > 0 && acceptedObjectEvent.onHitAnimationId
            ? adapter?.animateOnHit(acceptedObjectEvent.onHitAnimationId, () => this.ctx.resourceNodes?.completeDepletion(acceptedObjectEvent.target)) ?? false
            : false;
          if (!playbackStarted) this.ctx.resourceNodes?.completeDepletion(acceptedObjectEvent.target);
        } else if (acceptedObjectEvent && acceptedObjectEvent.acceptedDamage > 0 && acceptedObjectEvent.onHitAnimationId) {
          (acceptedObjectEvent.target.getData('objectAnimationAdapter') as ObjectAnimationAdapter | undefined)
            ?.animateOnHit(acceptedObjectEvent.onHitAnimationId);
        }
        if (hitTarget && shouldSpawnConfirmedHitEffect(weapon.def.onHitEffectId, result)) {
          this.effects.spawn({
            effectId: weapon.def.onHitEffectId!,
            direction: attackDirection,
            x: hitTarget.x,
            y: hitTarget.y,
            depth: hitTarget.depth + 0.2,
            followPositionOf: hitTarget,
            followDepthOffset: 0.2,
          });
        } else if (
          resourceHitAnchor
          && shouldSpawnConfirmedHitEffect(resourceHitEffectId, result)
        ) {
          this.effects.spawn({
            effectId: resourceHitEffectId!,
            direction: attackDirection,
            x: resourceHitAnchor.x,
            y: resourceHitAnchor.y,
            depth: resourceHitAnchor.depth + 0.2,
            ...(target.active ? {
              followPositionOf: target as Phaser.GameObjects.GameObject & { readonly x: number; readonly y: number; readonly depth: number },
              followDepthOffset: 0.2,
            } : {}),
          });
        }
        return result;
      },
      onAttackStart: () => {
        this.attacking = true;
        this.ctx.setActionLocked(true);
        player.setVelocity(0, 0);
      },
      onAttackEnd: () => {
        this.attacking = false;
        this.ctx.setActionLocked(false);
        this.ctx.playCharacterAction('idle');
      },
      playCharacterAction: this.ctx.playCharacterAction,
      playWeaponAnimation: (animationId, forceRestart) => this.weaponVisual?.play(animationId, forceRestart),
    });
    const visual = new WeaponVisual(scene, player, weapon.def, weapon.clock, {
      getDepth: () => player.depth + 0.01,
      getFacing: this.ctx.getFacing,
    });
    weapon.startIdle();
    return { weapon, visual };
  }

  private enemyContext(spawnArea?: MapEnemySpawnArea) {
    return {
      spawnArea,
      getPlayer: () => this.ctx.player,
      onContactDamage: (enemy: Enemy, amount: number) => {
        if (this.ctx.isDodging()) return;
        const impact = new Phaser.Math.Vector2(
          this.ctx.player.x - enemy.x,
          this.ctx.player.y - enemy.y,
        );
        if (impact.lengthSq() > 0) impact.normalize();
        this.ctx.applyPlayerDamage(
          amount,
          enemy.config.id,
          impact.x,
          impact.y,
          enemy.config.ai.knockbackStrength,
        );
      },
      onDeath: (enemy: Enemy) => this.onEnemyDeath(enemy),
      getSafeZones: () => this.safeZones(),
      registerRevealActor: this.ctx.registerRevealActor,
      fireProjectile: (
        x: number,
        y: number,
        dx: number,
        dy: number,
        speed: number,
        projectile: ProjectileReference,
        damage: number,
        knockbackStrength: number,
      ) => {
        if (projectile.projectileId) {
          projectilePool.fireDefinition(this.ctx.scene, x, y, dx, dy, projectile.projectileId, 'enemy', damage, knockbackStrength, speed);
          return;
        }
        if (!projectile.assetId) throw new Error('Projectile reference has no projectile ID or asset ID');
        projectilePool.fire(this.ctx.scene, x, y, dx, dy, speed, getAsset(projectile.assetId).runtime.textureKey, 'enemy', damage, knockbackStrength);
      },
    };
  }

  private safeZones(): MapEnemySafeZone[] {
    return [
      ...this.ctx.getSafeZones(),
      ...this.ctx.enemySafeZones,
      ...(this.ctx.spawns?.safeZones ?? []),
    ];
  }

  private applyLifeSteal(damageDealt: number): void {
    const percentage = getStats().lifeStealPct;
    if (damageDealt <= 0 || percentage <= 0) return;
    const healed = this.ctx.healPlayer(Math.ceil(damageDealt * percentage));
    if (healed > 0) floatingText.spawn(this.ctx.scene, this.ctx.player.x, this.ctx.player.y - 36, `+${healed}`, 'green');
  }

  private onEnemyDeath(enemy: Enemy): void {
    const { drop } = enemy.config;
    const { scene } = this.ctx;
    gameEvents.emit('enemy.died', {
      enemyId: enemy.enemyId,
      areaId: this.ctx.areaId,
      kind: enemy.config.id,
    });

    if (drop.xp > 0) {
      gameState.addXp(drop.xp);
      floatingText.spawn(scene, enemy.x, enemy.y - 36, `+${drop.xp} XP`, 'cyan');
    }
    if (drop.coins > 0) {
      gameState.addCoins(drop.coins);
      floatingText.spawn(scene, enemy.x, enemy.y - 20, `+${drop.coins}c`, 'yellow');
    }

    const itemDrops = (drop.items ?? []).filter((item) => Math.random() < item.chance);
    itemDrops.forEach((item, index) => {
      const added = playerInventory.add(item.itemId, item.count ?? 1);
      if (added > 0) this.ctx.spawnItemDropIcon(enemy.x, enemy.y, item.itemId, added, index, itemDrops.length);
    });
  }
}
