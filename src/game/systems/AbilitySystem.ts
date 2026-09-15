import Phaser from 'phaser';
import { gameState } from '../core/GameState';
import { floatingText } from '../ui/FloatingText';
import { isTileCollidable, type WorldTileId } from '../content/terrain/TileCatalog';
import { hitboxPool } from '../combat/Hitbox';
import { TargetDummy } from '../combat/TargetDummy';
import type { WorldDimensions } from '../world/WorldDimensions';
import type { AnimatedVisual } from '../features/visuals/AnimatedVisual';
import { resolveWorldDepth } from '../presentation/WorldDepth';
import { PlayerAbilityService, type PlayerAbilityIntent } from '../features/player/PlayerAbilityService';
import type { PlayerAbilityId } from '../features/player/PlayerAbilityDefinitions';

/**
 * AbilitySystem â€” owns jump + teleport (preview of Phase 2 ability framework).
 *
 * Both are level-gated:
 *   - Jump:      unlocked at level 2. A directional leap with a parabolic arc
 *                visual (scale stretch + a ground shadow), driven by a tween
 *                timeline. Raycasts against solid tiles so the hop stops at
 *                walls instead of clipping through them.
 *   - Teleport:  unlocked at level 5. An instant blink in the facing direction
 *                with a flash/afterimage at both ends. Costs energy.
 *
 * Cooldowns tracked in ms via scene.time.now.
 */

export type AbilityId = PlayerAbilityId;

const JUMP_ARC_HEIGHT = 54;

export interface AbilitySystemContext {
  scene: Phaser.Scene;
  dimensions: WorldDimensions;
  getPlayer: () => Phaser.Physics.Arcade.Sprite;
  getPlayerVisual: () => AnimatedVisual;
  isActionLocked: () => boolean;
  setActionLocked: (locked: boolean) => void;
  getFacing: () => Phaser.Math.Vector2;
  playAnimation: (key: string) => void;
  getTerrainGrid: () => WorldTileId[][];
  getCombatTargets: () => Phaser.Physics.Arcade.Group | null;
}

export class AbilitySystem {
  private ctx: AbilitySystemContext;
  private readonly decisions: PlayerAbilityService;

  constructor(ctx: AbilitySystemContext) {
    this.ctx = ctx;
    this.decisions = new PlayerAbilityService({
      nowMs: () => ctx.scene.time.now,
      state: {
        getLevel: () => gameState.level,
        getEnergy: () => gameState.energy,
        isActionLocked: ctx.isActionLocked,
        setActionLocked: ctx.setActionLocked,
        spendEnergy: (amount) => gameState.useEnergy(amount),
      },
      terrain: {
        isBlocked: (x, y) => {
          const grid = ctx.getTerrainGrid();
          const tileX = Math.floor(x / ctx.dimensions.tileSize);
          const tileY = Math.floor(y / ctx.dimensions.tileSize);
          if (tileY < 0 || tileY >= grid.length || tileX < 0 || tileX >= (grid[0]?.length ?? 0)) return true;
          const tileId = grid[tileY]?.[tileX];
          return tileId !== undefined && isTileCollidable(tileId);
        },
      },
    });
  }

  unlockLevel(ability: AbilityId): number {
    return this.decisions.unlockLevel(ability);
  }

  isUnlocked(ability: AbilityId): boolean {
    return this.decisions.isUnlocked(ability);
  }

  isBusy(): boolean {
    return this.decisions.isBusy();
  }

