import Phaser from 'phaser';

import { attackIntersectsCombatBody } from '../../combat/CombatBodyGeometry';
import { acceptedDamage, rejectedDamage, type DamageApplicationResult } from '../../combat/DamageableTarget';
import type { WeaponHitRequest } from '../../combat/WeaponHitRequest';
import type { BossDefinition } from '../../content/bosses/types';
import { getBossEditorPreview } from '../../content/bosses/BossCatalog';
import { getCharacterPackage } from '../../content/characters/CharacterCatalog';
import type { CharacterHitboxDocument, CharacterPackage } from '../../content/characters/types';
import type { MapEnemyAreaPerimeter, MapPoint } from '../../content/maps/mapFormat';
import { isEnemyEffectImmune } from '../../content/enemies/EnemyEffects';
import { CharacterAnimationTrackRunner } from '../characters/CharacterAnimationTrackRunner';
import { characterHitboxIntersectsCombatBody, resolveCharacterHitboxGeometry } from '../characters/characterHitboxGeometry';
import { getAsset } from '../../infrastructure/assets/manifest';
import { resolveWorldDepth } from '../../presentation/WorldDepth';
import { normalizeAnimationClip } from '../../shared/animation';
import {
  bossAnchorOutsideArena,
  bossArenaCenter,
  canBossBeginAttack,
  canRequestContactHop,
  contactHopProgress,
  contactHopVisualHeight,
  shouldBossReturnToArenaCenter,
  shouldResumePursuitFromReturn,
  type FattyOneEyePhase,
} from './FattyOneEyeBehavior';

export interface FattyOneEyeBossContext {
  readonly scene: Phaser.Scene;
  readonly definition: BossDefinition;
  readonly spawn: MapPoint;
  readonly arena: MapEnemyAreaPerimeter;
  readonly getPlayer: () => Phaser.Physics.Arcade.Sprite;
  readonly isPlayerDodging: () => boolean;
  readonly applyPlayerDamage: (amount: number, source: string, impactX: number, impactY: number, knockbackStrength: number) => void;
  readonly onDefeated: (boss: FattyOneEyeBoss) => void;
}

function animationFrame(from: number, through: number, elapsedMs: number, frameMs: number): number {
  const count = through - from + 1;
  return from + Math.floor(Math.max(0, elapsedMs) / frameMs) % count;
}

function clampToArena(point: Phaser.Math.Vector2, arena: MapEnemyAreaPerimeter): Phaser.Math.Vector2 {
  if (arena.shape === 'rectangle') {
    point.x = Phaser.Math.Clamp(point.x, arena.x, arena.x + arena.w);
    point.y = Phaser.Math.Clamp(point.y, arena.y, arena.y + arena.h);
    return point;
  }
  const delta = point.clone().subtract(new Phaser.Math.Vector2(arena.x, arena.y));
  if (delta.length() > arena.radius) delta.setLength(arena.radius);
  return delta.add(new Phaser.Math.Vector2(arena.x, arena.y));
}

function hitboxPresentationRadius(hitbox: CharacterHitboxDocument): number {
  return Math.max(hitbox.radius ?? 0, hitbox.radiusX ?? 0, hitbox.radiusY ?? 0, hitbox.width / 2, hitbox.height / 2);
}

/** Invisible combat anchor plus a separately elevated visual for the leap. */
export class FattyOneEyeBoss extends Phaser.Physics.Arcade.Sprite {
  readonly bossId: string;
  readonly maxHp: number;
  hp: number;
  dead = false;

  private readonly ctx: FattyOneEyeBossContext;
  private readonly characterPackage: CharacterPackage;
  private readonly contactHopImpactAtMs: number;
  private readonly contactHopRunner: CharacterAnimationTrackRunner;
  private readonly visual: Phaser.GameObjects.Sprite;
  private readonly shadow: Phaser.GameObjects.Ellipse;
  private readonly landingMarker: Phaser.GameObjects.Graphics;
  private phase: FattyOneEyePhase = 'chase';
  private phaseStartedAt = 0;
  private nextLeapAt = 0;
  private leapFrom = new Phaser.Math.Vector2();
  private leapTarget = new Phaser.Math.Vector2();
  private nextContactHopAt = 0;
  private contactHopAnchor = new Phaser.Math.Vector2();
  private contactHopImpactApplied = false;
  private hitFlashUntil = 0;
  private destroyedValue = false;
  private readonly transientEffects = new Set<Phaser.GameObjects.Sprite>();

