import Phaser from 'phaser';
import { getStats } from '../systems/PlayerStats';
import { hitboxPool, type HitHandler, type HitboxActivationHandle, type HitboxConfig } from './Hitbox';
import { resolveBodyBottom, resolveWorldDepth } from '../presentation/WorldDepth';
import { resolveScaledValue } from './CombatScaling';
import type { NormalizedWeaponDefinition, WeaponHitboxDocument } from '../content/weapons/types';
import { WeaponAttackTrackRunner, type WeaponTrackEvent } from './WeaponAttackTrackRunner';

const SWING_VISUAL_PADDING = 8;

export type WeaponId = string;
export type WeaponDef = NormalizedWeaponDefinition;

export interface WeaponContext {
  scene: Phaser.Scene;
  getPlayer: () => Phaser.Physics.Arcade.Sprite;
  getFacing: () => Phaser.Math.Vector2;
  getTargets: () => Phaser.GameObjects.Group | Phaser.Physics.Arcade.Group | Phaser.Physics.Arcade.StaticGroup | null;
  hitHandler: HitHandler;
  onAttackStart: () => void;
  onAttackEnd: () => void;
  playCharacterAction: (actionId: string) => void;
  playWeaponAnimation: (animationId: 'idle' | 'attack' | 'impact', forceRestart?: boolean) => void;
  onWeaponEvent?: (event: WeaponTrackEvent) => void;
}

interface AttackSnapshot {
  readonly direction: Phaser.Math.Vector2;
  readonly angle: number;
  readonly arcWidth: number;
  readonly finalDamage: number;
  readonly isCrit: boolean;
  readonly knockStrength: number;
  readonly reachMultiplier: number;
}

interface ActiveHitbox {
  readonly activationId: string;
  readonly handle: HitboxActivationHandle;
}

/**
 * Owns weapon gameplay timing. The weapon visual is deliberately separate:
 * this class only tells it which clip to play and when authored events fire.
 */
export class Weapon {
  public readonly def: WeaponDef;
  protected ctx: WeaponContext;
  private cooldownUntil = 0;
  private cooldownDurationMs: number;
  private readonly trackRunner?: WeaponAttackTrackRunner;
  private readonly activeHitboxes = new Map<string, ActiveHitbox>();
  private attackSnapshot?: AttackSnapshot;
  private legacyEndTimer: Phaser.Time.TimerEvent | null = null;
  private attacking = false;
  private destroyed = false;

  constructor(def: WeaponDef, ctx: WeaponContext) {
    this.def = def;
    this.ctx = ctx;
    this.cooldownDurationMs = def.cooldownMs;
    if (def.attackTrack) {
      this.trackRunner = new WeaponAttackTrackRunner(def.animations.attack, def.attackTrack, {
        onHitboxActivated: (hitboxId, activationId) => this.activateAuthoredHitbox(hitboxId, activationId),
        onHitboxDeactivated: (hitboxId, activationId) => this.deactivateAuthoredHitbox(hitboxId, activationId),
        onEvent: (event) => {
          if (event.eventId === 'weapon.impact') this.ctx.playWeaponAnimation('impact', true);
          this.ctx.onWeaponEvent?.(event);
        },
        onComplete: () => this.finishAttack(),
      });
    }
  }

  get id(): WeaponId {
    return this.def.weaponId;
  }

  get name(): string {
    return this.def.displayName;
  }

  get iconKey(): string {
    return this.def.iconKey;
  }

  isReady(time: number): boolean {
    return time >= this.cooldownUntil;
  }

  cooldownProgress(time: number): number {
    if (time >= this.cooldownUntil) return 1;
    const total = this.cooldownDurationMs;
    const remaining = this.cooldownUntil - time;
    return Phaser.Math.Clamp(1 - remaining / total, 0, 1);
  }

