import Phaser from 'phaser';
import { ComboSystem } from '../../combat/ComboSystem';
import { resolveScaledValue } from '../../combat/CombatScaling';
import { TargetDummy } from '../../combat/TargetDummy';
import { gameEvents } from '../../core/EventBus';
import { gameState } from '../../core/GameState';
import type { EnemyConfig } from '../../enemies/EnemyConfig';
import {
  AuthoredEnemyPopulationController,
  type EnemyPopulationMember,
  type EnemySpawnRequest,
} from '../../enemies/AuthoredEnemyPopulationController';
import { getEnemyConfig } from '../../enemies/library/EnemyTypes';
import { UI_THEME } from '../../presentation/theme';
import { getStats } from '../../systems/PlayerStats';
import { playerInventory } from '../../systems/Inventory';
import { floatingText } from '../../ui/FloatingText';
import { gameFeel } from '../feel/sharedFeel';
import { particleFx } from '../feel/ParticlePresets';
import { getWeaponDefinition } from '../../content/weapons/WeaponCatalog';
import type { NormalizedWeaponDefinition } from '../../content/weapons/types';
import type { WorldDimensions } from '../../world/WorldDimensions';
import type { MapEnemySafeZone, MapEnemySpawnArea, MapSpawns } from '../../content/maps/mapFormat';
import { MAX_ATTACHMENT_SLOT, resolveScreenUiDepth, resolveWorldDepth } from '../../presentation/WorldDepth';
import type { ManagedWorldEffectSpawner, WorldEffectSpawnRequest } from '../effects/WorldEffectSpawn';
import { resolveDamageModifier } from '../../combat/DamageModifiers';
import type { RoutedDamageOutcome } from './DamageRouter';
import type {
  ManagedWeaponTarget,
  WeaponAttackDirection,
  WeaponDamagePayload,
} from '../scripts/WeaponScript';

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
  findSpawnPoint: (anchor: Phaser.Math.Vector2) => Phaser.Math.Vector2;
  playCharacterAction: (actionId: string) => void;
  setActionLocked: (locked: boolean) => void;
  canAttack: () => boolean;
  healPlayer: (amount: number) => number;
  spawnItemDropIcon: (x: number, y: number, itemId: string, count: number, index: number, total: number) => void;
  createManagedEnemy: (request: EnemySpawnRequest) => EnemyPopulationMember | null | undefined;
  spawnManagedEffect: ManagedWorldEffectSpawner;
  mountManagedWeapon: (weaponId: string) => boolean;
  canManagedWeaponAttack: () => boolean;
  playManagedWeaponAttack: (direction: WeaponAttackDirection, damage: WeaponDamagePayload) => boolean;
  clearManagedWeapon: () => void;
  /** Gameplay clock (simulation time) for combo windows. */
  nowMs: () => number;
}

function resolveAttackDirection(direction: Phaser.Math.Vector2): WeaponAttackDirection {
  if (Math.abs(direction.x) >= Math.abs(direction.y)) return direction.x < 0 ? 'left' : 'right';
  return direction.y < 0 ? 'up' : 'down';
}

export interface ManagedEnemyDefeat {
  readonly enemyId: number;
  readonly config: EnemyConfig;
  readonly x: number;
  readonly y: number;
}

export class CombatController {
  readonly targets: Phaser.Physics.Arcade.Group;
  private weapon?: NormalizedWeaponDefinition;
  /** Set while a picked harvest tool swings: the weapon to put back when the swing ends. */
  private restoreAfterToolSwing?: { readonly weaponId: string | null };
  private combo: ComboSystem;
  private spawner?: AuthoredEnemyPopulationController;
  private comboText: Phaser.GameObjects.Text;
  private attacking = false;
  /** The swing in flight rolled a crit; cleared once its first creature hit sounds the crit. */
  private criticalAttack = false;

