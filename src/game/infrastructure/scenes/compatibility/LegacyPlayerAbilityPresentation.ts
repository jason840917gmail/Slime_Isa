import Phaser from 'phaser';

import { hitboxPool, type HitboxActivationHandle } from '../../../combat/Hitbox';
import { gameEvents } from '../../../core/EventBus';
import { TargetDummy } from '../../../combat/TargetDummy';
import type { PlayerAbilityId } from '../../../features/player/PlayerAbilityDefinitions';
import type {
  PlayerAbilityPresentationBackend,
  PlayerAbilityPresentationLease,
} from '../../../features/player/PlayerAbilityPresentation';
import type {
  PlayerAbilityIntent,
  PlayerAbilityRejectionReason,
} from '../../../features/player/PlayerAbilityService';
import type { AbilityWorldPort, LashCatch } from '../../../features/combat/LineStrike';
import { resolveWorldDepth } from '../../../presentation/WorldDepth';
import type { WorldVisual } from '../../../presentation/WorldVisual';
import { floatingText } from '../../../ui/FloatingText';
import { gameFeel } from '../../../features/feel/sharedFeel';
import { SQUASH_PRESETS, squashStart } from '../../../features/feel/SquashStretch';
import { gameSettings } from '../../../features/settings/GameSettingsService';

const JUMP_ARC_HEIGHT = 54;

/**
 * The Stretch Lash sheet (`effect.player.stretch-lash`, packed by
 * scripts/effects/pack-stretch-lash.py): frames 384 px long, drawn at twice
 * the display size, the tendril's centre line 52 px down.
 */
const STRETCH_LASH_SHEET = {
  textureKey: 'effect-player-stretch-lash',
  frameWidth: 384,
  originY: 52 / 96,
  scaleY: 0.5,
  halfWidthPx: 16,
  minReachPx: 48,
} as const;
/** How fast a heavy catch pulls the slime (px per ms). */
const STRETCH_LASH_PULL_SPEED = 0.9;
const SQUASH_SLAM_KNOCKBACK = 320;

export interface LegacyPlayerAbilityPresentationContext {
  readonly scene: Phaser.Scene;
  readonly getPlayer: () => Phaser.Physics.Arcade.Sprite;
  readonly getPlayerVisual: () => WorldVisual;
  readonly stopPlayerMotion: () => void;
  readonly teleportPlayer: (position: Readonly<{ x: number; y: number }>) => void;
  readonly playAnimation: (key: string) => void;
  readonly getCombatTargets: () => Phaser.Physics.Arcade.Group | null;
  /** The scene world for abilities (the lash hook, the slam's strike); absent in tests without a world. */
  readonly abilityWorld?: AbilityWorldPort;
}

class PhaserAbilityLease implements PlayerAbilityPresentationLease {
  private readonly cleanups: Array<() => void> = [];
  private disposed = false;

  add(cleanup: () => void): void {
    if (this.disposed) cleanup();
    else this.cleanups.push(cleanup);
  }

  trackTween(tween: Phaser.Tweens.Tween): void {
    this.add(() => {
      if (!tween.isDestroyed()) {
        tween.stop();
        tween.remove();
      }
    });
  }

  trackObject(object: Phaser.GameObjects.GameObject): void {
    this.add(() => { if (object.scene) object.destroy(); });
  }

  trackTimer(timer: Phaser.Time.TimerEvent): void {
    this.add(() => timer.remove(false));
  }

  trackHitbox(handle: HitboxActivationHandle): void {
    this.add(() => handle.deactivate());
  }

  complete(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.cleanups.length = 0;
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    for (let index = this.cleanups.length - 1; index >= 0; index -= 1) this.cleanups[index]?.();
    this.cleanups.length = 0;
  }
}

/** Temporary Phaser backend retained while the authored player effect nodes land. */
export class LegacyPlayerAbilityPresentation implements PlayerAbilityPresentationBackend {
  constructor(private readonly context: LegacyPlayerAbilityPresentationContext) {}

  present(intent: PlayerAbilityIntent, complete: () => void): PlayerAbilityPresentationLease {
    const lease = new PhaserAbilityLease();
    const visual = this.context.getPlayerVisual();
    lease.add(() => {
      this.context.scene.tweens.killTweensOf(visual.effects);
      visual.resetEffects();
    });
    gameEvents.emit('player.action', { anim: `ability-${intent.abilityId}` });
    switch (intent.abilityId) {
      case 'jump': this.presentJump(intent, lease, complete); break;
      case 'teleport': this.presentTeleport(intent, lease, complete); break;
      case 'squash-slam': this.presentSquashSlam(intent, lease, complete); break;
      case 'stretch-lash': this.presentStretchLash(intent, lease, complete); break;
    }
    return lease;
  }