  constructor(ctx: FattyOneEyeBossContext) {
    const preview = getBossEditorPreview(ctx.definition.id);
    const characterPackage = getCharacterPackage(ctx.definition.characterId);
    if (characterPackage.character.kind !== 'boss') throw new Error(`Boss '${ctx.definition.id}' must reference a boss character package`);
    if (characterPackage.character.visualSetId !== ctx.definition.visualSetId) throw new Error(`Boss '${ctx.definition.id}' visual set does not match its character package`);
    const contactHopClip = characterPackage.visualSet.clips[ctx.definition.contactHop.clipId];
    const contactHopHitbox = characterPackage.character.hitboxes[ctx.definition.contactHop.hitboxId];
    if (!contactHopClip || !contactHopHitbox) throw new Error(`Boss '${ctx.definition.id}' has invalid contact-hop animation references`);
    const normalizedContactHop = normalizeAnimationClip(contactHopClip);
    const impactSpan = characterPackage.character.animationTracks[ctx.definition.contactHop.clipId]?.hitboxSpans
      ?.find((span) => span.hitboxId === ctx.definition.contactHop.hitboxId);
    if (!impactSpan) throw new Error(`Boss '${ctx.definition.id}' contact-hop clip must activate its configured hitbox`);
    const contactHopImpactAtMs = impactSpan.from * 1000 / normalizedContactHop.framesPerSecond;
    super(ctx.scene, ctx.spawn.x, ctx.spawn.y, preview.textureKey, preview.frame);
    this.ctx = ctx;
    this.characterPackage = characterPackage;
    this.contactHopImpactAtMs = contactHopImpactAtMs;
    this.bossId = ctx.definition.id;
    this.maxHp = ctx.definition.maxHp;
    this.hp = this.maxHp;
    ctx.scene.add.existing(this);
    ctx.scene.physics.add.existing(this);
    this.setVisible(false).setImmovable(true).setCollideWorldBounds(true);
    const body = this.body as Phaser.Physics.Arcade.Body;
    body.setAllowGravity(false);
    body.setSize(ctx.definition.body.width, ctx.definition.body.height, true);

    this.shadow = ctx.scene.add.ellipse(this.x, this.y + 30, 96, 34, 0x07120e, 0.38).setVisible(false);
    this.visual = ctx.scene.add.sprite(this.x, this.y, preview.textureKey, preview.frame)
      .setOrigin(preview.origin[0], preview.origin[1])
      .setScale(preview.scale);
    this.landingMarker = ctx.scene.add.graphics().setVisible(false);
    this.contactHopRunner = new CharacterAnimationTrackRunner(characterPackage.character, characterPackage.visualSet, {
      onHitboxActivated: (hitboxId) => this.applyContactHopImpact(hitboxId),
      onComplete: () => {
        if (this.phase === 'contact-hop') this.completeContactHop(this.scene.time.now);
      },
    });
    this.phaseStartedAt = ctx.scene.time.now;
    this.nextLeapAt = ctx.scene.time.now + ctx.definition.leap.cadenceMs;
    this.syncPresentation(0);
  }

