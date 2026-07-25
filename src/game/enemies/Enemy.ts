import Phaser from 'phaser';

import type { AssetId } from '../infrastructure/assets/manifest';
import { getAsset } from '../infrastructure/assets/manifest';
import { getVisualClip, getVisualSet, type VisualSetId } from '../content/visuals/VisualCatalog';
import { AnimatedVisual } from '../features/visuals/AnimatedVisual';
import { floatingText } from '../ui/FloatingText';
import { runState, type EnemyState, type EnemyAIConfig, type EnemySafeZone } from './EnemyAI';

export interface EnemyItemDrop {
  itemId: string;
  chance: number;
  count?: number;
}

export interface EnemyDrop {
  xp: number;
  coins: number;
  items?: readonly EnemyItemDrop[];
}

export interface EnemyConfig {
  id: string;
  visualSetId: VisualSetId;
  maxHp: number;
  body: {
    width: number;
    height: number;
    centerOffsetX: number;
    centerOffsetY: number;
  };
  ai: EnemyAIConfig;
  drop: EnemyDrop;
  projectile?: {
    assetId: AssetId;
    damage: number;
  };
  impactEffect?: {
    visualSetId: VisualSetId;
    clipId: string;
    distance: number;
  };
}

export interface EnemyContext {
  getPlayer: () => Phaser.Physics.Arcade.Sprite;
  onContactDamage: (enemy: Enemy, amount: number) => void;
  onDeath: (enemy: Enemy) => void;
  fireProjectile?: (
    x: number,
    y: number,
    dx: number,
    dy: number,
    speed: number,
    assetId: AssetId,
    damage: number,
    knockbackStrength: number,
  ) => void;
  getSafeZones?: () => EnemySafeZone[];
}

type VisualDirection = 'side' | 'up' | 'down';
type VisualAction = 'idle' | 'walk' | 'attack' | 'knockback' | 'die';

let enemyIdCounter = 0;

export class Enemy extends Phaser.Physics.Arcade.Sprite {
  readonly enemyId: number;
  readonly config: EnemyConfig;
  readonly maxHp: number;
  hp: number;
  dead = false;

  private aiState: EnemyState = 'idle';
  private readonly ctx: EnemyContext;
  private readonly healthBar: Phaser.GameObjects.Graphics;
  private readonly visual: AnimatedVisual;
  private direction: VisualDirection = 'down';
  private sideFlipped = false;
  private currentClipId = '';
  private hitFlashUntil = 0;
  private hitStunUntil = 0;
  private attackActive = false;
  private attackReadyAt = 0;
  private attackSequenceId = 0;
  private attackVector = new Phaser.Math.Vector2(0, 1);
  private attackTimers: Phaser.Time.TimerEvent[] = [];
  private deathTimer?: Phaser.Time.TimerEvent;
  private deathFinishing = false;

  constructor(scene: Phaser.Scene, x: number, y: number, config: EnemyConfig, ctx: EnemyContext) {
    super(scene, x, y, '__WHITE');
    this.enemyId = ++enemyIdCounter;
    this.config = config;
    this.ctx = ctx;
    this.maxHp = config.maxHp;
    this.hp = config.maxHp;

    scene.add.existing(this);
    scene.physics.add.existing(this);
    this.setVisible(false).setDepth(8).setCollideWorldBounds(true);

    const body = this.body as Phaser.Physics.Arcade.Body;
    body.setSize(config.body.width, config.body.height, false);
    body.setOffset(
      this.displayOriginX - config.body.width / 2 + config.body.centerOffsetX,
      this.displayOriginY - config.body.height / 2 + config.body.centerOffsetY,
    );
    body.setBounce(0.2).setCollideWorldBounds(true);

    this.visual = new AnimatedVisual(scene, this, config.visualSetId, {
      depth: 8,
      initialFrame: 0,
    });
    this.healthBar = scene.add.graphics().setDepth(40);
    this.playVisual('idle');
  }

  takeDamage(amount: number, knockX: number, knockY: number, knockStrength: number): void {
    if (this.dead) return;
    this.cancelAttack();
    this.hp = Math.max(0, this.hp - amount);
    this.hitFlashUntil = this.scene.time.now + 120;
    this.visual.setTintFill(0xff5a5a);

    const bounds = this.visual.getBounds();
    floatingText.spawn(
      this.scene,
      this.x,
      bounds.top - 8,
      `-${amount}`,
      amount > 15 ? 'yellow' : 'white',
      amount > 15,
    );

    if (this.hp <= 0) {
      this.die();
      return;
    }

    const finalStrength = (knockStrength + 120) * (1 - this.config.ai.knockbackResist);
    if (finalStrength > 0) this.setVelocity(knockX * finalStrength, knockY * finalStrength);
    const hitStunDuration = 320 + Math.min(280, finalStrength * 0.35);
    this.hitStunUntil = Math.max(
      this.hitStunUntil,
      this.scene.time.now + hitStunDuration,
    );
    this.playVisual('knockback', true);
  }