  notifyRejected(_abilityId: PlayerAbilityId, reason: PlayerAbilityRejectionReason): void {
    const player = this.context.getPlayer();
    if (reason !== 'busy') gameEvents.emit('player.action', { anim: 'ability-denied' });
    if (reason === 'locked') {
      floatingText.spawn(this.context.scene, player.x, player.y - 30, 'Not learned yet', 'red');
    } else if (reason === 'energy') {
      floatingText.spawn(this.context.scene, player.x, player.y - 30, 'Low energy', 'orange');
    } else if (reason === 'blocked') {
      floatingText.spawn(this.context.scene, player.x, player.y - 30, 'No safe spot there', 'orange');
    }
  }

  private presentJump(intent: PlayerAbilityIntent, lease: PhaserAbilityLease, complete: () => void): void {
    const scene = this.context.scene;
    const visual = this.context.getPlayerVisual();
    const { start, target } = intent;
    const durationMs = intent.definition.durationMs ?? 420;
    this.context.playAnimation('slime-hop');
    this.context.stopPlayerMotion();
    visual.resetEffects();

    const shadow = scene.add.ellipse(start.x, start.y, 40, 16, 0x000000, 0.35)
      .setDepth(resolveWorldDepth(start.y, { stableId: 'player-jump-shadow', attachmentSlot: -6 }).depth)
      .setAlpha(0.35);
    lease.trackObject(shadow);
    const midX = (start.x + target.x) / 2;
    const midY = (start.y + target.y) / 2 - JUMP_ARC_HEIGHT;
    lease.trackTween(scene.tweens.add({
      targets: visual.effects,
      offsetX: midX - start.x,
      offsetY: midY - start.y,
      duration: durationMs / 2,
      ease: 'Quad.Out',
    }));
    // Take-off stretch (9.2), softened under reduce motion.
    const stretch = squashStart(SQUASH_PRESETS.jump, gameSettings.settings.reduceMotion);
    lease.trackTween(scene.tweens.add({ targets: visual.effects, scaleX: stretch.x, scaleY: stretch.y, duration: durationMs / 2, ease: SQUASH_PRESETS.jump.ease }));
    lease.trackTween(scene.tweens.add({
      targets: visual.effects,
      offsetX: target.x - start.x,
      offsetY: target.y - start.y,
      duration: durationMs / 2,
      delay: durationMs / 2,
      ease: 'Quad.In',
      onComplete: () => {
        this.context.teleportPlayer(target);
        visual.effects.offsetX = 0;
        visual.effects.offsetY = 0;
        // Back at rest; the world's squash and stretch plays the landing splat on 'jump-land'.
        visual.effects.scaleX = 1;
        visual.effects.scaleY = 1;
        gameEvents.emit('player.action', { anim: 'jump-land' });
        const dust = scene.add.particles(target.x, target.y, 'goo-dust', {
          lifespan: 320,
          speed: { min: 20, max: 60 },
          scale: { start: 0.3, end: 0 },
          alpha: { start: 0.6, end: 0 },
          quantity: 8,
          emitting: false,
        }).setDepth(resolveWorldDepth(target.y, {
          band: 'reveal-effects', stableId: 'player-jump-dust', attachmentSlot: -5,
        }).depth);
        lease.trackObject(dust);
        dust.emitParticle(8);
        lease.trackTimer(scene.time.delayedCall(400, () => dust.destroy()));
        complete();
      },
    }));
    lease.trackTween(scene.tweens.add({
      targets: visual.effects,
      scaleX: 1.18,
      scaleY: 0.7,
      duration: durationMs / 2,
      delay: durationMs / 2,
      ease: 'Quad.In',
    }));
    lease.trackTween(scene.tweens.add({
      targets: shadow,
      alpha: 0.12,
      scaleX: 0.7,
      scaleY: 0.7,
      duration: durationMs / 2,
      yoyo: true,
      onComplete: () => shadow.destroy(),
    }));
  }