  updateBoss(time: number, deltaMs: number): void {
    if (this.destroyedValue) return;
    if (this.dead) {
      const elapsed = time - this.phaseStartedAt;
      this.visual.setFrame(Math.min(35, 30 + Math.floor(elapsed / 110)));
      if (elapsed >= 780) this.destroy();
      return;
    }

    if (this.phase === 'chase') {
      if (shouldBossReturnToArenaCenter(this.ctx.arena, this.ctx.getPlayer())) this.beginReturning(time);
      else this.updateChase(time);
    } else if (this.phase === 'return-to-center') this.updateReturning(time, deltaMs);
    else if (this.phase === 'contact-hop') this.contactHopRunner.update(deltaMs);
    else if (this.phase === 'small-hop') this.updateSmallHops(time);
    else if (this.phase === 'airborne') this.updateAirborne(time);
    else if (this.phase === 'landing' && time - this.phaseStartedAt >= 360) this.beginRecovery(time);
    else if (this.phase === 'recovery' && time - this.phaseStartedAt >= this.ctx.definition.leap.recoveryMs) {
      this.nextLeapAt = time + this.ctx.definition.leap.cadenceMs;
      if (shouldBossReturnToArenaCenter(this.ctx.arena, this.ctx.getPlayer())) this.beginReturning(time);
      else this.beginChase(time, true);
    }

    this.updateFrame(time);
    this.syncPresentation(deltaMs);
  }

  applyWeaponHit(request: WeaponHitRequest): DamageApplicationResult {
    if (this.dead || this.destroyedValue) return rejectedDamage('dead');
    if (this.phase === 'airborne' || this.phase === 'contact-hop') return rejectedDamage('invulnerable');
    if (!this.ctx.definition.allowedWeaponIds.includes(request.weaponId)) return rejectedDamage('invalid');
    const radius = Math.min(this.ctx.definition.eye.width, this.ctx.definition.eye.height) / 2;
    const eyeX = this.x + this.ctx.definition.eye.offsetX;
    const eyeY = this.y + this.ctx.definition.eye.offsetY;
    const intersectsEye = attackIntersectsCombatBody(request.hitbox, {
      shape: 'circle',
      x: eyeX - radius,
      y: eyeY - radius,
      width: radius * 2,
      height: radius * 2,
      centerX: eyeX,
      centerY: eyeY,
      radius,
    });
    if (!intersectsEye) return rejectedDamage('invalid');

    const before = this.hp;
    this.hp = Math.max(0, this.hp - Math.max(0, Math.round(request.damage)));
    this.hitFlashUntil = this.scene.time.now + 130;
    if (this.hp <= 0) this.defeat();
    if (!isEnemyEffectImmune(this.ctx.definition.effectImmunities, 'knockback') && this.phase === 'chase') {
      this.setVelocity(request.knockX * request.knockStrength, request.knockY * request.knockStrength);
    }
    return acceptedDamage(before, this.hp);
  }

  requestContactHop(time: number): boolean {
    if (!canRequestContactHop({
      alive: !this.dead,
      destroyed: this.destroyedValue,
      phase: this.phase,
      time,
      nextContactHopAt: this.nextContactHopAt,
    })) return false;
    if (!canBossBeginAttack(this.ctx.arena, this.ctx.getPlayer()) || bossAnchorOutsideArena(this.ctx.arena, this)) {
      this.beginReturning(time);
      return false;
    }

    this.phase = 'contact-hop';
    this.phaseStartedAt = time;
    this.nextContactHopAt = time + this.ctx.definition.contactHop.cooldownMs;
    this.contactHopAnchor.set(this.x, this.y);
    this.contactHopImpactApplied = false;
    this.setVelocity(0, 0);
    this.showContactHopPresentation();
    (this.body as Phaser.Physics.Arcade.Body).enable = false;
    this.contactHopRunner.start(this.ctx.definition.contactHop.clipId);
    this.syncPresentation(0);
    return true;
  }

  private updateChase(time: number): void {
    const player = this.ctx.getPlayer();
    if (!canBossBeginAttack(this.ctx.arena, player)) {
      this.beginReturning(time);
      return;
    }
    if (time >= this.nextLeapAt) {
      this.beginSmallHops(time);
      return;
    }
    const target = clampToArena(new Phaser.Math.Vector2(player.x, player.y), this.ctx.arena);
    const velocity = target.subtract(new Phaser.Math.Vector2(this.x, this.y));
    if (velocity.lengthSq() > 1) velocity.setLength(this.ctx.definition.chaseSpeed);
    const body = this.body as Phaser.Physics.Arcade.Body;
    body.setVelocity(velocity.x, velocity.y);
  }