  preUpdate(time: number, delta: number): void {
    super.preUpdate(time, delta);
    this.visual.update();
    if (this.dead) return;

    if (this.hitFlashUntil > 0 && time > this.hitFlashUntil) {
      this.visual.clearTint();
      this.hitFlashUntil = 0;
    }
    const player = this.ctx.getPlayer();
    if (!player?.active) {
      this.setVelocity(0, 0);
      this.syncMovementVisual();
      return;
    }

    if (time < this.hitStunUntil) {
      const body = this.body as Phaser.Physics.Arcade.Body;
      body.velocity.scale(0.94);
      this.drawHealthBar();
      return;
    }

    const dx = player.x - this.x;
    const dy = player.y - this.y;
    const dist = Math.hypot(dx, dy);
    const dir = dist > 0
      ? new Phaser.Math.Vector2(dx / dist, dy / dist)
      : new Phaser.Math.Vector2();

    const nextState = runState(this.aiState, {
      enemy: this,
      player,
      time,
      delta,
      distToPlayer: dist,
      dirToPlayer: dir,
      config: this.config.ai,
      requestAttack: (direction) => this.beginAttack(direction, time),
      safeZones: this.ctx.getSafeZones?.(),
    });
    if (nextState !== 'continue') this.aiState = nextState;

    if (!this.attackActive) {
      const velocity = (this.body as Phaser.Physics.Arcade.Body).velocity;
      this.updateDirection(velocity);
      this.syncMovementVisual();
    }
    this.drawHealthBar();
  }

  destroy(fromScene?: boolean): void {
    this.cancelAttack();
    this.deathTimer?.remove();
    this.healthBar.destroy();
    this.visual.destroy();
    super.destroy(fromScene);
  }

  private beginAttack(direction: Phaser.Math.Vector2, time: number): void {
    if (this.attackActive || time < this.attackReadyAt || this.dead) return;
    this.attackActive = true;
    this.attackReadyAt = time + this.config.ai.attackCooldownMs;
    this.attackSequenceId += 1;
    const sequenceId = this.attackSequenceId;
    this.attackVector = direction.lengthSq() > 0 ? direction.clone().normalize() : this.attackVector;
    this.updateDirection(this.attackVector);
    this.playVisual('attack');

    this.attackTimers.push(this.scene.time.delayedCall(
      this.config.ai.attackWindupMs,
      () => this.resolveAttack(sequenceId),
    ));

    const clip = getVisualClip(this.config.visualSetId, `attack-${this.direction}`);
    const clipDuration = clip.frames.length / clip.frameRate * 1000;
    const sequenceDuration = Math.min(
      2000,
      Math.max(
        this.config.ai.attackWindupMs + this.config.ai.attackRecoveryMs,
        clipDuration,
      ) + 250,
    );
    this.attackTimers.push(this.scene.time.delayedCall(
      sequenceDuration,
      () => this.finishAttack(sequenceId),
    ));
  }

  private resolveAttack(sequenceId: number): void {
    if (!this.attackActive || sequenceId !== this.attackSequenceId || this.dead) return;
    const player = this.ctx.getPlayer();
    if (!player?.active) return;

    if (this.config.projectile && this.ctx.fireProjectile) {
      this.ctx.fireProjectile(
        this.x,
        this.y,
        this.attackVector.x,
        this.attackVector.y,
        this.config.ai.projectileSpeed ?? 200,
        this.config.projectile.assetId,
        this.config.projectile.damage,
        this.config.ai.knockbackStrength,
      );
      return;
    }

    const distance = Phaser.Math.Distance.Between(this.x, this.y, player.x, player.y);
    if (distance > this.config.ai.attackRange * 1.35) return;
    this.ctx.onContactDamage(this, this.config.ai.contactDamage);
    if (this.config.impactEffect) this.spawnImpactEffect();
  }

