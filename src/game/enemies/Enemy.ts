import Phaser from 'phaser';
import { floatingText } from '../ui/FloatingText';
import { runState, type EnemyState, type EnemyAIConfig, type EnemySafeZone } from './EnemyAI';

/**
 * Enemy base class. Extends Arcade sprite with HP, a state-machine AI,
 * knockback, contact damage, telegraphed attacks, and death/drop logic.
 *
 * Enemy type instances are created by factory functions in the library/
 * folder; this class handles the shared lifecycle.
 */

export interface EnemyItemDrop {
  itemId: string;
  chance: number;
  count?: number;
}

export interface EnemyDrop {
  xp: number;
  coins: number;
  /** Each item rolls independently when the enemy dies. */
  items?: readonly EnemyItemDrop[];
}

export interface EnemyConfig {
  textureKey: string;
  maxHp: number;
  scale: number;
  bodyWidth: number;
  bodyHeight: number;
  ai: EnemyAIConfig;
  drop: EnemyDrop;
  /** Tint applied to the sprite (optional, for color variants). */
  tint?: number;
}

export interface EnemyContext {
  getPlayer: () => Phaser.Physics.Arcade.Sprite;
  onContactDamage: (enemy: Enemy, amount: number) => void;
  onDeath: (enemy: Enemy) => void;
  fireProjectile?: (x: number, y: number, dx: number, dy: number, speed: number) => void;
  getSafeZones?: () => EnemySafeZone[];
}

let enemyIdCounter = 0;

export class Enemy extends Phaser.Physics.Arcade.Sprite {
  public readonly enemyId: number;
  public readonly config: EnemyConfig;
  public maxHp: number;
  public hp: number;
  public dead = false;

  private aiState: EnemyState = 'idle';
  private ctx: EnemyContext;
  private healthBar: Phaser.GameObjects.Graphics;
  private hitFlashUntil = 0;
  private telegraphUntil = 0;
  private deathAt = 0;
  private wanderTimer = 0;
  private hitStunUntil = 0;

  constructor(scene: Phaser.Scene, x: number, y: number, config: EnemyConfig, ctx: EnemyContext) {
    super(scene, x, y, config.textureKey);
    this.enemyId = ++enemyIdCounter;
    this.config = config;
    this.ctx = ctx;
    this.maxHp = config.maxHp;
    this.hp = config.maxHp;

    scene.add.existing(this);
    scene.physics.add.existing(this);

    this.setDepth(8);
    this.setScale(config.scale);
    this.setCollideWorldBounds(true);

    if (config.tint !== undefined) {
      this.setTint(config.tint);
    }

    const body = this.body as Phaser.Physics.Arcade.Body;
    body.setSize(config.bodyWidth, config.bodyHeight);
    body.setBounce(0.2);
    body.setCollideWorldBounds(true);

    this.healthBar = scene.add.graphics().setDepth(40);
  }

  takeDamage(amount: number, knockX: number, knockY: number, knockStrength: number): void {
    if (this.dead) return;

    this.hp = Math.max(0, this.hp - amount);
    this.hitFlashUntil = this.scene.time.now + 120;
    this.setTintFill(0xff5a5a);

    const big = amount > 15;
    floatingText.spawn(this.scene, this.x, this.y - this.displayHeight / 2 - 8, `-${amount}`, big ? 'yellow' : 'white', big);

    // Knockback (reduced by resistance, with a base boost so every hit
    // produces a visible bash-back even on heavy enemies).
    const resist = this.config.ai.knockbackResist;
    const finalStrength = (knockStrength + 120) * (1 - resist);
    if (finalStrength > 0) {
      this.setVelocity(knockX * finalStrength, knockY * finalStrength);
    }

    // Hit-stun: freeze AI movement so the knockback actually pushes the enemy
    // back instead of being immediately overwritten by chase velocity.
    const stunMs = 320 + Math.min(280, finalStrength * 0.35);
    this.hitStunUntil = this.scene.time.now + stunMs;

    // Interrupt attack telegraph on hit.
    this.telegraphUntil = 0;

    if (this.hp <= 0) {
      this.die();
    }
  }