  constructor(private readonly ctx: CombatControllerContext) {
    const { scene, player } = ctx;
    const spawnConfig = ctx.spawns;
    this.targets = scene.physics.add.group();
    this.comboText = scene.add.text(scene.cameras.main.width / 2, scene.cameras.main.height - 215, '', {
      fontFamily: UI_THEME.fontFamily,
      fontSize: '20px',
      color: '#ffdf8a',
      stroke: '#0b1020',
      strokeThickness: 4,
    }).setOrigin(0.5).setScrollFactor(0).setDepth(resolveScreenUiDepth(10)).setAlpha(0);

    this.combo = new ComboSystem(ctx.nowMs, {
      onComboHit: (count, multiplier) => {
        this.comboText.setText(`${count}x COMBO  x${multiplier.toFixed(2)}`).setAlpha(1);
        scene.tweens.add({ targets: this.comboText, scale: { from: 1.2, to: 1 }, duration: 150, ease: 'Back.Out' });
      },
      onComboReset: () => this.comboText.setAlpha(0),
      onComboFinish: (count) => {
        floatingText.spawn(scene, player.x, player.y - 60, `${count}x FINISHER!`, 'yellow', true);
        gameFeel.play('combo-finisher');
      },
    });

    const equippedWeaponId = gameState.equippedWeaponId;
    if (equippedWeaponId) {
      const definition = getWeaponDefinition(equippedWeaponId);
      if (!ctx.mountManagedWeapon(equippedWeaponId)) throw new Error(`Weapon scene '${equippedWeaponId}' could not be mounted.`);
      this.weapon = definition;
    }

    if (ctx.enemySpawnAreas.length > 0 || spawnConfig) {
      this.spawner = new AuthoredEnemyPopulationController({
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
        worldWidth: ctx.dimensions.width,
        worldHeight: ctx.dimensions.height,
        createEnemyRuntime: ctx.createManagedEnemy,
        getSafeZones: () => this.safeZones(),
      });

      this.spawner.seed(Math.min(8, spawnConfig?.maxPopulation ?? 8));
    }
    scene.physics.add.collider(this.targets, ctx.collisionTiles);
    scene.physics.add.collider(player, this.targets);
  }

  update(time: number, delta: number): void {
    this.combo.update();
    this.spawner?.update(time, delta);
  }

  tryAttack(): boolean {
    if (!this.weapon || this.attacking || !this.ctx.canAttack()) return false;
    if (!this.ctx.canManagedWeaponAttack()) return false;
    const facing = this.ctx.getFacing();
    const direction = resolveAttackDirection(
      facing.lengthSq() > 0 ? facing : new Phaser.Math.Vector2(1, 0),
    );
    const stats = getStats();
    const scaledDamage = Math.round(resolveScaledValue(
      this.weapon.baseDamage * (stats.attack / 10),
      this.weapon.scaling?.damage,
      stats.attributes,
    ));
    const critical = Math.random() < stats.critChance;
    const damage = critical ? Math.round(scaledDamage * stats.critMult) : scaledDamage;
    const attacked = this.ctx.playManagedWeaponAttack(direction, {
      damage,
      knockbackStrength: resolveScaledValue(this.weapon.knockStrength, this.weapon.scaling?.knockback, stats.attributes),
      cooldownMs: resolveScaledValue(this.weapon.cooldownMs, this.weapon.scaling?.cooldown, stats.attributes, 1),
      weaponTags: [
        this.weapon.weaponId.includes('spear') ? 'spear' : 'weapon',
        ...Object.entries(this.weapon.harvestCapabilities ?? {}).map(([tag, tier]) => `harvest:${tag}:${tier}`),
      ],
      damageTypes: ['physical'],
    });
    if (attacked && critical) gameFeel.play('critical-hit');
    if (attacked) this.criticalAttack = critical;
    return attacked;
  }

  /**
   * One swing of a harvest tool picked for the tree or rock in front (roadmap
   * 4.10): the tool is mounted for this swing only, then the equipped weapon
   * comes back. The belt and the HUD never change.
   */
  tryToolAttack(toolId: string): boolean {
    if (this.attacking || !this.ctx.canAttack()) return false;
    const previous = this.weapon?.weaponId ?? null;
    if (previous === toolId) return this.tryAttack();
    if (!this.equipWeapon(toolId)) return false;
    if (this.tryAttack()) {
      this.restoreAfterToolSwing = { weaponId: previous };
      return true;
    }
    this.restoreWeapon(previous);
    return false;
  }

  private restoreWeapon(weaponId: string | null): void {
    if (weaponId) {
      this.equipWeapon(weaponId);
      return;
    }
    this.weapon = undefined;
    this.ctx.clearManagedWeapon();
  }

