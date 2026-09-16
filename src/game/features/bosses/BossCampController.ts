import Phaser from 'phaser';

import { rejectedDamage, type DamageApplicationResult } from '../../combat/DamageableTarget';
import type { WeaponHitRequest } from '../../combat/WeaponHitRequest';
import { getBossDefinition } from '../../content/bosses/BossCatalog';
import type { MapBossCamp } from '../../content/maps/mapFormat';
import type { WorldProgress } from '../progression/WorldProgress';
import { BossHealthBar } from '../../ui/BossHealthBar';
import { FattyOneEyeBoss } from './FattyOneEyeBoss';
import type { FloatingTextColor } from '../../ui/FloatingText';
import { bossCampSpawnEligible, bossPerimeterContains, resolveBossCampSpawnSuppression } from './BossCampBehavior';

interface CampRuntime {
  readonly definition: MapBossCamp;
  boss?: FattyOneEyeBoss;
  healthBar?: BossHealthBar;
  observedOutsideAfterDefeat: boolean;
  pendingTransientReset: boolean;
  suppressSpawnUntilOutside: boolean;
}

export interface BossCampControllerContext {
  readonly scene: Phaser.Scene;
  readonly mapId: string;
  readonly camps: readonly MapBossCamp[];
  readonly player: Phaser.Physics.Arcade.Sprite;
  readonly collisionTiles: Phaser.Physics.Arcade.StaticGroup;
  readonly progress: WorldProgress;
  readonly isPlayerDodging: () => boolean;
  readonly applyPlayerDamage: (amount: number, source: string, impactX: number, impactY: number, knockbackStrength: number) => void;
  readonly showMessage: (x: number, y: number, message: string, color?: FloatingTextColor, important?: boolean) => void;
}

export class BossCampController {
  readonly targets: Phaser.Physics.Arcade.Group;

  private readonly records: CampRuntime[];
  private readonly colliders: Phaser.Physics.Arcade.Collider[];
  private nextRejectedMessageAt = 0;

  constructor(private readonly ctx: BossCampControllerContext) {
    this.targets = ctx.scene.physics.add.group({ allowGravity: false, immovable: true });
    this.records = ctx.camps.map((definition) => ({
      definition,
      observedOutsideAfterDefeat: ctx.progress.bossCampRespawnReadyAt(ctx.mapId, definition.id) === undefined,
      pendingTransientReset: false,
      suppressSpawnUntilOutside: false,
    }));
    this.colliders = [
      ctx.scene.physics.add.collider(this.targets, ctx.collisionTiles),
      ctx.scene.physics.add.collider(ctx.player, this.targets, (_player, target) => {
        if (target instanceof FattyOneEyeBoss) target.requestContactHop(ctx.scene.time.now);
      }),
    ];
  }

  update(time: number, deltaMs: number): void {
    const epochNow = Date.now();
    const resetThisUpdate = new Set(this.flushPendingTransientResets());
    for (const record of this.records) {
      if (resetThisUpdate.has(record)) continue;
      record.boss?.updateBoss(time, deltaMs);
      for (const resetRecord of this.flushPendingTransientResets()) resetThisUpdate.add(resetRecord);
      if (resetThisUpdate.has(record)) continue;
      record.healthBar?.update();
      if (record.boss && !record.boss.active) {
        record.boss = undefined;
        record.healthBar?.destroy();
        record.healthBar = undefined;
      }
      if (record.boss) continue;

      const respawnAt = this.ctx.progress.bossCampRespawnReadyAt(this.ctx.mapId, record.definition.id);
      const inside = bossPerimeterContains(record.definition.activationPerimeter, this.ctx.player.x, this.ctx.player.y);
      const suppression = resolveBossCampSpawnSuppression(record.suppressSpawnUntilOutside, inside);
      record.suppressSpawnUntilOutside = suppression.suppressSpawnUntilOutside;
      if (suppression.blocksSpawnThisUpdate) continue;
      if (respawnAt !== undefined && !inside) record.observedOutsideAfterDefeat = true;
      if (!bossCampSpawnEligible({
        hasLiveBoss: false,
        insideActivation: inside,
        respawnReadyAtEpochMs: respawnAt,
        observedOutsideAfterDefeat: record.observedOutsideAfterDefeat,
        epochNow,
      })) continue;
      this.spawn(record);
    }
  }

