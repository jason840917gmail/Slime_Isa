import Phaser from 'phaser';
import { getStats } from '../systems/PlayerStats';
import { hitboxPool, type HitHandler } from './Hitbox';
import { resolveBodyBottom, resolveWorldDepth } from '../presentation/WorldDepth';

const SWING_VISUAL_PADDING = 8;

/**
 * Abstract weapon base. Each weapon defines its attack shape (hitbox),
 * animation key, cooldown, and VFX. The actual damage application is delegated
 * to a HitHandler passed in from the scene (so enemies/friends/bosses are
 * handled in one place).
 *
 * Phase 2 ships the Goo Gauntlet (starter melee). More weapons are added in
 * the same pattern (see weapons/library/).
 */

export type WeaponId = 'goo-gauntlet' | 'splat-spear' | 'bouncy-bow' | 'sticky-whip' | 'bubble-wand' | 'slam-hammer';

export interface WeaponDef {
  id: WeaponId;
  name: string;
  /** Runtime animation key to play on attack (from the player's visual set). */
  animKey: string;
  /** Base damage before stat scaling. */
  baseDamage: number;
  /** Cooldown between attacks in ms. */
  cooldownMs: number;
  /** Hitbox dimensions relative to the player. */
  hitboxWidth: number;
  hitboxHeight: number;
  /** Distance from player center to hitbox center. */
  hitboxOffset: number;
  /** How long the hitbox lives in ms. */
  hitboxDurationMs: number;
  /** Knockback strength. */
  knockStrength: number;
  /** VFX color for the slash rect. */
  vfxColor: number;
  /** Unlock level (1 = starter). */
  unlockLevel: number;
  /** Icon texture key (from BootScene). */
  iconKey: string;
  description: string;
}

export interface WeaponContext {
  scene: Phaser.Scene;
  getPlayer: () => Phaser.Physics.Arcade.Sprite;
  getFacing: () => Phaser.Math.Vector2;
  getTargets: () => Phaser.GameObjects.Group | Phaser.Physics.Arcade.Group | Phaser.Physics.Arcade.StaticGroup | null;
  hitHandler: HitHandler;
  onAttackStart: () => void;
  onAttackEnd: () => void;
  playAnimation: (key: string) => void;
}

export class Weapon {
  public readonly def: WeaponDef;
  protected ctx: WeaponContext;
  private cooldownUntil = 0;

  constructor(def: WeaponDef, ctx: WeaponContext) {
    this.def = def;
    this.ctx = ctx;
  }

  get id(): WeaponId {
    return this.def.id;
  }

  get name(): string {
    return this.def.name;
  }

  get iconKey(): string {
    return this.def.iconKey;
  }

  isReady(time: number): boolean {
    return time >= this.cooldownUntil;
  }

  cooldownProgress(time: number): number {
    if (time >= this.cooldownUntil) return 1;
    const total = this.def.cooldownMs;
    const remaining = this.cooldownUntil - time;
    return Phaser.Math.Clamp(1 - remaining / total, 0, 1);
  }

  attack(time: number): boolean {
    const scene = this.ctx.scene;
    if (!this.isReady(time)) return false;

    const player = this.ctx.getPlayer();

    // Facing is captured once so the attack direction stays locked.
    const dir = this.ctx.getFacing().lengthSq() > 0
      ? this.ctx.getFacing().clone().normalize()
      : new Phaser.Math.Vector2(1, 0);

    const stats = getStats();
    const damage = Math.round(this.def.baseDamage * (stats.attack / 10));
    const isCrit = Math.random() < stats.critChance;
    const finalDamage = isCrit ? Math.round(damage * stats.critMult) : damage;

    // Hit shape uses the same crescent sector as the drawn slash. This keeps
    // diagonal/up/down swings aligned with what the player sees.
    const reachMult = stats.weaponReachMult;
    const totalReach = (this.def.hitboxOffset + this.def.hitboxWidth / 2) * reachMult;
    const outerRadius = totalReach + SWING_VISUAL_PADDING;
    const angle = Math.atan2(dir.y, dir.x);
    const arcWidth = stats.weaponArcRad;

    const targets = this.ctx.getTargets();
    if (targets) {
      hitboxPool.spawn(scene, targets, {
        x: player.x,
        y: player.y,
        width: outerRadius * 2,
        height: outerRadius * 2,
        damage: finalDamage,
        durationMs: this.def.hitboxDurationMs,
        knockX: dir.x,
        knockY: dir.y,
        knockStrength: this.def.knockStrength,
        vfxColor: this.def.vfxColor,
        showVfx: false,
        shape: 'sector',
        originX: player.x,
        originY: player.y,
        angle,
        arcWidth,
        innerRadius: 0,
        outerRadius,
      }, this.ctx.hitHandler);
    }

    // Play attack animation.
    this.ctx.playAnimation(this.def.animKey);
    this.ctx.onAttackStart();

    // Sword-swing VFX: a crescent arc that sweeps from the player outward.
    this.spawnSwingVfx(player, dir, isCrit);

    // Crit flash.
    if (isCrit) {
      scene.cameras.main.shake(80, 0.006);
    }

    const animDuration = Math.max(this.def.hitboxDurationMs, 200);
    scene.time.delayedCall(animDuration, () => {
      this.ctx.onAttackEnd();
    });

    this.cooldownUntil = time + this.def.cooldownMs;
    return true;
  }

  protected spawnSwingVfx(player: Phaser.Physics.Arcade.Sprite, dir: Phaser.Math.Vector2, isCrit: boolean): void {
    const scene = this.ctx.scene;
    const angle = Math.atan2(dir.y, dir.x);
    const stats = getStats();
    const reach = (this.def.hitboxOffset + this.def.hitboxWidth / 2) * stats.weaponReachMult;
    const color = isCrit ? 0xffdf8a : this.def.vfxColor;
    const px = player.x;
    const py = player.y;
    const outerR = reach + SWING_VISUAL_PADDING;
    const innerR = 8; // starts from the player's body, not from inside
    const arcWidth = stats.weaponArcRad;

    // Crescent slash trail centered on the player, oriented to the attack dir.
    const swing = scene.add.graphics().setDepth(resolveWorldDepth(resolveBodyBottom(player.body as Phaser.Physics.Arcade.Body), {
      stableId: 'player-swing',
      attachmentSlot: 2,
    }).depth);
    swing.fillStyle(color, 0.45);
    swing.beginPath();
    swing.arc(px, py, outerR, angle - arcWidth / 2, angle + arcWidth / 2, false);
    swing.arc(px, py, innerR, angle + arcWidth / 2, angle - arcWidth / 2, true);
    swing.closePath();
    swing.fillPath();

    // Bright leading edge.
    swing.lineStyle(3, color, 0.9);
    swing.beginPath();
    swing.arc(px, py, reach, angle - arcWidth / 2, angle + arcWidth / 2, false);
    swing.strokePath();

    // Flash + fade â€” the slash appears and vanishes in ~160ms.
    scene.tweens.add({
      targets: swing,
      alpha: { from: 1, to: 0 },
      duration: 160,
      ease: 'Quad.Out',
      onComplete: () => swing.destroy(),
    });
  }
}