  equipWeapon(weaponId: string): boolean {
    if (this.attacking || weaponId === this.weapon?.weaponId) return !this.attacking;
    let next: NormalizedWeaponDefinition;
    try {
      next = getWeaponDefinition(weaponId);
      if (!this.ctx.mountManagedWeapon(weaponId)) return false;
    } catch {
      return false;
    }
    this.weapon = next;
    this.ctx.playCharacterAction('idle');
    return true;
  }

  equippedWeaponId(): string | null {
    return this.weapon?.weaponId ?? null;
  }

  transformManagedWeaponDamage(damage: number, target?: ManagedWeaponTarget): number {
    const modifier = resolveDamageModifier(this.weapon?.damageModifiers, target?.targetTags ?? []);
    return Math.max(0, Math.round(damage * modifier * this.combo.registerHit()));
  }

  onManagedWeaponOutcome(outcome: RoutedDamageOutcome, target: ManagedWeaponTarget | undefined): void {
    if (outcome.result.status !== 'accepted') return;
    const targetTags = target?.targetTags ?? [];
    if (targetTags.includes('resource')) return;
    if (this.criticalAttack && outcome.result.actualDamage > 0) {
      // One crit sting per swing, however many creatures it hits.
      this.criticalAttack = false;
      gameEvents.emit('weapon.critical-hit', {});
    }
    // A light hit-stop whenever the weapon lands on a creature.
    if (target && outcome.result.actualDamage > 0) {
      gameFeel.play('hit');
      particleFx.play('hit-spark', target.x, target.y - 12);
    }
    const effectId = this.weapon?.onHitEffectId;
    if (!target || !effectId || outcome.result.actualDamage <= 0) return;
    this.spawnEffect({
      effectId,
      direction: target.attackDirection,
      x: target.x,
      y: target.y,
      // Just above every attachment slot of the target so the impact draws in front of it.
      depth: target.depth !== undefined
        ? target.depth + MAX_ATTACHMENT_SLOT + 1
        : resolveWorldDepth(target.y, { stableId: target.receiverNodeId, attachmentSlot: 2 }).depth,
    });
  }

  onManagedEnemyDefeated(enemy: ManagedEnemyDefeat): void {
    this.awardEnemyDefeat(enemy);
  }

  spawnDummy(x: number, y: number): void {
    const dummy = new TargetDummy(this.ctx.scene, x, y);
    this.targets.add(dummy);
  }

  destroy(): void {
    this.ctx.clearManagedWeapon();
    this.ctx.setActionLocked(false);
    this.spawner?.destroy();
    this.combo.reset();
    this.comboText.destroy();
  }

  onManagedWeaponAttackStarted(weaponId: string, direction: WeaponAttackDirection): void {
    if (this.weapon?.weaponId !== weaponId) return;
    this.attacking = true;
    this.ctx.setActionLocked(true);
    this.ctx.player.setVelocity(0, 0);
    this.ctx.playCharacterAction(this.weapon.directionalAttacks[direction].characterActionId);
  }

  onManagedWeaponAttackFinished(weaponId: string): void {
    if (this.weapon?.weaponId !== weaponId) return;
    this.attacking = false;
    this.ctx.setActionLocked(false);
    this.ctx.playCharacterAction('idle');
    const restore = this.restoreAfterToolSwing;
    this.restoreAfterToolSwing = undefined;
    if (restore) this.restoreWeapon(restore.weaponId);
  }

  private safeZones(): MapEnemySafeZone[] {
    return [
      ...this.ctx.enemySafeZones,
      ...(this.ctx.spawns?.safeZones ?? []),
    ];
  }

  private spawnEffect(request: WorldEffectSpawnRequest): void {
    if (!this.ctx.spawnManagedEffect(request)) {
      throw new Error(`Effect scene '${request.effectId}' could not be spawned.`);
    }
  }

  private awardEnemyDefeat(enemy: ManagedEnemyDefeat): void {
    const { drop } = enemy.config;
    const { scene } = this.ctx;
    gameEvents.emit('enemy.died', {
      enemyId: enemy.enemyId,
      areaId: this.ctx.areaId,
      kind: enemy.config.id,
    });

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