  isBossTarget(target: Phaser.GameObjects.GameObject): target is FattyOneEyeBoss {
    return target instanceof FattyOneEyeBoss && this.targets.contains(target);
  }

  applyWeaponHit(request: WeaponHitRequest): DamageApplicationResult {
    if (!this.isBossTarget(request.target)) return rejectedDamage('invalid');
    const result = request.target.applyWeaponHit(request);
    if (result.status === 'accepted') {
      this.ctx.showMessage(request.target.x, request.target.y - 72, `-${result.actualDamage}`, 'yellow', result.actualDamage >= 20);
      return result;
    }
    if (this.ctx.scene.time.now < this.nextRejectedMessageAt) return result;
    this.nextRejectedMessageAt = this.ctx.scene.time.now + 700;
    const definition = getBossDefinition(request.target.bossId);
    const message = result.reason === 'invulnerable'
      ? 'The eye is protected while Fatty is airborne!'
      : definition.allowedWeaponIds.includes(request.weaponId)
        ? 'Pierce the eye in the center!'
        : 'Only a spear can reach the center eye!';
    this.ctx.showMessage(request.target.x, request.target.y - 72, message, 'white', true);
    return result;
  }

  isChestLocked(instanceId: string): boolean {
    const record = this.records.find((candidate) => candidate.definition.guardedChestInstanceId === instanceId);
    return Boolean(record?.boss && !record.boss.dead);
  }

  resetActiveFights(): void {
    for (const record of this.records) {
      if (!record.boss || record.boss.dead) continue;
      record.pendingTransientReset = true;
    }
  }

  destroy(): void {
    this.colliders.forEach((collider) => collider.destroy());
    for (const record of this.records) {
      record.healthBar?.destroy();
      record.boss?.destroy();
    }
    this.targets.destroy(true);
  }

  private spawn(record: CampRuntime): void {
    const definition = getBossDefinition(record.definition.bossId);
    const boss = new FattyOneEyeBoss({
      scene: this.ctx.scene,
      definition,
      spawn: record.definition.spawn,
      arena: record.definition.arenaPerimeter,
      getPlayer: () => this.ctx.player,
      isPlayerDodging: this.ctx.isPlayerDodging,
      applyPlayerDamage: this.ctx.applyPlayerDamage,
      onDefeated: () => this.onDefeated(record),
    });
    this.targets.add(boss);
    record.boss = boss;
    record.healthBar = new BossHealthBar(this.ctx.scene, boss, definition.displayName);
    record.observedOutsideAfterDefeat = false;
    record.pendingTransientReset = false;
    record.suppressSpawnUntilOutside = false;
    this.ctx.progress.setBossCampRespawnReadyAt(this.ctx.mapId, record.definition.id, undefined);
  }

  private flushPendingTransientResets(): CampRuntime[] {
    const resetRecords: CampRuntime[] = [];
    for (const record of this.records) {
      if (!record.pendingTransientReset) continue;
      record.pendingTransientReset = false;
      if (!record.boss || record.boss.dead) continue;
      this.transientReset(record);
      resetRecords.push(record);
    }
    return resetRecords;
  }

  private transientReset(record: CampRuntime): void {
    record.boss?.destroy();
    record.healthBar?.destroy();
    record.boss = undefined;
    record.healthBar = undefined;
    record.observedOutsideAfterDefeat = true;
    record.pendingTransientReset = false;
    record.suppressSpawnUntilOutside = true;
  }

  private onDefeated(record: CampRuntime): void {
    record.pendingTransientReset = false;
    record.suppressSpawnUntilOutside = false;
    record.healthBar?.defeat();
    record.healthBar = undefined;
    record.observedOutsideAfterDefeat = false;
    this.ctx.progress.defeatBoss(record.definition.bossId);
    this.ctx.progress.setBossCampRespawnReadyAt(
      this.ctx.mapId,
      record.definition.id,
      Date.now() + record.definition.respawnMs,
    );
    this.ctx.showMessage(record.boss?.x ?? record.definition.spawn.x, (record.boss?.y ?? record.definition.spawn.y) - 84, 'Fatty One Eye defeated!', 'yellow', true);
  }
}
