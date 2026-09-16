import Phaser from 'phaser';
import { ComboSystem } from '../../combat/ComboSystem';
import { resolveScaledValue } from '../../combat/CombatScaling';
import { TargetDummy } from '../../combat/TargetDummy';
import type { WeaponHitRequest } from '../../combat/WeaponHitRequest';
import type { DamageApplicationResult } from '../../combat/DamageableTarget';
import { gameEvents } from '../../core/EventBus';
import { gameState } from '../../core/GameState';
import { Enemy, type ProjectileReference } from '../../enemies/Enemy';
import {
  EnemySpawner,
  type EnemyPopulationMember,
  type EnemySpawnRequest,
} from '../../enemies/EnemySpawner';
import type { AnimatedVisual } from '../visuals/AnimatedVisual';
import { getEnemyConfig } from '../../enemies/library/EnemyTypes';
import { UI_THEME } from '../../presentation/theme';
import { getStats } from '../../systems/PlayerStats';
import { playerInventory } from '../../systems/Inventory';
import { floatingText } from '../../ui/FloatingText';
import { getWeaponDefinition } from '../../content/weapons/WeaponCatalog';
import { resolveWeaponPresentationOffsetY } from '../../content/weapons/presentation';
import {
  LEGACY_WEAPON_SECTOR_ARC_RAD,
  type NormalizedWeaponDefinition,
  type WeaponHitboxDocument,
} from '../../content/weapons/types';
import type { WorldDimensions } from '../../world/WorldDimensions';
import type { MapEnemySafeZone, MapEnemySpawnArea, MapSpawns } from '../../content/maps/mapFormat';
import { resolveScreenUiDepth, resolveWorldDepth } from '../../presentation/WorldDepth';
import { hitboxPool, type HitboxConfig, type HitboxTargets } from '../../combat/Hitbox';
import { ObjectAnimationAdapter } from '../objects/ObjectAnimationAdapter';
import { shouldSpawnConfirmedHitEffect } from '../../combat/ConfirmedHitEffect';
import { resolveResourceHitPresentation } from '../../combat/ResourceHitPresentation';
import type { ManagedWorldEffectSpawner, WorldEffectSpawnRequest } from '../effects/WorldEffectSpawn';
import { resolveDamageModifier } from '../../combat/DamageModifiers';
import type { ResourceNodeController } from '../resources/ResourceNodeController';
import { rejectedDamage } from '../../combat/DamageableTarget';
import type { RoutedDamageOutcome } from './DamageRouter';
import type {
  LegacyWeaponHitboxRequest,
  ManagedWeaponTarget,
  WeaponAttackDirection,
  WeaponDamagePayload,
} from '../scripts/WeaponScript';
import type { EnemyProjectileRequest } from '../scripts/EnemyScript';

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
  getBossTargets?: () => Phaser.Physics.Arcade.Group | null;
  isBossTarget?: (target: Phaser.GameObjects.GameObject) => boolean;
  applyBossHit?: (request: WeaponHitRequest) => DamageApplicationResult;
  createManagedEnemy?: (request: EnemySpawnRequest) => EnemyPopulationMember | null | undefined;
  spawnManagedEffect: ManagedWorldEffectSpawner;
  mountManagedWeapon: (weaponId: string) => boolean;
  canManagedWeaponAttack: (timeMs: number) => boolean;
  playManagedWeaponAttack: (direction: WeaponAttackDirection, timeMs: number, damage: WeaponDamagePayload) => boolean;
  spawnManagedEnemyProjectile: (request: EnemyProjectileRequest) => boolean;
  clearManagedWeapon: () => void;
}

function resolveAttackDirection(direction: Phaser.Math.Vector2): WeaponAttackDirection {
  if (Math.abs(direction.x) >= Math.abs(direction.y)) return direction.x < 0 ? 'left' : 'right';
  return direction.y < 0 ? 'up' : 'down';
}

function attackVector(direction: WeaponAttackDirection): Readonly<{ x: number; y: number }> {
  if (direction === 'left') return { x: -1, y: 0 };
  if (direction === 'up') return { x: 0, y: -1 };
  if (direction === 'down') return { x: 0, y: 1 };
  return { x: 1, y: 0 };
}

