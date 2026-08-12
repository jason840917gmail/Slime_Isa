import Phaser from 'phaser';
import { getStats } from '../systems/PlayerStats';
import { hitboxPool, type HitHandler, type HitboxActivationHandle, type HitboxConfig } from './Hitbox';
import { resolveScaledValue } from './CombatScaling';
import { LEGACY_WEAPON_SECTOR_ARC_RAD } from '../content/weapons/types';
import type {
  NormalizedLayeredAnimationDocument,
} from '../shared/animation';
import type {
  NormalizedWeaponDefinition,
  WeaponAttackDirection,
  WeaponAttackTrackDocument,
  WeaponHitboxDocument,
  WeaponPlaybackAnimationId,
} from '../content/weapons/types';
import { WeaponAttackTrackRunner, type WeaponTrackEvent } from './WeaponAttackTrackRunner';

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
  playWeaponAnimation: (animationId: WeaponPlaybackAnimationId, forceRestart?: boolean) => void;
  onWeaponEvent?: (event: WeaponTrackEvent) => void;
}

interface AttackSnapshot {
  readonly direction: Phaser.Math.Vector2;
  readonly attackDirection: WeaponAttackDirection;
  readonly hitboxes: Readonly<Record<string, WeaponHitboxDocument>>;
  readonly angle: number;
  readonly finalDamage: number;
  readonly isCrit: boolean;
  readonly knockStrength: number;
}

interface ActiveHitbox {
  readonly activationId: string;
  readonly handle: HitboxActivationHandle;
}

export function resolveWeaponAttackDirection(direction: Phaser.Math.Vector2): WeaponAttackDirection {
  if (Math.abs(direction.x) >= Math.abs(direction.y)) return direction.x < 0 ? 'left' : 'right';
  return direction.y < 0 ? 'up' : 'down';
}

function resolveDirectionalOffset(
  attackDirection: WeaponAttackDirection,
  offsetX: number,
  offsetY: number,
): readonly [number, number] {
  if (attackDirection === 'right') return [offsetX, offsetY];
  if (attackDirection === 'left') return [-offsetX, offsetY];
  if (attackDirection === 'up') return [offsetY, -offsetX];
  return [-offsetY, offsetX];
}

function resolveAttackVector(attackDirection: WeaponAttackDirection): Phaser.Math.Vector2 {
  if (attackDirection === 'right') return new Phaser.Math.Vector2(1, 0);
  if (attackDirection === 'left') return new Phaser.Math.Vector2(-1, 0);
  if (attackDirection === 'up') return new Phaser.Math.Vector2(0, -1);
  return new Phaser.Math.Vector2(0, 1);
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
  private trackRunner?: WeaponAttackTrackRunner;
  private readonly activeHitboxes = new Map<string, ActiveHitbox>();
  private attackSnapshot?: AttackSnapshot;
  private legacyEndTimer: Phaser.Time.TimerEvent | null = null;
  private attacking = false;
  private destroyed = false;

  constructor(def: WeaponDef, ctx: WeaponContext) {
    this.def = def;
    this.ctx = ctx;
    this.cooldownDurationMs = def.cooldownMs;
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
    const attackDirection = resolveWeaponAttackDirection(direction);
    const attackVector = resolveAttackVector(attackDirection);
    const directionalAttack = this.def.directionalAttacks[attackDirection];
    const snapshot: AttackSnapshot = {
      direction: attackVector,
      attackDirection,
      hitboxes: directionalAttack.hitboxes,
      angle: Math.atan2(attackVector.y, attackVector.x),
      finalDamage,
      isCrit,
      knockStrength: resolveScaledValue(this.def.knockStrength, this.def.scaling?.knockback, stats.attributes),
    };
    this.attackSnapshot = snapshot;
    this.attacking = true;

    this.cooldownDurationMs = resolveScaledValue(this.def.cooldownMs, this.def.scaling?.cooldown, stats.attributes, 1);
    this.cooldownUntil = time + this.cooldownDurationMs;

    this.ctx.onAttackStart();
    this.ctx.playCharacterAction(directionalAttack.characterActionId);
    this.ctx.playWeaponAnimation(`attack-${attackDirection}`, true);
    this.ctx.getPlayer().setVelocity(0, 0);

    if (snapshot.isCrit) this.ctx.scene.cameras.main.shake(80, 0.006);

    this.trackRunner?.destroy();
    this.trackRunner = directionalAttack.attackTrack
      ? this.createTrackRunner(directionalAttack.animation, directionalAttack.attackTrack)
      : undefined;
    if (this.trackRunner) {
      this.trackRunner.start(true);
    } else {
      this.activateAuthoredHitbox('primary', 'legacy:primary');
      const animDuration = Math.max(this.def.hitboxDurationMs, 200);
      this.legacyEndTimer = this.ctx.scene.time.delayedCall(animDuration, () => this.finishAttack());
    }
    return true;
  }

  private createTrackRunner(
    clip: NormalizedLayeredAnimationDocument,
    track: WeaponAttackTrackDocument,
  ): WeaponAttackTrackRunner {
    return new WeaponAttackTrackRunner(clip, track, {
      onHitboxActivated: (hitboxId, activationId) => this.activateAuthoredHitbox(hitboxId, activationId),
      onHitboxDeactivated: (hitboxId, activationId) => this.deactivateAuthoredHitbox(hitboxId, activationId),
      onEvent: (event) => {
        this.ctx.onWeaponEvent?.(event);
      },
      onComplete: () => this.finishAttack(),
    });
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
    const hitbox = snapshot?.hitboxes[hitboxId];
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
    const [resolvedOffsetX, resolvedOffsetY] = resolveDirectionalOffset(
      snapshot.attackDirection,
      hitbox.offsetX,
      hitbox.offsetY,
    );
    const x = player.x + resolvedOffsetX;
    const y = player.y + resolvedOffsetY;
    const damage = snapshot.finalDamage * (hitbox.damageMultiplier ?? 1);
    const knockStrength = snapshot.knockStrength * (hitbox.knockbackMultiplier ?? 1);

    if (hitbox.shape === 'sector') {
      const outerRadius = hitbox.outerRadius ?? hitbox.offsetX + hitbox.width / 2;
      const innerRadius = hitbox.innerRadius ?? 0;
      return {
        x,
        y,
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
        originX: x,
        originY: y,
        angle: snapshot.angle,
        arcWidth: hitbox.arcWidthRad ?? LEGACY_WEAPON_SECTOR_ARC_RAD,
        innerRadius,
        outerRadius,
        autoDeactivate: false,
      };
    }

    const radiusX = hitbox.radiusX ?? hitbox.radius ?? hitbox.width / 2;
    const radiusY = hitbox.radiusY ?? hitbox.radius ?? hitbox.height / 2;
    return {
      x,
      y,
      width: hitbox.shape === 'circle' ? radiusX * 2 : hitbox.width,
      height: hitbox.shape === 'circle' ? radiusY * 2 : hitbox.height,
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
}