  /** Attempt to jump in the given direction (or facing if zero). */
  tryJump(direction: Phaser.Math.Vector2): boolean {
    const intent = this.beginAbility('jump', direction);
    if (!intent) return false;
    const scene = this.ctx.scene;
    const player = this.ctx.getPlayer();
    const visual = this.ctx.getPlayerVisual();
    const { start, target } = intent;
    const durationMs = intent.definition.durationMs ?? 420;
    this.ctx.playAnimation('slime-hop');

    // Ground shadow stays at the start position.
    const shadow = scene.add.ellipse(start.x, start.y, 40, 16, 0x000000, 0.35)
      .setDepth(resolveWorldDepth(start.y, { stableId: 'player-jump-shadow', attachmentSlot: -6 }).depth)
      .setAlpha(0.35);

    // Freeze physics-driven movement; we drive position manually.
    player.setVelocity(0, 0);

    const midX = (start.x + target.x) / 2;
    const midY = (start.y + target.y) / 2 - JUMP_ARC_HEIGHT;

    visual.resetEffects();

    // Up: stretch tall + rise to midpoint.
    scene.tweens.add({
      targets: player,
      x: midX,
      y: midY,
      duration: durationMs / 2,
      ease: 'Quad.Out',
    });
    scene.tweens.add({
      targets: visual.effects,
      scaleX: 0.82,
      scaleY: 1.35,
      duration: durationMs / 2,
      ease: 'Quad.Out',
    });
    // Down: squash + land at target.
    scene.tweens.add({
      targets: player,
      x: target.x,
      y: target.y,
      duration: durationMs / 2,
      delay: durationMs / 2,
      ease: 'Quad.In',
      onComplete: () => {
        // Squash rebound.
        scene.tweens.add({
          targets: visual.effects,
          scaleX: 1,
          scaleY: 1,
          duration: 120,
          ease: 'Back.Out',
        });
        // Landing dust.
        const dust = scene.add.particles(target.x, target.y, 'xp-orb', {
          lifespan: 320,
          speed: { min: 20, max: 60 },
          scale: { start: 0.3, end: 0 },
          alpha: { start: 0.6, end: 0 },
          quantity: 8,
          emitting: false,
        }).setDepth(resolveWorldDepth(target.y, {
          band: 'reveal-effects',
          stableId: 'player-jump-dust',
          attachmentSlot: -5,
        }).depth);
        dust.emitParticle(8);
        scene.time.delayedCall(400, () => dust.destroy());

        if (this.decisions.complete(intent.sequenceId)) this.ctx.playAnimation('slime-idle');
      },
    });
    scene.tweens.add({
      targets: visual.effects,
      scaleX: 1.18,
      scaleY: 0.7,
      duration: durationMs / 2,
      delay: durationMs / 2,
      ease: 'Quad.In',
    });

    // Shadow fades as we "rise" and returns at landing.
    scene.tweens.add({
      targets: shadow,
      alpha: 0.12,
      scaleX: 0.7,
      scaleY: 0.7,
      duration: durationMs / 2,
      yoyo: true,
      onComplete: () => shadow.destroy(),
    });

    return true;
  }

  /** Attempt to teleport (blink) in the given direction (or facing). */
  tryTeleport(direction: Phaser.Math.Vector2): boolean {
    const intent = this.beginAbility('teleport', direction);
    if (!intent) return false;
    const scene = this.ctx.scene;
    const player = this.ctx.getPlayer();
    const visual = this.ctx.getPlayerVisual();
    const { start, target } = intent;

    // Afterimage at origin.
    this.spawnFlash(start.x, start.y, 0x72d8ff);
    this.ctx.playAnimation('slime-teleport');

    // Vanish.
    player.setVelocity(0, 0);
    scene.tweens.add({
      targets: visual.effects,
      alpha: 0,
      scaleX: 0.36,
      scaleY: 0.36,
      duration: 120,
      ease: 'Quad.In',
      onComplete: () => {
        player.setPosition(target.x, target.y);
        // Reappear.
        this.spawnFlash(target.x, target.y, 0xa3f0c0);
        scene.tweens.add({
          targets: visual.effects,
          alpha: 1,
          scaleX: 1,
          scaleY: 1,
          duration: 180,
          ease: 'Back.Out',
          onComplete: () => {
            if (this.decisions.complete(intent.sequenceId)) this.ctx.playAnimation('slime-idle');
          },
        });
      },
    });

    return true;
  }

