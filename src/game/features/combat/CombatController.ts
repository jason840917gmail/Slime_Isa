import Phaser from 'phaser';
import { ComboSystem } from '../../combat/ComboSystem';
import { TargetDummy } from '../../combat/TargetDummy';
import type { Weapon } from '../../combat/Weapon';
import { gameEvents } from '../../core/EventBus';
import { gameState } from '../../core/GameState';
import { Enemy } from '../../enemies/Enemy';
import { EnemySpawner } from '../../enemies/EnemySpawner';
import type { AnimatedVisual } from '../visuals/AnimatedVisual';
import { getEnemyConfig } from '../../enemies/library/EnemyTypes';
import { projectilePool } from '../../enemies/Projectile';
import { UI_THEME } from '../../presentation/theme';
import { getStats } from '../../systems/PlayerStats';
import { playerInventory } from '../../systems/Inventory';
import { getAsset, type AssetId } from '../../infrastructure/assets/manifest';
import { floatingText } from '../../ui/FloatingText';
import { createGooGauntlet } from '../../weapons/library/GooGauntlet';
import type { WorldDimensions } from '../../world/WorldDimensions';
import type { MapEnemySafeZone, MapSpawns } from '../../content/maps/mapFormat';
import { resolveScreenUiDepth } from '../../presentation/WorldDepth';

export interface CombatControllerContext {
  scene: Phaser.Scene;
  player: Phaser.Physics.Arcade.Sprite;
  collisionTiles: Phaser.Physics.Arcade.StaticGroup;
  dimensions: WorldDimensions;
  spawns?: MapSpawns;
  enemySafeZones: readonly MapEnemySafeZone[];
  areaId: string;
  getFacing: () => Phaser.Math.Vector2;
  getSafeZones: () => MapEnemySafeZone[];
  findSpawnPoint: (anchor: Phaser.Math.Vector2) => Phaser.Math.Vector2;
  playAnimation: (key: string) => void;
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
}

export class CombatController {
  readonly targets: Phaser.Physics.Arcade.Group;
  private weapon: Weapon;
  private combo: ComboSystem;
  private spawner?: EnemySpawner;
  private comboText: Phaser.GameObjects.Text;
  private attacking = false;
  private readonly projectileWorldColliders: Phaser.Physics.Arcade.Collider[] = [];

  constructor(private readonly ctx: CombatControllerContext) {
    const { scene, player } = ctx;
    const spawnConfig = ctx.spawns;
    this.targets = scene.physics.add.group();
    this.comboText = scene.add.text(scene.cameras.main.width / 2, scene.cameras.main.height - 130, '', {
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

    this.weapon = createGooGauntlet({
      scene,
      getPlayer: () => player,
      getFacing: ctx.getFacing,
      getTargets: () => this.targets,
      hitHandler: (target, damage, knockX, knockY, knockStrength) => {
        const finalDamage = Math.round(damage * this.combo.registerHit());
        if (target instanceof Enemy) {
          const hpBefore = target.hp;
          target.takeDamage(finalDamage, knockX, knockY, knockStrength);
          this.applyLifeSteal(Math.max(0, hpBefore - target.hp));
        } else if (target instanceof TargetDummy) {
          target.takeDamage(finalDamage, knockX, knockY, knockStrength);
        }
      },
      onAttackStart: () => {
        this.attacking = true;
        player.setVelocity(0, 0);
      },
      onAttackEnd: () => { this.attacking = false; },
      playAnimation: ctx.playAnimation,
    });

    if (spawnConfig) {
      this.spawner = new EnemySpawner({
        scene,
        getPlayer: () => player,
        maxPopulation: spawnConfig.maxPopulation,
        spawnRadius: spawnConfig.radius.max,
        despawnRadius: spawnConfig.radius.max + 300,
        minSpawnDistance: spawnConfig.radius.min,
        spawnIntervalMs: spawnConfig.intervalMs,
        spawnTable: spawnConfig.enemies.map((entry) => ({
          config: getEnemyConfig(entry.type),
          weight: entry.weight,
          maxAlive: entry.maxAlive,
        })),
        worldWidth: ctx.dimensions.width,
        worldHeight: ctx.dimensions.height,
        targetGroup: this.targets,
        getSafeZones: () => this.safeZones(),
        enemyContext: this.enemyContext(),
      });

      this.spawner.seed(Math.min(8, spawnConfig.maxPopulation));
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
    projectilePool.update(this.ctx.scene);
  }

  tryAttack(): boolean {
    if (this.attacking || !this.ctx.canAttack()) return false;
    return this.weapon.attack(this.ctx.scene.time.now);
  }

  spawnDummy(x: number, y: number): void {
    const dummy = new TargetDummy(this.ctx.scene, x, y);
    this.targets.add(dummy);
  }

  destroy(): void {
    this.projectileWorldColliders.forEach((collider) => collider.destroy());
    this.spawner?.destroy();
    this.combo.reset();
    this.comboText.destroy();
  }

  private enemyContext() {
    return {
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
        assetId: AssetId,
        damage: number,
        knockbackStrength: number,
      ) => {
        projectilePool.fire(
          this.ctx.scene,
          x,
          y,
          dx,
          dy,
          speed,
          getAsset(assetId).runtime.textureKey,
          'enemy',
          damage,
          knockbackStrength,
        );
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