  private die(): void {
    this.dead = true;
    this.aiState = 'dead';
    this.setActive(false);
    this.setVelocity(0, 0);
    this.healthBar.clear();

    // Death particles.
    const dust = this.scene.add.particles(this.x, this.y, 'xp-orb', {
      lifespan: 400,
      speed: { min: 30, max: 80 },
      scale: { start: 0.3, end: 0 },
      alpha: { start: 0.6, end: 0 },
      quantity: 10,
      emitting: false,
    }).setDepth(7);
    dust.emitParticle(10);
    this.scene.time.delayedCall(450, () => dust.destroy());

    // Fade out + shrink, then remove.
    this.scene.tweens.add({
      targets: this,
      alpha: 0,
      scale: this.config.scale * 0.5,
      duration: 400,
      onComplete: () => {
        this.destroy();
      },
    });

    this.ctx.onDeath(this);
  }

  preUpdate(time: number, delta: number): void {
    super.preUpdate(time, delta);

    if (this.dead) return;

    // Hit flash recovery.
    if (this.hitFlashUntil > 0 && time > this.hitFlashUntil) {
      if (this.config.tint !== undefined) {
        this.setTint(this.config.tint);
      } else {
        this.clearTint();
      }
      this.hitFlashUntil = 0;
    }

    // Telegraph flash (red pulse before attacking).
    if (this.telegraphUntil > 0) {
      if (time < this.telegraphUntil) {
        // Pulsing red tint.
        const pulse = Math.sin(time * 0.03) * 0.5 + 0.5;
        this.setTint(Phaser.Display.Color.GetColor(255, Math.floor(90 + pulse * 50), 90));
      } else {
        if (this.config.tint !== undefined) {
          this.setTint(this.config.tint);
        } else {
          this.clearTint();
        }
        this.telegraphUntil = 0;
      }
    }

    // Run AI state machine — skip while in hit-stun so knockback isn't
    // immediately cancelled by chase/wander velocity.
    const player = this.ctx.getPlayer();
    if (!player || !player.active) {
      const body = this.body as Phaser.Physics.Arcade.Body;
      body.setVelocity(0, 0);
      return;
    }

    const inHitStun = time < this.hitStunUntil;

    if (inHitStun) {
      // Let the knockback velocity play out; light drag so the bash carries.
      const body = this.body as Phaser.Physics.Arcade.Body;
      body.velocity.scale(0.94);
      this.drawHealthBar();
      return;
    }

    const dx = player.x - this.x;
    const dy = player.y - this.y;
    const dist = Math.hypot(dx, dy);
    const dir = dist > 0 ? new Phaser.Math.Vector2(dx / dist, dy / dist) : new Phaser.Math.Vector2(0, 0);

    const nextState = runState(this.aiState, {
      enemy: this,
      player,
      time,
      delta,
      distToPlayer: dist,
      dirToPlayer: dir,
      config: this.config.ai,
      fireProjectile: this.ctx.fireProjectile
        ? (fx, fy, fdx, fdy) => this.ctx.fireProjectile!(fx, fy, fdx, fdy, this.config.ai.projectileSpeed ?? 200)
        : undefined,
      telegraph: (durationMs) => {
        this.telegraphUntil = time + durationMs;
      },
      safeZones: this.ctx.getSafeZones?.(),
    });

    if (nextState !== 'continue') {
      this.aiState = nextState;
    }

    // Contact damage: if overlapping the player, deal damage.
    if (dist < (this.config.bodyWidth * this.config.scale + 24) / 2) {
      this.ctx.onContactDamage(this, this.config.ai.contactDamage);
    }

    this.drawHealthBar();
  }

  private drawHealthBar(): void {
    const g = this.healthBar;
    g.clear();

    const w = Math.max(28, this.displayWidth * 0.8);
    const h = 4;
    const x = this.x - w / 2;
    const y = this.y - this.displayHeight / 2 - 8;

    g.fillStyle(0x0a1f15, 0.8);
    g.fillRoundedRect(x, y, w, h, 2);

    const pct = this.maxHp > 0 ? Phaser.Math.Clamp(this.hp / this.maxHp, 0, 1) : 0;
    const fill = pct <= 0.25 ? 0xff5a5a : pct <= 0.5 ? 0xff9a3c : 0xff6b6b;
    g.fillStyle(fill, 1);
    g.fillRoundedRect(x + 1, y + 1, Math.max(0, (w - 2) * pct), h - 2, 2);
  }

  destroy(fromScene?: boolean): void {
    this.healthBar.destroy();
    super.destroy(fromScene);
  }
}