  private finishAttack(sequenceId: number): void {
    if (!this.attackActive || sequenceId !== this.attackSequenceId || this.dead) return;
    this.attackTimers.forEach((timer) => timer.remove());
    this.attackTimers = [];
    this.attackActive = false;
    const player = this.ctx.getPlayer();
    const distance = player
      ? Phaser.Math.Distance.Between(this.x, this.y, player.x, player.y)
      : Number.POSITIVE_INFINITY;
    this.aiState = this.config.ai.fleeRange && distance < this.config.ai.fleeRange
      ? 'flee'
      : 'chase';
    this.syncMovementVisual();
  }

  private cancelAttack(): void {
    this.attackSequenceId += 1;
    this.attackTimers.forEach((timer) => timer.remove());
    this.attackTimers = [];
    this.attackActive = false;
  }

  private die(): void {
    if (this.dead) return;
    this.dead = true;
    this.aiState = 'dead';
    this.cancelAttack();
    this.setVelocity(0, 0);
    (this.body as Phaser.Physics.Arcade.Body).enable = false;
    this.healthBar.clear();
    this.visual.clearTint();
    this.playVisual('die');
    this.ctx.onDeath(this);

    const clip = getVisualClip(this.config.visualSetId, `die-${this.direction}`);
    const runtimeKey = clip.runtimeKey;
    const finish = () => this.finishDeath();
    this.visual.onceComplete(runtimeKey, finish);
    this.deathTimer = this.scene.time.delayedCall(
      Math.min(1500, clip.frames.length / clip.frameRate * 1000 + 250),
      finish,
    );
  }

  private finishDeath(): void {
    if (this.deathFinishing) return;
    this.deathFinishing = true;
    this.deathTimer?.remove();

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
    this.scene.tweens.add({
      targets: this.visual.effects,
      alpha: 0,
      duration: 250,
      onUpdate: () => this.visual.update(),
      onComplete: () => this.destroy(),
    });
  }

  private spawnImpactEffect(): void {
    const effect = this.config.impactEffect;
    if (!effect) return;
    const definition = getVisualSet(effect.visualSetId);
    const asset = getAsset(definition.assetId);
    const clip = getVisualClip(effect.visualSetId, effect.clipId);
    const sprite = this.scene.add.sprite(
      this.x + this.attackVector.x * effect.distance,
      this.y + this.attackVector.y * effect.distance,
      asset.runtime.textureKey,
      0,
    ).setDepth(12).setRotation(Math.atan2(this.attackVector.y, this.attackVector.x));
    let cleaned = false;
    const cleanup = () => {
      if (cleaned) return;
      cleaned = true;
      sprite.destroy();
    };
    sprite.once(Phaser.Animations.Events.ANIMATION_COMPLETE_KEY + clip.runtimeKey, cleanup);
    sprite.play(clip.runtimeKey);
    this.scene.time.delayedCall(500, cleanup);
  }

  private updateDirection(vector: Phaser.Math.Vector2): void {
    if (vector.lengthSq() < 1) return;
    if (Math.abs(vector.x) > Math.abs(vector.y)) {
      this.direction = 'side';
      this.sideFlipped = vector.x < 0;
    } else {
      this.direction = vector.y < 0 ? 'up' : 'down';
      this.sideFlipped = false;
    }
    this.visual.setFlipX(this.sideFlipped);
  }

  private syncMovementVisual(): void {
    if (this.attackActive || this.dead) return;
    const velocity = (this.body as Phaser.Physics.Arcade.Body).velocity;
    this.playVisual(velocity.lengthSq() > 4 ? 'walk' : 'idle');
  }

  private playVisual(action: VisualAction, forceRestart = false): void {
    const clipId = `${action}-${this.direction}`;
    if (this.currentClipId === clipId && !forceRestart) return;
    this.currentClipId = clipId;
    this.visual.play(
      getVisualClip(this.config.visualSetId, clipId).runtimeKey,
      !forceRestart,
    );
  }

  private drawHealthBar(): void {
    const bounds = this.visual.getBounds();
    const width = Math.max(28, bounds.width * 0.8);
    const y = bounds.top - 8;
    this.healthBar.clear();
    this.healthBar.fillStyle(0x0a1f15, 0.8).fillRoundedRect(this.x - width / 2, y, width, 4, 2);
    const pct = Phaser.Math.Clamp(this.hp / this.maxHp, 0, 1);
    const fill = pct <= 0.25 ? 0xff5a5a : pct <= 0.5 ? 0xff9a3c : 0xff6b6b;
    this.healthBar.fillStyle(fill, 1).fillRoundedRect(
      this.x - width / 2 + 1,
      y + 1,
      Math.max(0, (width - 2) * pct),
      2,
      2,
    );
  }
}
