import Phaser from 'phaser';
import { BLOBFATHER } from '../../boss/BossDefs';
import { ComboSystem } from '../../combat/ComboSystem';
import { TargetDummy } from '../../combat/TargetDummy';
import type { Weapon } from '../../combat/Weapon';
import { gameEvents } from '../../core/EventBus';
import { gameState } from '../../core/GameState';
import { Enemy } from '../../enemies/Enemy';
import { EnemySpawner } from '../../enemies/EnemySpawner';
import { ENEMY_CONFIGS, SPAWN_TABLE_MEDIUM } from '../../enemies/library/EnemyTypes';
import { projectilePool } from '../../enemies/Projectile';
import { worldProgress } from '../progression/WorldProgress';
import { UI_THEME } from '../../presentation/theme';
import { getStats } from '../../systems/PlayerStats';
import { playerInventory } from '../../systems/Inventory';
import { BossHealthBar } from '../../ui/BossHealthBar';
import { floatingText } from '../../ui/FloatingText';
import { createGooGauntlet } from '../../weapons/library/GooGauntlet';
import type { WorldDimensions } from '../../world/WorldDimensions';
import type { MapEnemySafeZone, MapSpawns } from '../../content/maps/mapFormat';

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
  applyPlayerDamage: (amount: number, source: string) => void;
  healPlayer: (amount: number) => number;
  spawnItemDropIcon: (x: number, y: number, itemId: string, count: number, index: number, total: number) => void;
}

export class CombatController {
  readonly targets: Phaser.Physics.Arcade.Group;
  private weapon: Weapon;
  private combo: ComboSystem;
  private spawner: EnemySpawner;
  private activeBoss?: Enemy;
  private bossHealthBar?: BossHealthBar;
  private comboText: Phaser.GameObjects.Text;
  private attacking = false;

