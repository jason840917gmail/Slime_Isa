import Phaser from 'phaser';
import { PLAYER_CONFIG } from '../../content/player';
import { gameEvents } from '../../core/EventBus';
import { gameState } from '../../core/GameState';
import { floatingText } from '../../ui/FloatingText';
import { particleFx } from '../feel/ParticlePresets';
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
  /** Movement multiplier from the current Gulp form (1 without one). */
  getFormSpeedMultiplier: () => number;
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
    const wantsBoost = this.ctx.getInput().isActionPressed('sprint');
    const stats = getStats();
    const baseSpeed = wantsBoost
      ? PLAYER_CONFIG.movement.boostSpeed + gameState.boostBonus
      : stats.movementSpeed;
    // A Gulp form scales the effective (capped) speed, so Heavy is slower than any walk.
    const speed = resolveMovementSpeed(baseSpeed, 0, statusEffects?.speedMultiplier ?? 1) * this.ctx.getFormSpeedMultiplier();

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

    // Sprinting walks faster with the walk animations: the roll belongs to the dodge only.
    if (Math.abs(direction.y) > Math.abs(direction.x)) {
      this.ctx.playAnimation(direction.y < 0 ? 'slime-stretch' : 'slime-hop');
    } else this.ctx.playAnimation('slime-walk');
  }

  /** Turns the slime to `direction` (a unit vector), as a swing or a roll does. */
  face(direction: Readonly<{ x: number; y: number }>): void {
    if (direction.x === 0 && direction.y === 0) return;
    this.facing.set(direction.x, direction.y).normalize();
    this.ctx.visual.setFlipX(Math.abs(direction.x) >= Math.abs(direction.y) && direction.x > 0);
  }

  /** Rolls along `direction` (already snapped to 4 directions by the caller). */
  tryDodge(direction: Readonly<{ x: number; y: number }>): boolean {
    const scene = this.ctx.scene;
    const player = this.ctx.player;
    const dodgeDirection = new Phaser.Math.Vector2(direction.x, direction.y);
    if (dodgeDirection.lengthSq() === 0) dodgeDirection.copy(this.facing);
    if (dodgeDirection.lengthSq() === 0) dodgeDirection.set(1, 0);
    dodgeDirection.normalize();

    const { dodgeSpeed, dodgeDurationMs, dodgeInvulnerabilityMs } = PLAYER_CONFIG.movement;
    if (!this.ctx.getMotion().beginDodge(
      dodgeDirection,
      resolveMovementSpeed(dodgeSpeed),
      dodgeDurationMs,
      dodgeInvulnerabilityMs,
    )) return false;
    this.face(dodgeDirection);
    this.ctx.playAnimation('slime-roll');
    gameEvents.emit('player.action', { anim: 'dodge' });

    particleFx.play('dodge-dust', player.x, resolveBodyBottom(player.body as Phaser.Physics.Arcade.Body));
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
