import Phaser from 'phaser';
import { PLAYER_CONFIG } from '../../content/player';
import { gameEvents } from '../../core/EventBus';
import { gameState } from '../../core/GameState';
import { floatingText } from '../../ui/FloatingText';
import type { StatusEffectManager } from '../../systems/StatusEffects';
import { getStats, resolveMovementSpeed } from '../../systems/PlayerStats';
import { resolveBodyBottom, resolveWorldDepth } from '../../presentation/WorldDepth';
import { resolvePhysicsPresentationPosition } from '../../presentation/PhysicsPresentation';
import type { WorldVisual } from '../../presentation/WorldVisual';
import type { PlayerActorPort, PlayerInputPort } from './PlayerServicePorts';

export interface PlayerControllerContext {
  scene: Phaser.Scene;
  player: Phaser.Physics.Arcade.Sprite;
  visual: WorldVisual;
  nameTag: Phaser.GameObjects.Text;
  getMotion: () => PlayerActorPort;
  getInput: () => PlayerInputPort;
  getStatusEffects: () => StatusEffectManager | undefined;
  playAnimation: (key: string) => void;
}

export class PlayerController {
  readonly facing = new Phaser.Math.Vector2(0, 1);
  private readonly presentationPosition = new Phaser.Math.Vector2();

  constructor(private readonly ctx: PlayerControllerContext) {}

  readDirection(): Phaser.Math.Vector2 {
    const direction = this.ctx.getInput().getMovementInput();
    return new Phaser.Math.Vector2(direction.x, direction.y);
  }

  updateVisuals(): void {
    const { player, nameTag } = this.ctx;
    const authoredPosition = this.ctx.getMotion().getPosition();
    player.setPosition(authoredPosition.x, authoredPosition.y);
    const body = player.body as Phaser.Physics.Arcade.Body;
    const presentationPosition = resolvePhysicsPresentationPosition(
      this.ctx.scene,
      player,
      this.presentationPosition,
    );
    player.setDepth(resolveWorldDepth(resolveBodyBottom(body), { stableId: 'player' }).depth);
    nameTag
      .setPosition(presentationPosition.x, presentationPosition.y - 56)
      .setDepth(resolveWorldDepth(resolveBodyBottom(body), {
        stableId: 'player',
        attachmentSlot: 7,
      }).depth);
  }

  move(direction: Phaser.Math.Vector2): void {
    const player = this.ctx.player;
    if (this.ctx.getMotion().isMovementSuppressed()) {
      player.rotation = 0;
      return;
    }
    const statusEffects = this.ctx.getStatusEffects();
    const wantsBoost = this.ctx.getInput().isActionPressed('boost');
    const stats = getStats();
    const baseSpeed = wantsBoost
      ? PLAYER_CONFIG.movement.boostSpeed + gameState.boostBonus
      : stats.movementSpeed;
    const speed = resolveMovementSpeed(baseSpeed, 0, statusEffects?.speedMultiplier ?? 1);

    if (statusEffects?.isRooted()) {
      this.ctx.getMotion().move({ x: 0, y: 0 }, 0);
      player.rotation = 0;
      this.ctx.playAnimation('slime-idle');
      return;
    }

    if (direction.lengthSq() > 0) {
      direction.normalize().scale(speed);
    }

    this.ctx.getMotion().move(direction, direction.length());
    player.rotation = 0;

    if (direction.lengthSq() === 0) {
      this.ctx.visual.setFlipX(false);
      this.ctx.playAnimation('slime-idle');
      return;
    }

    this.facing.set(direction.x, direction.y).normalize();
    this.ctx.visual.setFlipX(
      Math.abs(direction.x) >= Math.abs(direction.y) && direction.x > 0,
    );

    if (wantsBoost) this.ctx.playAnimation('slime-roll');
    else if (Math.abs(direction.y) > Math.abs(direction.x)) {
      this.ctx.playAnimation(direction.y < 0 ? 'slime-stretch' : 'slime-hop');
    } else this.ctx.playAnimation('slime-walk');
  }

  tryDodge(direction: Phaser.Math.Vector2): boolean {
    const scene = this.ctx.scene;
    const player = this.ctx.player;
    const dodgeDirection = direction.lengthSq() > 0
      ? direction.clone().normalize()
      : this.facing.clone().normalize();
    if (dodgeDirection.lengthSq() === 0) dodgeDirection.set(1, 0);

    const dodgeSpeed = resolveMovementSpeed(PLAYER_CONFIG.movement.dodgeSpeed);
    if (!this.ctx.getMotion().beginDodge(
      dodgeDirection,
      dodgeSpeed,
      PLAYER_CONFIG.movement.dodgeInvulnerabilityMs,
    )) return false;
    this.ctx.playAnimation('slime-roll');
    gameEvents.emit('player.action', { anim: 'dodge' });

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
    return this.ctx.getMotion().isDodging();
  }

  isMovementSuppressed(): boolean {
    return this.ctx.getMotion().isMovementSuppressed();
  }

  applyKnockback(direction: Phaser.Math.Vector2, strength: number, durationMs: number): void {
    if (direction.lengthSq() === 0 || strength <= 0) return;
    const normalized = direction.clone().normalize();
    this.ctx.getMotion().applyKnockback(normalized, strength, durationMs);
  }
}