  private presentTeleport(intent: PlayerAbilityIntent, lease: PhaserAbilityLease, complete: () => void): void {
    const scene = this.context.scene;
    const visual = this.context.getPlayerVisual();
    this.spawnFlash(intent.start.x, intent.start.y, 0x72d8ff, lease);
    this.context.playAnimation('slime-teleport');
    this.context.stopPlayerMotion();
    lease.trackTween(scene.tweens.add({
      targets: visual.effects,
      alpha: 0,
      scaleX: 0.36,
      scaleY: 0.36,
      duration: 120,
      ease: 'Quad.In',
      onComplete: () => {
        this.context.teleportPlayer(intent.target);
        gameEvents.emit('player.action', { anim: 'teleport-in' });
        this.spawnFlash(intent.target.x, intent.target.y, 0xa3f0c0, lease);
        lease.trackTween(scene.tweens.add({
          targets: visual.effects,
          alpha: 1,
          scaleX: 1,
          scaleY: 1,
          duration: 180,
          ease: 'Back.Out',
          onComplete: complete,
        }));
      },
    }));
  }

  private presentSquashSlam(intent: PlayerAbilityIntent, lease: PhaserAbilityLease, complete: () => void): void {
    const scene = this.context.scene;
    const player = this.context.getPlayer();
    const visual = this.context.getPlayerVisual();
    const radius = intent.definition.radius ?? 90;
    const damage = intent.definition.damage ?? 30;
    this.context.playAnimation('slime-squash');
    this.context.stopPlayerMotion();
    lease.trackTween(scene.tweens.add({
      targets: visual.effects,
      scaleY: 1.36,
      duration: 200,
      ease: 'Quad.Out',
      onComplete: () => {
        lease.trackTween(scene.tweens.add({
          targets: visual.effects,
          scaleY: 0.64,
          duration: 120,
          ease: 'Quad.In',
          onComplete: () => {
            const ring = scene.add.circle(player.x, player.y, 10, 0x86f0c3, 0.5).setDepth(resolveWorldDepth(player.y, {
              band: 'reveal-effects', stableId: 'player-squash-slam', attachmentSlot: -2,
            }).depth);
            lease.trackObject(ring);
            lease.trackTween(scene.tweens.add({
              targets: ring,
              scale: radius / 10,
              alpha: 0,
              duration: 300,
              onComplete: () => ring.destroy(),
            }));
            gameFeel.play('slam');
            gameEvents.emit('player.action', { anim: 'slam-impact' });
            // Enemies (and other damage receivers) around the landing.
            this.context.abilityWorld?.strikeArea({
              abilityId: 'squash-slam',
              center: { x: player.x, y: player.y },
              radius,
              damage,
              knockback: SQUASH_SLAM_KNOCKBACK,
              weaponTags: ['slam'],
            });
            const targets = this.context.getCombatTargets();
            if (targets) {
              lease.trackHitbox(hitboxPool.spawn(scene, targets, {
                x: player.x,
                y: player.y,
                width: radius * 2,
                height: radius * 2,
                damage,
                durationMs: 200,
                knockStrength: SQUASH_SLAM_KNOCKBACK,
                vfxColor: 0x86f0c3,
                showVfx: false,
              }, (target, appliedDamage, _knockX, _knockY, knockStrength) => {
                if (!(target instanceof TargetDummy)) return;
                const dx = target.x - player.x;
                const dy = target.y - player.y;
                const length = Math.hypot(dx, dy) || 1;
                target.takeDamage(appliedDamage, dx / length, dy / length, knockStrength);
                floatingText.spawn(scene, target.x, target.y - 24, `${appliedDamage}`, 'yellow', true);
              }));
            }
            lease.trackTween(scene.tweens.add({
              targets: visual.effects,
              scaleY: 1,
              duration: 150,
              ease: 'Back.Out',
              onComplete: complete,
            }));
          },
        }));
      },
    }));
  }