  /** Squash Slam â€” AoE shockwave around the player. Unlocks at level 3. */
  trySquashSlam(): boolean {
    const intent = this.beginAbility('squash-slam');
    if (!intent) return false;
    const scene = this.ctx.scene;
    const player = this.ctx.getPlayer();
    const visual = this.ctx.getPlayerVisual();
    const radius = intent.definition.radius ?? 90;
    const damage = intent.definition.damage ?? 30;
    this.ctx.playAnimation('slime-squash');
    player.setVelocity(0, 0);

    // Windup: rise slightly.
    scene.tweens.add({
      targets: visual.effects,
      scaleY: 1.36,
      duration: 200,
      ease: 'Quad.Out',
      onComplete: () => {
        // Slam down: squash flat + shockwave.
        scene.tweens.add({
          targets: visual.effects,
          scaleY: 0.64,
          duration: 120,
          ease: 'Quad.In',
          onComplete: () => {
            // Shockwave ring.
            const ring = scene.add.circle(player.x, player.y, 10, 0x86f0c3, 0.5).setDepth(resolveWorldDepth(player.y, {
              band: 'reveal-effects',
              stableId: 'player-squash-slam',
              attachmentSlot: -2,
            }).depth);
            scene.tweens.add({
              targets: ring,
              scale: radius / 10,
              alpha: 0,
              duration: 300,
              onComplete: () => ring.destroy(),
            });

            // Camera shake.
            scene.cameras.main.shake(150, 0.01);

            // AoE damage hitbox.
            const targets = this.ctx.getCombatTargets();
            if (targets) {
              hitboxPool.spawn(scene, targets, {
                x: player.x,
                y: player.y,
                width: radius * 2,
                height: radius * 2,
                damage,
                durationMs: 200,
                knockStrength: 320,
                vfxColor: 0x86f0c3,
                showVfx: false,
              }, (target: Phaser.GameObjects.GameObject, dmg: number, _kx: number, _ky: number, kStr: number) => {
                if (target instanceof TargetDummy) {
                  const dx = target.x - player.x;
                  const dy = target.y - player.y;
                  const len = Math.hypot(dx, dy) || 1;
                  target.takeDamage(dmg, dx / len, dy / len, kStr);
                  floatingText.spawn(scene, target.x, target.y - 24, `${dmg}`, 'yellow', true);
                }
              });
            }

            // Rebound.
            scene.tweens.add({
              targets: visual.effects,
              scaleY: 1,
              duration: 150,
              ease: 'Back.Out',
              onComplete: () => {
                if (this.decisions.complete(intent.sequenceId)) this.ctx.playAnimation('slime-idle');
              },
            });
          },
        });
      },
    });

    return true;
  }