function directionalOffset(direction: WeaponAttackDirection, x: number, y: number): readonly [number, number] {
  if (direction === 'left') return [-x, y];
  if (direction === 'up') return [y, -x];
  if (direction === 'down') return [-y, x];
  return [x, y];
}

export interface ManagedEnemyDefeat {
  readonly enemyId: number;
  readonly config: Enemy['config'];
  readonly x: number;
  readonly y: number;
}

export class CombatController {
  readonly targets: Phaser.Physics.Arcade.Group;
  private weapon?: NormalizedWeaponDefinition;
  private combo: ComboSystem;
  private spawner?: EnemySpawner;
  private comboText: Phaser.GameObjects.Text;
  private attacking = false;
  private attackSequence = 0;

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

    this.combo = new ComboSystem(scene, {
      onComboHit: (count, multiplier) => {
        this.comboText.setText(`${count}x COMBO  x${multiplier.toFixed(2)}`).setAlpha(1);
        scene.tweens.add({ targets: this.comboText, scale: { from: 1.2, to: 1 }, duration: 150, ease: 'Back.Out' });
      },
      onComboReset: () => this.comboText.setAlpha(0),
      onComboFinish: (count) => {
        floatingText.spawn(scene, player.x, player.y - 60, `${count}x FINISHER!`, 'yellow', true);
        scene.cameras.main.shake(120, 0.008);
      },
    });

