import Phaser from 'phaser';
import { gameState } from '../core/GameState';
import { floatingText } from '../ui/FloatingText';
import { isTileCollidable, type WorldTileId } from '../content/terrain/TileCatalog';
import { hitboxPool } from '../combat/Hitbox';
import { TargetDummy } from '../combat/TargetDummy';
import type { WorldDimensions } from '../world/WorldDimensions';
import type { AnimatedVisual } from '../features/visuals/AnimatedVisual';
import { resolveWorldDepth } from '../presentation/WorldDepth';

/**
 * AbilitySystem — owns jump + teleport (preview of Phase 2 ability framework).
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

export type AbilityId = 'jump' | 'teleport' | 'squash-slam' | 'stretch-lash';

const UNLOCK_LEVEL: Record<AbilityId, number> = {
  jump: 2,
  teleport: 5,
  'squash-slam': 3,
  'stretch-lash': 4,
};

const JUMP_COOLDOWN_MS = 700;
const JUMP_DISTANCE = 168;
const JUMP_DURATION_MS = 420;
const JUMP_ARC_HEIGHT = 54;

const TELEPORT_COOLDOWN_MS = 1800;
const TELEPORT_DISTANCE = 240;
const TELEPORT_ENERGY_COST = 35;

const SLAM_COOLDOWN_MS = 2500;
const SLAM_ENERGY_COST = 30;
const SLAM_RADIUS = 90;
const SLAM_DAMAGE = 30;

const LASH_COOLDOWN_MS = 2000;
const LASH_ENERGY_COST = 20;
const LASH_RANGE = 180;
const LASH_DAMAGE = 18;

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
  private cooldownUntil: Record<AbilityId, number> = {
    jump: 0,
    teleport: 0,
    'squash-slam': 0,
    'stretch-lash': 0,
  };
  private busy = false;

  constructor(ctx: AbilitySystemContext) {
    this.ctx = ctx;
  }

  unlockLevel(ability: AbilityId): number {
    return UNLOCK_LEVEL[ability];
  }

  isUnlocked(ability: AbilityId): boolean {
    return gameState.level >= UNLOCK_LEVEL[ability];
  }

  isBusy(): boolean {
    return this.busy;
  }

  /** Attempt to jump in the given direction (or facing if zero). */
  tryJump(direction: Phaser.Math.Vector2): boolean {
    if (this.busy) return false;
    if (!this.isUnlocked('jump')) {
      this.notifyLocked('jump');
      return false;
    }
    const scene = this.ctx.scene;
    if (scene.time.now < this.cooldownUntil.jump) return false;
    if (this.ctx.isActionLocked()) return false;

    const dir = direction.lengthSq() > 0
      ? direction.clone().normalize()
      : this.ctx.getFacing().clone().normalize();
    if (dir.lengthSq() === 0) {
      // Default to "up" if no facing at all.
      dir.set(0, -1);
    }

    const player = this.ctx.getPlayer();
    const visual = this.ctx.getPlayerVisual();
    const start = new Phaser.Math.Vector2(player.x, player.y);
    const target = this.raycast(start, dir, JUMP_DISTANCE);

    // If we can't move meaningfully, treat as a small in-place hop.
    const dist = Phaser.Math.Distance.Between(start.x, start.y, target.x, target.y);
    if (dist < 8) {
      target.set(start.x + dir.x * 12, start.y + dir.y * 12);
    }

    this.busy = true;
    this.ctx.setActionLocked(true);
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
      duration: JUMP_DURATION_MS / 2,
      ease: 'Quad.Out',
    });
    scene.tweens.add({
      targets: visual.effects,
      scaleX: 0.82,
      scaleY: 1.35,
      duration: JUMP_DURATION_MS / 2,
      ease: 'Quad.Out',
    });
    // Down: squash + land at target.
    scene.tweens.add({
      targets: player,
      x: target.x,
      y: target.y,
      duration: JUMP_DURATION_MS / 2,
      delay: JUMP_DURATION_MS / 2,
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

        this.busy = false;
        this.ctx.setActionLocked(false);
        this.ctx.playAnimation('slime-idle');
      },
    });
    scene.tweens.add({
      targets: visual.effects,
      scaleX: 1.18,
      scaleY: 0.7,
      duration: JUMP_DURATION_MS / 2,
      delay: JUMP_DURATION_MS / 2,
      ease: 'Quad.In',
    });

    // Shadow fades as we "rise" and returns at landing.
    scene.tweens.add({
      targets: shadow,
      alpha: 0.12,
      scaleX: 0.7,
      scaleY: 0.7,
      duration: JUMP_DURATION_MS / 2,
      yoyo: true,
      onComplete: () => shadow.destroy(),
    });

    this.cooldownUntil.jump = scene.time.now + JUMP_COOLDOWN_MS;
    return true;
  }

  /** Attempt to teleport (blink) in the given direction (or facing). */
  tryTeleport(direction: Phaser.Math.Vector2): boolean {
    if (this.busy) return false;
    if (!this.isUnlocked('teleport')) {
      this.notifyLocked('teleport');
      return false;
    }
    const scene = this.ctx.scene;
    if (scene.time.now < this.cooldownUntil.teleport) return false;
    if (this.ctx.isActionLocked()) return false;

    if (gameState.energy < TELEPORT_ENERGY_COST) {
      floatingText.spawn(scene, this.ctx.getPlayer().x, this.ctx.getPlayer().y - 30, 'Low energy', 'orange');
      return false;
    }

    const dir = direction.lengthSq() > 0
      ? direction.clone().normalize()
      : this.ctx.getFacing().clone().normalize();
    if (dir.lengthSq() === 0) dir.set(0, -1);

    const player = this.ctx.getPlayer();
    const visual = this.ctx.getPlayerVisual();
    const start = new Phaser.Math.Vector2(player.x, player.y);
    const target = this.raycast(start, dir, TELEPORT_DISTANCE);

    this.busy = true;
    this.ctx.setActionLocked(true);
    gameState.useEnergy(TELEPORT_ENERGY_COST);

    // Afterimage at origin.
    this.spawnFlash(start.x, start.y, 0x6be0ff);
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
            this.busy = false;
            this.ctx.setActionLocked(false);
            this.ctx.playAnimation('slime-idle');
          },
        });
      },
    });

    this.cooldownUntil.teleport = scene.time.now + TELEPORT_COOLDOWN_MS;
    return true;
  }

  /** Squash Slam — AoE shockwave around the player. Unlocks at level 3. */
  trySquashSlam(): boolean {
    if (this.busy) return false;
    if (!this.isUnlocked('squash-slam')) {
      this.notifyLocked('squash-slam');
      return false;
    }
    const scene = this.ctx.scene;
    if (scene.time.now < this.cooldownUntil['squash-slam']) return false;
    if (this.ctx.isActionLocked()) return false;
    if (gameState.energy < SLAM_ENERGY_COST) {
      floatingText.spawn(scene, this.ctx.getPlayer().x, this.ctx.getPlayer().y - 30, 'Low energy', 'orange');
      return false;
    }

    const player = this.ctx.getPlayer();
    const visual = this.ctx.getPlayerVisual();
    gameState.useEnergy(SLAM_ENERGY_COST);

    this.busy = true;
    this.ctx.setActionLocked(true);
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
            const ring = scene.add.circle(player.x, player.y, 10, 0x88ffaa, 0.5).setDepth(resolveWorldDepth(player.y, {
              band: 'reveal-effects',
              stableId: 'player-squash-slam',
              attachmentSlot: -2,
            }).depth);
            scene.tweens.add({
              targets: ring,
              scale: SLAM_RADIUS / 10,
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
                width: SLAM_RADIUS * 2,
                height: SLAM_RADIUS * 2,
                damage: SLAM_DAMAGE,
                durationMs: 200,
                knockStrength: 320,
                vfxColor: 0x88ffaa,
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
                this.busy = false;
                this.ctx.setActionLocked(false);
                this.ctx.playAnimation('slime-idle');
              },
            });
          },
        });
      },
    });

    this.cooldownUntil['squash-slam'] = scene.time.now + SLAM_COOLDOWN_MS;
    return true;
  }

  /** Stretch Lash — long-range tongue/whip attack in facing direction. Lv 4. */
  tryStretchLash(): boolean {
    if (this.busy) return false;
    if (!this.isUnlocked('stretch-lash')) {
      this.notifyLocked('stretch-lash');
      return false;
    }
    const scene = this.ctx.scene;
    if (scene.time.now < this.cooldownUntil['stretch-lash']) return false;
    if (this.ctx.isActionLocked()) return false;
    if (gameState.energy < LASH_ENERGY_COST) {
      floatingText.spawn(scene, this.ctx.getPlayer().x, this.ctx.getPlayer().y - 30, 'Low energy', 'orange');
      return false;
    }

    const player = this.ctx.getPlayer();
    const visual = this.ctx.getPlayerVisual();
    const facing = this.ctx.getFacing();
    const dir = facing.lengthSq() > 0 ? facing.clone().normalize() : new Phaser.Math.Vector2(1, 0);

    gameState.useEnergy(LASH_ENERGY_COST);

    this.busy = true;
    this.ctx.setActionLocked(true);
    this.ctx.playAnimation('slime-stretch');
    player.setVelocity(0, 0);

    // Stretch in facing direction.
    const stretchX = player.x + dir.x * LASH_RANGE * 0.5;
    const stretchY = player.y + dir.y * LASH_RANGE * 0.5;

    scene.tweens.add({
      targets: player,
      x: stretchX,
      y: stretchY,
      duration: 180,
      ease: 'Quad.Out',
      onComplete: () => {
        // Lash VFX: a line from player to the lash tip.
        const tipX = player.x + dir.x * LASH_RANGE * 0.5;
        const tipY = player.y + dir.y * LASH_RANGE * 0.5;
        const lash = scene.add.graphics().setDepth(resolveWorldDepth(player.y, {
          band: 'reveal-effects',
          stableId: 'player-stretch-lash',
          attachmentSlot: -2,
        }).depth);
        lash.lineStyle(4, 0xff9a3c, 0.8);
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
          const hx = player.x + dir.x * LASH_RANGE * 0.4;
          const hy = player.y + dir.y * LASH_RANGE * 0.4;
          hitboxPool.spawn(scene, targets, {
            x: hx,
            y: hy,
            width: LASH_RANGE,
            height: 40,
            damage: LASH_DAMAGE,
            durationMs: 160,
            knockX: dir.x,
            knockY: dir.y,
            knockStrength: 280,
            vfxColor: 0xff9a3c,
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
          x: player.x - dir.x * LASH_RANGE * 0.3,
          y: player.y - dir.y * LASH_RANGE * 0.3,
          duration: 200,
          ease: 'Quad.In',
          onComplete: () => {
            this.busy = false;
            this.ctx.setActionLocked(false);
            this.ctx.playAnimation('slime-idle');
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

    this.cooldownUntil['stretch-lash'] = scene.time.now + LASH_COOLDOWN_MS;
    return true;
  }

  update(): void {
    // Nothing per-frame for now; cooldowns read lazily.
  }

  destroy(): void {
    this.busy = false;
  }

  // ── helpers ──

  private notifyLocked(ability: AbilityId): void {
    const scene = this.ctx.scene;
    const need = UNLOCK_LEVEL[ability];
    const player = this.ctx.getPlayer();
    floatingText.spawn(scene, player.x, player.y - 30, `Locked — Lv ${need}`, 'red');
  }

  /** March from `start` in `dir` up to `maxDist`; stop just before a solid tile. */
  private raycast(start: Phaser.Math.Vector2, dir: Phaser.Math.Vector2, maxDist: number): Phaser.Math.Vector2 {
    const grid = this.ctx.getTerrainGrid();
    const steps = Math.ceil(maxDist / 8);
    let lastValid = start.clone();

    for (let i = 1; i <= steps; i += 1) {
      const d = (i / steps) * maxDist;
      const x = start.x + dir.x * d;
      const y = start.y + dir.y * d;
      const tileX = Math.floor(x / this.ctx.dimensions.tileSize);
      const tileY = Math.floor(y / this.ctx.dimensions.tileSize);

      if (tileY < 0 || tileY >= grid.length || tileX < 0 || tileX >= grid[0].length) break;

      const tileId = grid[tileY]?.[tileX];
      if (tileId && isTileCollidable(tileId)) break;

      lastValid = new Phaser.Math.Vector2(x, y);
    }

    return lastValid;
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