  attack(time: number): boolean {
    if (this.destroyed || this.attacking || !this.isReady(time)) return false;

    const stats = getStats();
    const direction = this.ctx.getFacing().lengthSq() > 0
      ? this.ctx.getFacing().clone().normalize()
      : new Phaser.Math.Vector2(1, 0);
    const damage = Math.round(resolveScaledValue(
      this.def.baseDamage * (stats.attack / 10),
      this.def.scaling?.damage,
      stats.attributes,
    ));
    const isCrit = Math.random() < stats.critChance;
    const finalDamage = isCrit ? Math.round(damage * stats.critMult) : damage;
    const reachMultiplier = stats.weaponReachMult * resolveScaledValue(1, this.def.scaling?.reach, stats.attributes);
    const snapshot: AttackSnapshot = {
      direction,
      angle: Math.atan2(direction.y, direction.x),
      arcWidth: stats.weaponArcRad,
      finalDamage,
      isCrit,
      knockStrength: resolveScaledValue(this.def.knockStrength, this.def.scaling?.knockback, stats.attributes),
      reachMultiplier,
    };
    this.attackSnapshot = snapshot;
    this.attacking = true;

    this.cooldownDurationMs = resolveScaledValue(this.def.cooldownMs, this.def.scaling?.cooldown, stats.attributes, 1);
    this.cooldownUntil = time + this.cooldownDurationMs;

    this.ctx.onAttackStart();
    this.ctx.playCharacterAction(this.def.characterActionId);
    this.ctx.playWeaponAnimation('attack', true);
    this.ctx.getPlayer().setVelocity(0, 0);
    this.spawnSwingVfx(this.ctx.getPlayer(), snapshot);

    if (snapshot.isCrit) this.ctx.scene.cameras.main.shake(80, 0.006);

    if (this.trackRunner) {
      this.trackRunner.start(true);
    } else {
      this.activateAuthoredHitbox('primary', 'legacy:primary');
      const animDuration = Math.max(this.def.hitboxDurationMs, 200);
      this.legacyEndTimer = this.ctx.scene.time.delayedCall(animDuration, () => this.finishAttack());
    }
    return true;
  }

  update(delta: number): void {
    this.trackRunner?.update(delta);
  }

  cancel(): void {
    this.legacyEndTimer?.remove();
    this.legacyEndTimer = null;
    this.trackRunner?.cancel();
    this.deactivateAllHitboxes();
    if (this.attacking) this.finishAttack();
  }

  destroy(): void {
    if (this.destroyed) return;
    this.cancel();
    this.trackRunner?.destroy();
    this.destroyed = true;
  }

  private activateAuthoredHitbox(hitboxId: string, activationId: string): void {
    const snapshot = this.attackSnapshot;
    const hitbox = this.def.hitboxes[hitboxId];
    const targets = this.ctx.getTargets();
    if (!snapshot || !hitbox || !targets) return;

    const handle = hitboxPool.spawn(
      this.ctx.scene,
      targets,
      this.toHitboxConfig(hitbox, snapshot),
      this.ctx.hitHandler,
    );
    this.activeHitboxes.set(hitboxId, { activationId, handle });
  }

  private deactivateAuthoredHitbox(hitboxId: string, activationId: string): void {
    const active = this.activeHitboxes.get(hitboxId);
    if (!active || active.activationId !== activationId) return;
    active.handle.deactivate();
    this.activeHitboxes.delete(hitboxId);
  }

  private deactivateAllHitboxes(): void {
    for (const active of this.activeHitboxes.values()) active.handle.deactivate();
    this.activeHitboxes.clear();
  }

  private finishAttack(): void {
    if (!this.attacking) return;
    this.legacyEndTimer?.remove();
    this.legacyEndTimer = null;
    this.deactivateAllHitboxes();
    this.attacking = false;
    this.attackSnapshot = undefined;
    this.ctx.onAttackEnd();
  }