  private beginReturning(time: number): void {
    this.phase = 'return-to-center';
    this.phaseStartedAt = time;
    this.setVelocity(0, 0);
  }

  private updateReturning(time: number, deltaMs: number): void {
    if (shouldResumePursuitFromReturn(this.ctx.arena, this.ctx.getPlayer())) {
      this.beginChase(time, true);
      this.updateChase(time);
      return;
    }
    const center = bossArenaCenter(this.ctx.arena);
    const velocity = new Phaser.Math.Vector2(center.x - this.x, center.y - this.y);
    const remaining = velocity.length();
    const step = this.ctx.definition.chaseSpeed * Math.max(0, deltaMs) / 1000;
    if (remaining <= Math.max(1, step)) {
      this.setPosition(center.x, center.y);
      this.setVelocity(0, 0);
      return;
    }
    velocity.setLength(this.ctx.definition.chaseSpeed);
    this.setVelocity(velocity.x, velocity.y);
  }

  private beginSmallHops(time: number): void {
    this.phase = 'small-hop';
    this.phaseStartedAt = time;
    this.setVelocity(0, 0);
  }

  private updateSmallHops(time: number): void {
    const stepMs = this.ctx.definition.leap.smallHopDurationMs + this.ctx.definition.leap.betweenHopsMs;
    const nextIndex = Math.floor((time - this.phaseStartedAt) / stepMs);
    if (nextIndex < this.ctx.definition.leap.smallHopCount) {
      return;
    }
    this.beginAirborne(time);
  }

  private beginAirborne(time: number): void {
    this.phase = 'airborne';
    this.phaseStartedAt = time;
    this.leapFrom.set(this.x, this.y);
    const player = this.ctx.getPlayer();
    this.leapTarget.set(player.x, player.y);
    this.setVelocity(0, 0);
    this.showLandingPresentation(this.leapTarget, this.ctx.definition.leap.landingRadius);
    (this.body as Phaser.Physics.Arcade.Body).enable = false;
  }

  private updateAirborne(time: number): void {
    const progress = Phaser.Math.Clamp((time - this.phaseStartedAt) / this.ctx.definition.leap.airTimeMs, 0, 1);
    this.setPosition(
      Phaser.Math.Linear(this.leapFrom.x, this.leapTarget.x, progress),
      Phaser.Math.Linear(this.leapFrom.y, this.leapTarget.y, progress),
    );
    if (progress >= 1) this.land(time);
  }

  private completeContactHop(time: number): void {
    this.contactHopRunner.stop();
    this.phaseStartedAt = time;
    this.enableBodyAt(this.contactHopAnchor);
    this.hideLandingPresentation();
    if (shouldBossReturnToArenaCenter(this.ctx.arena, this.ctx.getPlayer())) this.beginReturning(time);
    else this.phase = 'chase';
  }

  private applyContactHopImpact(hitboxId: string): void {
    if (this.phase !== 'contact-hop' || hitboxId !== this.ctx.definition.contactHop.hitboxId || this.contactHopImpactApplied) return;
    this.contactHopImpactApplied = true;
    this.hideLandingPresentation();
    this.spawnLandingCrack(hitboxPresentationRadius(this.contactHopHitbox()));
    const player = this.ctx.getPlayer();
    if (this.ctx.isPlayerDodging()) return;
    if (!characterHitboxIntersectsCombatBody(this.contactHopHitbox(), this.contactHopAnchor, 1, player)) return;
    const impact = new Phaser.Math.Vector2(player.x - this.contactHopAnchor.x, player.y - this.contactHopAnchor.y);
    if (impact.lengthSq() > 0) impact.normalize();
    this.ctx.applyPlayerDamage(
      this.ctx.definition.contactHop.damage,
      this.ctx.definition.id,
      impact.x,
      impact.y,
      this.ctx.definition.contactHop.knockbackStrength,
    );
  }

  private contactHopHitbox(): CharacterHitboxDocument {
    return this.characterPackage.character.hitboxes[this.ctx.definition.contactHop.hitboxId];
  }

