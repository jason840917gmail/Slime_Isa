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
import { resolveWorldDepth } from '../../../presentation/WorldDepth';
import type { WorldVisual } from '../../../presentation/WorldVisual';
import { floatingText } from '../../../ui/FloatingText';

const JUMP_ARC_HEIGHT = 54;

export interface LegacyPlayerAbilityPresentationContext {
  readonly scene: Phaser.Scene;
  readonly getPlayer: () => Phaser.Physics.Arcade.Sprite;
  readonly getPlayerVisual: () => WorldVisual;
  readonly stopPlayerMotion: () => void;
  readonly teleportPlayer: (position: Readonly<{ x: number; y: number }>) => void;
  readonly playAnimation: (key: string) => void;
  readonly getCombatTargets: () => Phaser.Physics.Arcade.Group | null;
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

  notifyRejected(
    _abilityId: PlayerAbilityId,
    reason: PlayerAbilityRejectionReason,
    unlockLevel?: number,
  ): void {
    const player = this.context.getPlayer();
    if (reason !== 'busy') gameEvents.emit('player.action', { anim: 'ability-denied' });
    if (reason === 'locked') {
      floatingText.spawn(this.context.scene, player.x, player.y - 30, `Locked - Lv ${unlockLevel ?? '?'}`, 'red');
    } else if (reason === 'energy') {
      floatingText.spawn(this.context.scene, player.x, player.y - 30, 'Low energy', 'orange');
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
    lease.trackTween(scene.tweens.add({ targets: visual.effects, scaleX: 0.82, scaleY: 1.35, duration: durationMs / 2, ease: 'Quad.Out' }));
    lease.trackTween(scene.tweens.add({
      targets: visual.effects,
      offsetX: target.x - start.x,
      offsetY: target.y - start.y,
      duration: durationMs / 2,
      delay: durationMs / 2,
      ease: 'Quad.In',
      onComplete: () => {
        this.context.teleportPlayer(target);
        gameEvents.emit('player.action', { anim: 'jump-land' });
        visual.effects.offsetX = 0;
        visual.effects.offsetY = 0;
        lease.trackTween(scene.tweens.add({ targets: visual.effects, scaleX: 1, scaleY: 1, duration: 120, ease: 'Back.Out' }));
        const dust = scene.add.particles(target.x, target.y, 'xp-orb', {
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
            scene.cameras.main.shake(150, 0.01);
            gameEvents.emit('player.action', { anim: 'slam-impact' });
            const targets = this.context.getCombatTargets();
            if (targets) {
              lease.trackHitbox(hitboxPool.spawn(scene, targets, {
                x: player.x,
                y: player.y,
                width: radius * 2,
                height: radius * 2,
                damage,
                durationMs: 200,
                knockStrength: 320,
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

  private presentStretchLash(intent: PlayerAbilityIntent, lease: PhaserAbilityLease, complete: () => void): void {
    const scene = this.context.scene;
    const player = this.context.getPlayer();
    const visual = this.context.getPlayerVisual();
    const direction = intent.direction;
    const range = intent.definition.distance ?? 180;
    const damage = intent.definition.damage ?? 18;
    this.context.playAnimation('slime-stretch');
    this.context.stopPlayerMotion();
    const stretchX = player.x + direction.x * range * 0.5;
    const stretchY = player.y + direction.y * range * 0.5;
    lease.trackTween(scene.tweens.add({
      targets: visual.effects,
      offsetX: stretchX - intent.start.x,
      offsetY: stretchY - intent.start.y,
      duration: 180,
      ease: 'Quad.Out',
      onComplete: () => {
        const tipX = intent.start.x + direction.x * range;
        const tipY = intent.start.y + direction.y * range;
        const lash = scene.add.graphics().setDepth(resolveWorldDepth(player.y, {
          band: 'reveal-effects', stableId: 'player-stretch-lash', attachmentSlot: -2,
        }).depth);
        lease.trackObject(lash);
        lash.lineStyle(4, 0xffad66, 0.8);
        lash.beginPath();
        lash.moveTo(player.x, player.y);
        lash.lineTo(tipX, tipY);
        lash.strokePath();
        lease.trackTween(scene.tweens.add({
          targets: lash,
          alpha: 0,
          duration: 200,
          onComplete: () => lash.destroy(),
        }));
        const targets = this.context.getCombatTargets();
        if (targets) {
          lease.trackHitbox(hitboxPool.spawn(scene, targets, {
            x: player.x + direction.x * range * 0.4,
            y: player.y + direction.y * range * 0.4,
            width: range,
            height: 40,
            damage,
            durationMs: 160,
            knockX: direction.x,
            knockY: direction.y,
            knockStrength: 280,
            vfxColor: 0xffad66,
            showVfx: false,
          }, (target, appliedDamage, knockX, knockY, knockStrength) => {
            if (!(target instanceof TargetDummy)) return;
            target.takeDamage(appliedDamage, knockX, knockY, knockStrength);
            floatingText.spawn(scene, target.x, target.y - 24, `${appliedDamage}`, 'orange', true);
          }));
        }
        lease.trackTween(scene.tweens.add({
          targets: visual.effects,
          offsetX: direction.x * range * 0.2,
          offsetY: direction.y * range * 0.2,
          duration: 200,
          ease: 'Quad.In',
          onComplete: () => {
            this.context.teleportPlayer({
              x: intent.start.x + direction.x * range * 0.2,
              y: intent.start.y + direction.y * range * 0.2,
            });
            visual.effects.offsetX = 0;
            visual.effects.offsetY = 0;
            complete();
          },
        }));
        lease.trackTween(scene.tweens.add({ targets: visual.effects, scaleX: 1, scaleY: 1, duration: 200, ease: 'Quad.In' }));
      },
    }));
    lease.trackTween(scene.tweens.add({ targets: visual.effects, scaleX: 1.5, scaleY: 0.64, duration: 180, ease: 'Quad.Out' }));
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