  /**
   * The Stretch Lash is a goo hook (`STRETCH_LASH_SHEET`), not a weapon: it
   * reaches along the slime's facing until it catches something. A loose
   * pickup flies back to the slime; anything solid (a tree, rock, post, wall
   * or bell) pulls the slime across to it, over water too, and a bell it
   * catches rings. It does no damage.
   */
  private presentStretchLash(intent: PlayerAbilityIntent, lease: PhaserAbilityLease, complete: () => void): void {
    const scene = this.context.scene;
    const visual = this.context.getPlayerVisual();
    const world = this.context.abilityWorld;
    const direction = intent.direction;
    const range = intent.definition.distance ?? 180;
    const halfWidth = STRETCH_LASH_SHEET.halfWidthPx;
    const from = { x: intent.start.x, y: intent.start.y };
    const wanted = { x: from.x + direction.x * range, y: from.y + direction.y * range };
    const caught: LashCatch = world?.lashProbe(from, wanted, halfWidth) ?? { kind: 'none', at: wanted };
    const tipDistance = Math.hypot(caught.at.x - from.x, caught.at.y - from.y);
    this.context.playAnimation('slime-stretch');
    this.context.stopPlayerMotion();
    // A short lean into the throw.
    lease.trackTween(scene.tweens.add({
      targets: visual.effects,
      offsetX: direction.x * 8,
      offsetY: direction.y * 8,
      scaleX: 1.14,
      scaleY: 0.88,
      duration: 110,
      ease: 'Quad.Out',
      yoyo: true,
    }));

    const lash = scene.textures.exists(STRETCH_LASH_SHEET.textureKey)
      ? scene.add.sprite(from.x, from.y, STRETCH_LASH_SHEET.textureKey, 0)
        .setOrigin(0, STRETCH_LASH_SHEET.originY)
        .setRotation(Math.atan2(direction.y, direction.x))
      : undefined;
    if (lash) lease.trackObject(lash);
    /** Draws the tendril from `at` reaching `length` px, showing `frame`. */
    const draw = (frame: number, at: Readonly<{ x: number; y: number }> = from, length = tipDistance) => {
      if (!lash?.scene) return;
      lash.setFrame(frame)
        .setPosition(at.x, at.y)
        .setScale(Math.max(STRETCH_LASH_SHEET.minReachPx, length) / STRETCH_LASH_SHEET.frameWidth, STRETCH_LASH_SHEET.scaleY)
        .setDepth(resolveWorldDepth(at.y, { stableId: 'player-stretch-lash', attachmentSlot: -2 }).depth);
    };
    const finish = () => {
      if (lash?.scene) lash.destroy();
      complete();
    };
    const at = (delay: number, step: () => void) => {
      if (delay === 0) step();
      else lease.trackTimer(scene.time.delayedCall(delay, step));
    };

    // Reach out (frames 0-3), then act on the catch.
    at(0, () => draw(0));
    at(40, () => draw(1));
    at(80, () => draw(2));
    at(120, () => {
      if (caught.kind === 'light') {
        draw(4);
        const player = this.context.getPlayer();
        world?.lashPull(caught.pickupId, { x: player.x, y: player.y });
        at(60, () => draw(6));
        at(120, () => draw(7));
        at(170, finish);
        return;
      }
      if (caught.kind === 'heavy' && world) {
        draw(4);
        world.lashRing(from, caught.at, halfWidth);
        const landing = world.lashLanding(from, caught.anchor ?? caught.at);
        const travel = Math.hypot(landing.x - from.x, landing.y - from.y);
        if (travel < 8) {
          at(60, () => draw(6));
          at(110, () => draw(7));
          at(160, finish);
          return;
        }
        const flight = { progress: 0 };
        at(50, () => lease.trackTween(scene.tweens.add({
          targets: flight,
          progress: 1,
          duration: Math.max(120, travel / STRETCH_LASH_PULL_SPEED),
          ease: 'Quad.In',
          onUpdate: () => {
            const position = { x: from.x + (landing.x - from.x) * flight.progress, y: from.y + (landing.y - from.y) * flight.progress };
            this.context.teleportPlayer(position);
            draw(3, position, Math.hypot(caught.at.x - position.x, caught.at.y - position.y));
          },
          onComplete: () => {
            if (lash?.scene) lash.destroy();
            // Arrive with a little squash.
            lease.trackTween(scene.tweens.add({
              targets: visual.effects,
              scaleX: 1.2,
              scaleY: 0.82,
              duration: 90,
              ease: 'Quad.Out',
              yoyo: true,
              onComplete: complete,
            }));
          },
        })));
        return;
      }
      draw(3);
      at(50, () => draw(6));
      at(100, () => draw(7));
      at(150, finish);
    });
  }

  private spawnFlash(x: number, y: number, color: number, lease: PhaserAbilityLease): void {
    const scene = this.context.scene;
    const flash = scene.add.circle(x, y, 10, color, 0.9).setDepth(resolveWorldDepth(y, {
      band: 'reveal-effects', stableId: `ability-flash:${color}`, attachmentSlot: -1,
    }).depth);
    lease.trackObject(flash);
    lease.trackTween(scene.tweens.add({
      targets: flash,
      scale: 6,
      alpha: 0,
      duration: 260,
      ease: 'Quad.Out',
      onComplete: () => flash.destroy(),
    }));
  }
}