  private land(time: number): void {
    this.phase = 'landing';
    this.phaseStartedAt = time;
    this.enableBodyAt(this.leapTarget);
    this.hideLandingPresentation();
    this.spawnLandingCrack(this.ctx.definition.leap.landingRadius);
    const player = this.ctx.getPlayer();
    const impact = new Phaser.Math.Vector2(player.x - this.x, player.y - this.y);
    if (impact.length() <= this.ctx.definition.leap.landingRadius) {
      if (impact.lengthSq() > 0) impact.normalize();
      this.ctx.applyPlayerDamage(
        this.ctx.definition.leap.landingDamage,
        this.ctx.definition.id,
        impact.x,
        impact.y,
        this.ctx.definition.leap.landingKnockbackStrength,
      );
    }
    this.scene.cameras.main.shake(100, 0.003);
  }

  private beginRecovery(time: number): void {
    this.phase = 'recovery';
    this.phaseStartedAt = time;
    this.setVelocity(0, 0);
  }

  private beginChase(time: number, preserveLeapDeadline = false): void {
    this.phase = 'chase';
    this.phaseStartedAt = time;
    if (!preserveLeapDeadline) this.nextLeapAt = time + this.ctx.definition.leap.cadenceMs;
  }

  private updateFrame(time: number): void {
    if (time < this.hitFlashUntil) {
      this.visual.setFrame(animationFrame(4, 5, time, 65));
      return;
    }
    const elapsed = time - this.phaseStartedAt;
    if (this.phase === 'chase' || this.phase === 'return-to-center') this.visual.setFrame(animationFrame(6, 11, time, 130));
    else if (this.phase === 'small-hop') {
      const local = elapsed % (this.ctx.definition.leap.smallHopDurationMs + this.ctx.definition.leap.betweenHopsMs);
      this.visual.setFrame(local < this.ctx.definition.leap.smallHopDurationMs
        ? 12 + Math.min(3, Math.floor(local / (this.ctx.definition.leap.smallHopDurationMs / 4)))
        : 0);
    } else if (this.phase === 'contact-hop') this.visual.setFrame(this.contactHopRunner.state.sourceFrame);
    else if (this.phase === 'airborne') this.visual.setFrame(18 + Math.min(5, Math.floor(elapsed / (this.ctx.definition.leap.airTimeMs / 6))));
    else if (this.phase === 'landing') this.visual.setFrame(24 + Math.min(3, Math.floor(elapsed / 90)));
    else if (this.phase === 'recovery') this.visual.setFrame(animationFrame(28, 29, elapsed, 180));
  }

  private syncPresentation(_deltaMs: number): void {
    let height = 0;
    if (this.phase === 'contact-hop') {
      const progress = contactHopProgress(this.scene.time.now, this.phaseStartedAt, Math.max(1, this.contactHopImpactAtMs));
      height = contactHopVisualHeight(progress);
      this.shadow.setPosition(this.contactHopAnchor.x, this.contactHopAnchor.y + 24)
        .setScale(1 - Math.sin(progress * Math.PI) * 0.25);
    } else if (this.phase === 'airborne') {
      const progress = Phaser.Math.Clamp((this.scene.time.now - this.phaseStartedAt) / this.ctx.definition.leap.airTimeMs, 0, 1);
      height = Math.sin(progress * Math.PI) * 96;
      this.shadow.setPosition(this.x, this.y + 24).setScale(1 - Math.sin(progress * Math.PI) * 0.35);
    } else if (this.phase === 'small-hop') {
      const local = (this.scene.time.now - this.phaseStartedAt) % (this.ctx.definition.leap.smallHopDurationMs + this.ctx.definition.leap.betweenHopsMs);
      if (local < this.ctx.definition.leap.smallHopDurationMs) height = Math.sin(local / this.ctx.definition.leap.smallHopDurationMs * Math.PI) * 20;
    }
    this.visual.setPosition(this.x, this.y - height);
    const depth = resolveWorldDepth(this.y, { stableId: `boss:${this.ctx.definition.id}` }).depth;
    this.setDepth(depth);
    this.visual.setDepth(depth + (height > 0 ? 0.4 : 0));
    this.shadow.setDepth(depth - 0.2);
    this.landingMarker.setDepth(depth - 0.15);
  }