  /** Stretch Lash â€” long-range tongue/whip attack in facing direction. Lv 4. */
  tryStretchLash(): boolean {
    const intent = this.beginAbility('stretch-lash');
    if (!intent) return false;
    const scene = this.ctx.scene;
    const player = this.ctx.getPlayer();
    const visual = this.ctx.getPlayerVisual();
    const dir = intent.direction;
    const range = intent.definition.distance ?? 180;
    const damage = intent.definition.damage ?? 18;
    this.ctx.playAnimation('slime-stretch');
    player.setVelocity(0, 0);

    // Stretch in facing direction.
    const stretchX = player.x + dir.x * range * 0.5;
    const stretchY = player.y + dir.y * range * 0.5;

    scene.tweens.add({
      targets: player,
      x: stretchX,
      y: stretchY,
      duration: 180,
      ease: 'Quad.Out',
      onComplete: () => {
        // Lash VFX: a line from player to the lash tip.
        const tipX = player.x + dir.x * range * 0.5;
        const tipY = player.y + dir.y * range * 0.5;
        const lash = scene.add.graphics().setDepth(resolveWorldDepth(player.y, {
          band: 'reveal-effects',
          stableId: 'player-stretch-lash',
          attachmentSlot: -2,
        }).depth);
        lash.lineStyle(4, 0xffad66, 0.8);
        lash.beginPath();
        lash.moveTo(player.x, player.y);
        lash.lineTo(tipX, tipY);
        lash.strokePath();
        scene.tweens.add({
          targets: lash,
          alpha: 0,
          duration: 200,
          onComplete: () => lash.destroy(),
        });

        // Hitbox along the lash path.
        const targets = this.ctx.getCombatTargets();
        if (targets) {
          const hx = player.x + dir.x * range * 0.4;
          const hy = player.y + dir.y * range * 0.4;
          hitboxPool.spawn(scene, targets, {
            x: hx,
            y: hy,
            width: range,
            height: 40,
            damage,
            durationMs: 160,
            knockX: dir.x,
            knockY: dir.y,
            knockStrength: 280,
            vfxColor: 0xffad66,
            showVfx: false,
          }, (target: Phaser.GameObjects.GameObject, dmg: number, kx: number, ky: number, kStr: number) => {
            if (target instanceof TargetDummy) {
              target.takeDamage(dmg, kx, ky, kStr);
              floatingText.spawn(scene, target.x, target.y - 24, `${dmg}`, 'orange', true);
            }
          });
        }

        // Retract.
        scene.tweens.add({
          targets: player,
          x: player.x - dir.x * range * 0.3,
          y: player.y - dir.y * range * 0.3,
          duration: 200,
          ease: 'Quad.In',
          onComplete: () => {
            if (this.decisions.complete(intent.sequenceId)) this.ctx.playAnimation('slime-idle');
          },
        });
        scene.tweens.add({
          targets: visual.effects,
          scaleX: 1,
          scaleY: 1,
          duration: 200,
          ease: 'Quad.In',
        });
      },
    });
    scene.tweens.add({
      targets: visual.effects,
      scaleX: 1.5,
      scaleY: 0.64,
      duration: 180,
      ease: 'Quad.Out',
    });

    return true;
  }

  update(): void {
    // Nothing per-frame for now; cooldowns read lazily.
  }

  destroy(): void {
    this.decisions.cancel();
  }

  // â”€â”€ helpers â”€â”€

  private beginAbility(ability: AbilityId, direction?: Phaser.Math.Vector2): PlayerAbilityIntent | undefined {
    const player = this.ctx.getPlayer();
    const facing = this.ctx.getFacing();
    const decision = this.decisions.tryBegin(ability, {
      position: { x: player.x, y: player.y },
      direction: direction ? { x: direction.x, y: direction.y } : { x: 0, y: 0 },
      facing: { x: facing.x, y: facing.y },
    });
    if (decision.accepted) return decision.intent;
    if (decision.reason === 'locked') this.notifyLocked(ability);
    if (decision.reason === 'energy') floatingText.spawn(this.ctx.scene, player.x, player.y - 30, 'Low energy', 'orange');
    return undefined;
  }

  private notifyLocked(ability: AbilityId): void {
    const scene = this.ctx.scene;
    const need = this.decisions.unlockLevel(ability);
    const player = this.ctx.getPlayer();
    floatingText.spawn(scene, player.x, player.y - 30, `Locked - Lv ${need}`, 'red');
  }

  private spawnFlash(x: number, y: number, color: number): void {
    const scene = this.ctx.scene;
    const flash = scene.add.circle(x, y, 10, color, 0.9).setDepth(resolveWorldDepth(y, {
      band: 'reveal-effects',
      stableId: `ability-flash:${color}`,
      attachmentSlot: -1,
    }).depth);
    scene.tweens.add({
      targets: flash,
      scale: 6,
      alpha: 0,
      duration: 260,
      ease: 'Quad.Out',
      onComplete: () => flash.destroy(),
    });
  }
}