  constructor(private readonly ctx: CombatControllerContext) {
    const { scene, player } = ctx;
    const spawnConfig = ctx.spawns;
    const spawnTable = spawnConfig
      ? spawnConfig.enemies.map((entry) => ({
          config: ENEMY_CONFIGS[entry.type],
          weight: entry.weight,
          maxAlive: entry.maxAlive,
        }))
      : SPAWN_TABLE_MEDIUM;
    this.targets = scene.physics.add.group();
    this.comboText = scene.add.text(scene.cameras.main.width / 2, scene.cameras.main.height - 130, '', {
      fontFamily: UI_THEME.fontFamily,
      fontSize: '20px',
      color: '#ffe680',
      stroke: '#0a1f15',
      strokeThickness: 4,
    }).setOrigin(0.5).setScrollFactor(0).setDepth(55).setAlpha(0);

    this.combo = new ComboSystem(scene, {
      onComboHit: (count, multiplier) => {
        this.comboText.setText(`${count}x COMBO  ×${multiplier.toFixed(2)}`).setAlpha(1);
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

    this.spawner = new EnemySpawner({
      scene,
      getPlayer: () => player,
      maxPopulation: spawnConfig?.maxPopulation ?? 16,
      spawnRadius: spawnConfig?.radius.max ?? 500,
      despawnRadius: (spawnConfig?.radius.max ?? 500) + 300,
      minSpawnDistance: spawnConfig?.radius.min ?? 200,
      spawnIntervalMs: spawnConfig?.intervalMs ?? 1500,
      spawnTable,
      worldWidth: ctx.dimensions.width,
      worldHeight: ctx.dimensions.height,
      targetGroup: this.targets,
      getSafeZones: () => this.safeZones(),
      enemyContext: this.enemyContext(),
    });

    this.spawner.seed(Math.min(8, spawnConfig?.maxPopulation ?? 16));
    this.spawnBossIfNeeded();
    this.spawnDummy(player.x + 80, player.y + 20);
    scene.physics.add.collider(this.targets, ctx.collisionTiles);
    scene.physics.add.collider(player, this.targets);
    scene.physics.add.overlap(player, projectilePool.enemyGroup(scene), (_player, projectile) => {
      const sprite = projectile as Phaser.Physics.Arcade.Image;
      if (!ctx.isDodging()) ctx.applyPlayerDamage(12, 'projectile');
      floatingText.spawn(scene, sprite.x, sprite.y - 10, 'hit', 'orange');
      sprite.setActive(false).setVisible(false).setVelocity(0, 0);
    });
  }

  update(time: number, delta: number): void {
    this.combo.update();
    this.spawner.update(time, delta);
    this.bossHealthBar?.update();
  }

  tryAttack(aimDirection?: Phaser.Math.Vector2): boolean {
    if (this.attacking || !this.ctx.canAttack()) return false;
    return this.weapon.attack(this.ctx.scene.time.now, aimDirection);
  }

  spawnDummy(x: number, y: number): void {
    const dummy = new TargetDummy(this.ctx.scene, x, y);
    this.targets.add(dummy);
  }

  destroy(): void {
    this.spawner.destroy();
    this.bossHealthBar?.destroy();
    this.combo.reset();
    this.comboText.destroy();
  }

  private enemyContext() {
    return {
      getPlayer: () => this.ctx.player,
      onContactDamage: (_enemy: Enemy, amount: number) => {
        if (!this.ctx.isDodging()) this.ctx.applyPlayerDamage(amount, 'enemy');
      },
      onDeath: (enemy: Enemy) => this.onEnemyDeath(enemy),
      getSafeZones: () => this.safeZones(),
      fireProjectile: (x: number, y: number, dx: number, dy: number, speed: number) => {
        projectilePool.fire(this.ctx.scene, x, y, dx, dy, speed, 'enemy-projectile', 'enemy', 12);
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

  private spawnBossIfNeeded(): void {
    if (this.ctx.areaId !== BLOBFATHER.areaId || worldProgress.isBossDefeated(BLOBFATHER.id)) return;
    const position = this.ctx.findSpawnPoint(new Phaser.Math.Vector2(
      this.ctx.dimensions.width * 0.68,
      this.ctx.dimensions.height * 0.5,
    ));
    const boss = new Enemy(this.ctx.scene, position.x, position.y, BLOBFATHER.config, this.enemyContext());
    this.targets.add(boss);
    this.activeBoss = boss;
    this.bossHealthBar = new BossHealthBar(this.ctx.scene, boss, BLOBFATHER.name);
    this.showBossIntro(BLOBFATHER.name);
  }

  private showBossIntro(name: string): void {
    const { scene } = this.ctx;
    scene.cameras.main.shake(450, 0.01);
    const card = scene.add.container(scene.cameras.main.width / 2, 116).setScrollFactor(0).setDepth(240).setAlpha(0);
    const background = scene.add.graphics();
    background.fillStyle(0x1f0808, 0.92).fillRoundedRect(-210, -28, 420, 56, 14);
    background.lineStyle(2, 0xff5a5a, 0.9).strokeRoundedRect(-210, -28, 420, 56, 14);
    card.add(background);
    card.add(scene.add.text(0, 0, name, {
      fontFamily: UI_THEME.fontFamily,
      fontSize: '26px',
      color: '#ffe0d0',
      stroke: '#0a0505',
      strokeThickness: 6,
    }).setOrigin(0.5));
    scene.tweens.add({ targets: card, alpha: 1, y: 132, duration: 280, yoyo: true, hold: 1200, onComplete: () => card.destroy() });
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
    gameEvents.emit('enemy.died', { enemyId: enemy.enemyId, areaId: this.ctx.areaId, kind: enemy.config.textureKey });

    if (enemy === this.activeBoss) {
      worldProgress.defeatBoss(BLOBFATHER.id);
      this.bossHealthBar?.defeat();
      this.bossHealthBar = undefined;
      this.activeBoss = undefined;
      gameState.addCoins(BLOBFATHER.reward.coins);
      gameState.addXp(BLOBFATHER.reward.xp);
      scene.cameras.main.shake(700, 0.018);
      floatingText.spawn(scene, enemy.x, enemy.y - 70, `${BLOBFATHER.name} DEFEATED!`, 'yellow', true);
      floatingText.spawn(scene, enemy.x, enemy.y - 46, `+${BLOBFATHER.reward.coins}c  +${BLOBFATHER.reward.xp} XP`, 'green', true);
    }

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