  private showLandingPresentation(center: Readonly<{ x: number; y: number }>, radius: number): void {
    this.shadow.setPosition(center.x, center.y + 24).setScale(1).setVisible(true);
    this.landingMarker.clear().lineStyle(3, 0xffc85a, 0.85).fillStyle(0xff7a3d, 0.15)
      .fillCircle(center.x, center.y, radius)
      .strokeCircle(center.x, center.y, radius)
      .setVisible(true);
  }

  private showContactHopPresentation(): void {
    const hitbox = this.contactHopHitbox();
    const geometry = resolveCharacterHitboxGeometry(hitbox, this.contactHopAnchor, 1);
    const centerX = 'centerX' in geometry ? geometry.centerX : geometry.x + geometry.width / 2;
    const centerY = 'centerY' in geometry ? geometry.centerY : geometry.y + geometry.height / 2;
    this.shadow.setPosition(this.contactHopAnchor.x, this.contactHopAnchor.y + 24).setScale(1).setVisible(true);
    this.landingMarker.clear().lineStyle(3, 0xffc85a, 0.85).fillStyle(0xff7a3d, 0.15);
    if (geometry.shape === 'circle') {
      this.landingMarker.fillCircle(centerX, centerY, geometry.radius).strokeCircle(centerX, centerY, geometry.radius);
    } else if (geometry.shape === 'ellipse') {
      this.landingMarker.fillEllipse(centerX, centerY, geometry.width, geometry.height).strokeEllipse(centerX, centerY, geometry.width, geometry.height);
    } else {
      this.landingMarker.fillRect(geometry.x, geometry.y, geometry.width, geometry.height).strokeRect(geometry.x, geometry.y, geometry.width, geometry.height);
    }
    this.landingMarker.setVisible(true);
  }

  private hideLandingPresentation(): void {
    this.shadow.setVisible(false).setScale(1);
    this.landingMarker.setVisible(false).clear();
  }

  private enableBodyAt(point: Readonly<{ x: number; y: number }>): void {
    const body = this.body as Phaser.Physics.Arcade.Body;
    body.enable = true;
    body.reset(point.x, point.y);
  }

  private spawnLandingCrack(radius: number): void {
    const texture = getAsset('effect.boss.ground-crack').runtime.textureKey;
    const crack = this.scene.add.sprite(this.x, this.y, texture, 0)
      .setDepth(resolveWorldDepth(this.y, { stableId: `boss-crack:${this.ctx.definition.id}` }).depth - 0.1)
      .setDisplaySize(radius * 2, radius * 2);
    this.transientEffects.add(crack);
    crack.once(Phaser.GameObjects.Events.DESTROY, () => this.transientEffects.delete(crack));
    this.scene.tweens.addCounter({
      from: 0,
      to: 4,
      duration: this.ctx.definition.leap.crackFadeMs,
      onUpdate: (tween) => crack.setFrame(Math.min(3, Math.floor(tween.getValue() ?? 0))).setAlpha(1 - tween.progress),
      onComplete: () => crack.destroy(),
    });
  }

  private defeat(): void {
    if (this.dead) return;
    this.dead = true;
    this.phase = 'dead';
    this.phaseStartedAt = this.scene.time.now;
    this.setVelocity(0, 0);
    (this.body as Phaser.Physics.Arcade.Body).enable = false;
    this.hideLandingPresentation();
    this.ctx.onDefeated(this);
  }

  override destroy(fromScene?: boolean): void {
    if (this.destroyedValue) return;
    this.destroyedValue = true;
    for (const effect of this.transientEffects) effect.destroy();
    this.transientEffects.clear();
    this.contactHopRunner.destroy();
    this.visual.destroy();
    this.shadow.destroy();
    this.landingMarker.destroy();
    super.destroy(fromScene);
  }
}
