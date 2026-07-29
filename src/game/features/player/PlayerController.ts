import Phaser from 'phaser';
import { PLAYER_CONFIG } from '../../content/player';
import { gameState } from '../../core/GameState';
import type { Controls } from '../../core/Input';
import { floatingText } from '../../ui/FloatingText';
import type { StatusEffectManager } from '../../systems/StatusEffects';
import { getStats, resolveMovementSpeed } from '../../systems/PlayerStats';
import type { PlayerEntity } from './PlayerFactory';
import { resolveBodyBottom, resolveWorldDepth } from '../../presentation/WorldDepth';

export interface PlayerControllerContext {
  scene: Phaser.Scene;
  entity: PlayerEntity;
  getControls: () => Controls;
  getStatusEffects: () => StatusEffectManager | undefined;
  playAnimation: (key: string) => void;
}

export class PlayerController {
  readonly facing = new Phaser.Math.Vector2(0, 1);
  private dodgeInvulnerableUntil = 0;
  private movementSuppressedUntil = 0;

  constructor(private readonly ctx: PlayerControllerContext) {}

  readDirection(): Phaser.Math.Vector2 {
    const controls = this.ctx.getControls();
    const direction = new Phaser.Math.Vector2();
    if (controls.left.isDown || controls.leftAlt.isDown) direction.x -= 1;
    if (controls.right.isDown || controls.rightAlt.isDown) direction.x += 1;
    if (controls.up.isDown || controls.upAlt.isDown) direction.y -= 1;
    if (controls.down.isDown || controls.downAlt.isDown) direction.y += 1;
    return direction;
  }

  updateVisuals(): void {
    const { sprite, visual, nameTag } = this.ctx.entity;
    visual.update();
    const body = sprite.body as Phaser.Physics.Arcade.Body;
    sprite.setDepth(resolveWorldDepth(resolveBodyBottom(body), { stableId: 'player' }).depth);
    nameTag
      .setPosition(sprite.x, sprite.y - 56)
      .setDepth(resolveWorldDepth(resolveBodyBottom(body), {
        stableId: 'player',
        attachmentSlot: 7,
      }).depth);
  }

  move(direction: Phaser.Math.Vector2): void {
    const player = this.ctx.entity.sprite;
    if (this.ctx.scene.time.now < this.movementSuppressedUntil) {
      player.rotation = 0;
      return;
    }
    const controls = this.ctx.getControls();
    const statusEffects = this.ctx.getStatusEffects();
    const wantsBoost = controls.boost.isDown;
    const stats = getStats();
    const baseSpeed = wantsBoost
      ? PLAYER_CONFIG.movement.boostSpeed + gameState.boostBonus
      : stats.movementSpeed;
    const speed = resolveMovementSpeed(baseSpeed, 0, statusEffects?.speedMultiplier ?? 1);

    if (statusEffects?.isRooted()) {
      player.setVelocity(0, 0);
      player.rotation = 0;
      this.ctx.playAnimation('slime-idle');
      return;
    }

    if (direction.lengthSq() > 0) {
      direction.normalize().scale(speed);
    }

    player.setVelocity(direction.x, direction.y);
    player.rotation = 0;

    if (direction.lengthSq() === 0) {
      this.ctx.entity.visual.setFlipX(false);
      this.ctx.playAnimation('slime-idle');
      return;
    }

    this.facing.set(direction.x, direction.y).normalize();
    this.ctx.entity.visual.setFlipX(
      Math.abs(direction.x) >= Math.abs(direction.y) && direction.x > 0,
    );

    if (wantsBoost) this.ctx.playAnimation('slime-roll');
    else if (Math.abs(direction.y) > Math.abs(direction.x)) {
      this.ctx.playAnimation(direction.y < 0 ? 'slime-stretch' : 'slime-hop');
    } else this.ctx.playAnimation('slime-walk');
  }

  tryDodge(direction: Phaser.Math.Vector2): boolean {
    const scene = this.ctx.scene;
    const player = this.ctx.entity.sprite;
    const dodgeDirection = direction.lengthSq() > 0
      ? direction.clone().normalize()
      : this.facing.clone().normalize();
    if (dodgeDirection.lengthSq() === 0) dodgeDirection.set(1, 0);

    this.dodgeInvulnerableUntil = scene.time.now + PLAYER_CONFIG.movement.dodgeInvulnerabilityMs;
    this.ctx.playAnimation('slime-roll');
    const dodgeSpeed = resolveMovementSpeed(PLAYER_CONFIG.movement.dodgeSpeed);
    player.setVelocity(dodgeDirection.x * dodgeSpeed, dodgeDirection.y * dodgeSpeed);

    const dust = scene.add.particles(player.x, player.y, 'xp-orb', {
      lifespan: 280,
      speed: { min: 10, max: 40 },
      scale: { start: 0.2, end: 0 },
      alpha: { start: 0.4, end: 0 },
      quantity: 6,
      emitting: false,
    }).setDepth(resolveWorldDepth(resolveBodyBottom(player.body as Phaser.Physics.Arcade.Body), {
      stableId: 'player',
      attachmentSlot: -4,
    }).depth);
    dust.emitParticle(6);
    scene.time.delayedCall(300, () => dust.destroy());
    floatingText.spawn(scene, player.x, player.y - 30, 'DODGE', 'cyan');
    return true;
  }

  isDodging(): boolean {
    return this.ctx.scene.time.now < this.dodgeInvulnerableUntil;
  }

  isMovementSuppressed(): boolean {
    return this.ctx.scene.time.now < this.movementSuppressedUntil;
  }

  applyKnockback(direction: Phaser.Math.Vector2, strength: number, durationMs: number): void {
    if (direction.lengthSq() === 0 || strength <= 0) return;
    const normalized = direction.clone().normalize();
    this.movementSuppressedUntil = Math.max(
      this.movementSuppressedUntil,
      this.ctx.scene.time.now + durationMs,
    );
    this.ctx.entity.sprite.setVelocity(normalized.x * strength, normalized.y * strength);
  }
}