    const equippedWeaponId = gameState.equippedWeaponId;
    if (equippedWeaponId) {
      const definition = getWeaponDefinition(equippedWeaponId);
      if (!ctx.mountManagedWeapon(equippedWeaponId)) throw new Error(`Weapon scene '${equippedWeaponId}' could not be mounted.`);
      this.weapon = definition;
    }

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
        createEnemyRuntime: ctx.createManagedEnemy,
        getSafeZones: () => this.safeZones(),
        enemyContext: this.enemyContext(),
      });

      this.spawner.seed(Math.min(8, spawnConfig?.maxPopulation ?? 8));
    }
    scene.physics.add.collider(this.targets, ctx.collisionTiles);
    scene.physics.add.collider(player, this.targets);
  }

  update(time: number, delta: number): void {
    this.combo.update();
    this.spawner?.update(time, delta);
    hitboxPool.update(this.ctx.scene);
  }

  tryAttack(): boolean {
    if (!this.weapon || this.attacking || !this.ctx.canAttack()) return false;
    const timeMs = this.ctx.scene.time.now;
    if (!this.ctx.canManagedWeaponAttack(timeMs)) return false;
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
    const attacked = this.ctx.playManagedWeaponAttack(direction, timeMs, {
      damage,
      knockbackStrength: resolveScaledValue(this.weapon.knockStrength, this.weapon.scaling?.knockback, stats.attributes),
      cooldownMs: resolveScaledValue(this.weapon.cooldownMs, this.weapon.scaling?.cooldown, stats.attributes, 1),
      weaponTags: [this.weapon.weaponId.includes('spear') ? 'spear' : 'weapon'],
      damageTypes: ['physical'],
    });
    if (attacked && critical) this.ctx.scene.cameras.main.shake(80, 0.006);
    return attacked;
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

  transformManagedWeaponDamage(damage: number): number {
    return Math.max(0, Math.round(damage * this.combo.registerHit()));
  }

  onManagedWeaponOutcome(outcome: RoutedDamageOutcome, target: ManagedWeaponTarget | undefined): void {
    if (outcome.result.status !== 'accepted') return;
    this.applyLifeSteal(outcome.result.actualDamage);
    const effectId = this.weapon?.onHitEffectId;
    if (!target || !effectId || outcome.result.actualDamage <= 0) return;
    this.spawnEffect({
      effectId,
      direction: target.attackDirection,
      x: target.x,
      y: target.y,
      depth: resolveWorldDepth(target.y, { stableId: target.receiverNodeId, attachmentSlot: 2 }).depth,
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
    this.attackSequence += 1;
    this.ctx.setActionLocked(true);
    this.ctx.player.setVelocity(0, 0);
    this.ctx.playCharacterAction(this.weapon.directionalAttacks[direction].characterActionId);
  }

  onManagedWeaponAttackFinished(weaponId: string): void {
    if (this.weapon?.weaponId !== weaponId) return;
    this.attacking = false;
    this.ctx.setActionLocked(false);
    this.ctx.playCharacterAction('idle');
  }

  activateLegacyWeaponHitbox(request: LegacyWeaponHitboxRequest): () => void {
    const weapon = this.weapon;
    if (!weapon || weapon.weaponId !== request.weaponId) return () => undefined;
    const hitbox = weapon.directionalAttacks[request.attackDirection].hitboxes[request.hitboxId];
    if (!hitbox) return () => undefined;
    const config = this.legacyHitboxConfig(hitbox, request, weapon);
    const resourceTargets = this.ctx.getResourceTargets?.();
    const bossTargets = this.ctx.getBossTargets?.();
    const targets: HitboxTargets = [this.targets, ...(resourceTargets ? [resourceTargets] : []), ...(bossTargets ? [bossTargets] : [])];
    const vector = attackVector(request.attackDirection);
    const handle = hitboxPool.spawn(this.ctx.scene, targets, config, (target, damage, knockX, knockY, knockStrength) => {
      this.applyLegacyWeaponHit({
        target,
        damage,
        knockX,
        knockY,
        knockStrength,
        weaponId: weapon.weaponId,
        hitboxId: request.hitboxId,
        attackDirection: request.attackDirection,
        attackVector: [vector.x, vector.y],
        playbackId: this.attackSequence,
        hitbox: config,
      }, weapon);
    });
    return () => handle.deactivate();
  }

  private applyLegacyWeaponHit(hitRequest: WeaponHitRequest, weapon: NormalizedWeaponDefinition): DamageApplicationResult {
    const { target, damage, knockX, knockY, knockStrength, attackDirection } = hitRequest;
    const isResourceTarget = this.ctx.resourceNodes?.isResourceTarget(target) === true;
    const isBossTarget = this.ctx.isBossTarget?.(target) === true;
    const targetTags = target instanceof Enemy
      ? ['enemy']
      : isBossTarget
        ? ['enemy', 'boss']
      : isResourceTarget
        ? this.ctx.resourceNodes!.tagsFor(target)
        : [];
    if (isResourceTarget) {
      const requirement = this.ctx.resourceNodes!.harvestRequirementFor(target);
      const capabilityTier = requirement
        ? weapon.harvestCapabilities?.[requirement.targetTag] ?? 0
        : 0;
      if (requirement && capabilityTier < requirement.minimumTier) {
        this.ctx.resourceNodes!.showHarvestFailure(target, requirement.failureMessage);
        return rejectedDamage('invalid');
      }
    }
    const damageModifier = resolveDamageModifier(weapon.damageModifiers, targetTags);
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
    let hitTarget: Enemy | TargetDummy | (Phaser.GameObjects.GameObject & { readonly x: number; readonly y: number; readonly depth: number }) | undefined;
    if (target instanceof Enemy) {
      hitTarget = target;
      result = target.applyDamage({ amount: finalDamage, knockX, knockY, knockStrength });
      this.applyLifeSteal(result.actualDamage);
    } else if (target instanceof TargetDummy) {
      hitTarget = target;
      result = target.applyDamage({ amount: finalDamage, knockX, knockY, knockStrength });
    } else if (isBossTarget && this.ctx.applyBossHit) {
      hitTarget = target as Phaser.GameObjects.GameObject & { readonly x: number; readonly y: number; readonly depth: number };
      result = this.ctx.applyBossHit({ ...hitRequest, damage: finalDamage });
      this.applyLifeSteal(result.actualDamage);
    } else if (isResourceTarget) {
      result = this.ctx.resourceNodes!.applyDamage(target, finalDamage);
    } else {
      result = rejectedDamage('invalid');
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
    const resourceHitPresentation = acceptedObjectEvent
      ? resolveResourceHitPresentation(acceptedObjectEvent)
      : 'none';
    if (acceptedObjectEvent && resourceHitPresentation === 'deplete') {
      this.ctx.resourceNodes?.completeDepletion(acceptedObjectEvent.target);
    } else if (acceptedObjectEvent && resourceHitPresentation === 'animate-hit') {
      (acceptedObjectEvent.target.getData('objectAnimationAdapter') as ObjectAnimationAdapter | undefined)
        ?.animateOnHit(acceptedObjectEvent.onHitAnimationId);
    }
    if (hitTarget && shouldSpawnConfirmedHitEffect(weapon.onHitEffectId, result)) {
      this.spawnEffect({
        effectId: weapon.onHitEffectId!,
        direction: attackDirection,
        x: hitTarget.x,
        y: hitTarget.y,
        depth: hitTarget.depth + 0.2,
        followPositionOf: hitTarget,
        followDepthOffset: 0.2,
      });
    } else if (resourceHitAnchor && shouldSpawnConfirmedHitEffect(resourceHitEffectId, result)) {
      this.spawnEffect({
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
  }

  private legacyHitboxConfig(
    hitbox: WeaponHitboxDocument,
    request: LegacyWeaponHitboxRequest,
    weapon: NormalizedWeaponDefinition,
  ): HitboxConfig {
    const [offsetX, offsetY] = directionalOffset(request.attackDirection, hitbox.offsetX, hitbox.offsetY);
    const presentationOffsetY = weapon.directionalAttacks[request.attackDirection].presentationOffsetY
      ?? resolveWeaponPresentationOffsetY(weapon.directionalAttacks[request.attackDirection].mirrorY);
    const x = this.ctx.player.x + offsetX;
    const y = this.ctx.player.y + offsetY + presentationOffsetY;
    const vector = attackVector(request.attackDirection);
    if (hitbox.shape === 'sector') {
      const outerRadius = hitbox.outerRadius ?? hitbox.offsetX + hitbox.width / 2;
      return {
        x, y, width: outerRadius * 2, height: outerRadius * 2,
        damage: request.damage, durationMs: 1000,
        knockX: vector.x, knockY: vector.y, knockStrength: request.knockbackStrength,
        vfxColor: weapon.vfxColor, showVfx: false, shape: 'sector',
        originX: x, originY: y, angle: Math.atan2(vector.y, vector.x),
        arcWidth: hitbox.arcWidthRad ?? LEGACY_WEAPON_SECTOR_ARC_RAD,
        innerRadius: hitbox.innerRadius ?? 0, outerRadius, autoDeactivate: false,
      };
    }
    const radiusX = hitbox.radiusX ?? hitbox.radius ?? hitbox.width / 2;
    const radiusY = hitbox.radiusY ?? hitbox.radius ?? hitbox.height / 2;
    return {
      x, y,
      width: hitbox.shape === 'circle' ? radiusX * 2 : hitbox.width,
      height: hitbox.shape === 'circle' ? radiusY * 2 : hitbox.height,
      radiusX, radiusY,
      damage: request.damage, durationMs: 1000,
      knockX: vector.x, knockY: vector.y, knockStrength: request.knockbackStrength,
      vfxColor: weapon.vfxColor, showVfx: false,
      shape: hitbox.shape === 'rectangle' ? 'rect' : hitbox.shape,
      autoDeactivate: false,
    };
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
        if (!projectile.projectileId) throw new Error('Enemy projectile must reference an authored projectile scene.');
        this.ctx.spawnManagedEnemyProjectile({
          sourceNodeId: 'legacy.enemy',
          projectileId: projectile.projectileId,
          ...(projectile.assetId ? { assetId: projectile.assetId } : {}),
          position: { x, y },
          direction: { x: dx, y: dy },
          speed,
          damage,
          knockbackStrength,
        });
      },
    };
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

  private applyLifeSteal(damageDealt: number): void {
    const percentage = getStats().lifeStealPct;
    if (damageDealt <= 0 || percentage <= 0) return;
    const healed = this.ctx.healPlayer(Math.ceil(damageDealt * percentage));
    if (healed > 0) floatingText.spawn(this.ctx.scene, this.ctx.player.x, this.ctx.player.y - 36, `+${healed}`, 'green');
  }

  private onEnemyDeath(enemy: Enemy): void {
    this.awardEnemyDefeat(enemy);
  }

  private awardEnemyDefeat(enemy: ManagedEnemyDefeat): void {
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