  private toHitboxConfig(hitbox: WeaponHitboxDocument, snapshot: AttackSnapshot): HitboxConfig {
    const player = this.ctx.getPlayer();
    const offsetX = hitbox.offsetX * snapshot.reachMultiplier;
    const offsetY = hitbox.offsetY * snapshot.reachMultiplier;
    const x = player.x + offsetX * snapshot.direction.x - offsetY * snapshot.direction.y;
    const y = player.y + offsetX * snapshot.direction.y + offsetY * snapshot.direction.x;
    const damage = snapshot.finalDamage * (hitbox.damageMultiplier ?? 1);
    const knockStrength = snapshot.knockStrength * (hitbox.knockbackMultiplier ?? 1);

    if (hitbox.shape === 'sector') {
      const outerRadius = (hitbox.outerRadius ?? hitbox.offsetX + hitbox.width / 2) * snapshot.reachMultiplier;
      const innerRadius = (hitbox.innerRadius ?? 0) * snapshot.reachMultiplier;
      return {
        x: player.x,
        y: player.y,
        width: outerRadius * 2,
        height: outerRadius * 2,
        damage,
        durationMs: 1000,
        knockX: snapshot.direction.x,
        knockY: snapshot.direction.y,
        knockStrength,
        vfxColor: this.def.vfxColor,
        showVfx: false,
        shape: 'sector',
        originX: player.x,
        originY: player.y,
        angle: snapshot.angle,
        arcWidth: hitbox.arcWidthRad ?? snapshot.arcWidth,
        innerRadius,
        outerRadius,
        autoDeactivate: false,
      };
    }

    const radiusX = (hitbox.radiusX ?? hitbox.radius ?? hitbox.width / 2) * snapshot.reachMultiplier;
    const radiusY = (hitbox.radiusY ?? hitbox.radius ?? hitbox.height / 2) * snapshot.reachMultiplier;
    return {
      x,
      y,
      width: hitbox.shape === 'circle' ? radiusX * 2 : hitbox.width * snapshot.reachMultiplier,
      height: hitbox.shape === 'circle' ? radiusY * 2 : hitbox.height * snapshot.reachMultiplier,
      radiusX,
      radiusY,
      damage,
      durationMs: 1000,
      knockX: snapshot.direction.x,
      knockY: snapshot.direction.y,
      knockStrength,
      vfxColor: this.def.vfxColor,
      showVfx: false,
      shape: hitbox.shape === 'rectangle' ? 'rect' : hitbox.shape,
      autoDeactivate: false,
    };
  }

  protected spawnSwingVfx(player: Phaser.Physics.Arcade.Sprite, snapshot: AttackSnapshot): void {
    const scene = this.ctx.scene;
    const visualOffset = this.def.visual.sourceOffset;
    const px = player.x + visualOffset[0] * snapshot.direction.x - visualOffset[1] * snapshot.direction.y;
    const py = player.y + visualOffset[0] * snapshot.direction.y + visualOffset[1] * snapshot.direction.x;
    const primary = this.def.hitboxes.primary ?? Object.values(this.def.hitboxes)[0];
    const reach = (primary?.outerRadius ?? this.def.hitboxOffset + this.def.hitboxWidth / 2) * snapshot.reachMultiplier;
    const color = snapshot.isCrit ? 0xffdf8a : this.def.vfxColor;
    const outerR = reach + SWING_VISUAL_PADDING;
    const innerR = 8;

    const swing = scene.add.graphics().setDepth(resolveWorldDepth(resolveBodyBottom(player.body as Phaser.Physics.Arcade.Body), {
      stableId: 'player-swing',
      attachmentSlot: 2,
    }).depth);
    swing.fillStyle(color, 0.45);
    swing.beginPath();
    swing.arc(px, py, outerR, snapshot.angle - snapshot.arcWidth / 2, snapshot.angle + snapshot.arcWidth / 2, false);
    swing.arc(px, py, innerR, snapshot.angle + snapshot.arcWidth / 2, snapshot.angle - snapshot.arcWidth / 2, true);
    swing.closePath();
    swing.fillPath();
    swing.lineStyle(3, color, 0.9);
    swing.beginPath();
    swing.arc(px, py, reach, snapshot.angle - snapshot.arcWidth / 2, snapshot.angle + snapshot.arcWidth / 2, false);
    swing.strokePath();
    scene.tweens.add({
      targets: swing,
      alpha: { from: 1, to: 0 },
      duration: 160,
      ease: 'Quad.Out',
      onComplete: () => swing.destroy(),
    });
  }
}
