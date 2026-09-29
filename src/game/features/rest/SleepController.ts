import type Phaser from 'phaser';

import { GAME_CONSTANTS } from '../../Constant';
import { DEPTH_BANDS } from '../../presentation/WorldDepth';

export interface WorldPoint {
  readonly x: number;
  readonly y: number;
}

export interface SleepRequest {
  /** World point where the sleeping slime is drawn (on the mattress). */
  readonly sleepPoint: WorldPoint;
  /** Walkable world point in front of the bed where the slime lies and wakes. */
  readonly wakePoint: WorldPoint;
}

export type WakeReason = 'input' | 'damage' | 'death' | 'teardown';

export interface SleepContext {
  readonly scene: Phaser.Scene;
  /** Gameplay clock in ms; stands still while the simulation is paused. */
  now(): number;
  teleportPlayer(point: WorldPoint): void;
  /** Draws the player art offset from its body without moving the body. */
  setPlayerArtOffset(offset: WorldPoint): void;
  setActionLocked(locked: boolean): void;
  stopPlayerMotion(): void;
  playAnimation(animationId: string, forceRestart: boolean): void;
  animationDurationMs(animationId: string): number | undefined;
  /** Restores HP quietly (rest healing); returns the amount actually restored. */
  heal(amount: number): number;
  isAtFullHealth(): boolean;
  /** True once when the player pressed something that should wake them. */
  consumeWakeInput(): boolean;
  /** Called once the slime is lying down (e.g. to set the respawn point). */
  onFellAsleep(request: SleepRequest): void;
  /** The doze finished and deep sleep began, or the sleeper woke up. */
  onSleepStateChanged(asleep: boolean): void;
  /** HP reached full during this sleep. */
  onRested(): void;
  showMessage(point: WorldPoint, message: string, color: 'green' | 'cyan' | 'white'): void;
}

type SleepPhase = 'dozing' | 'sleeping';

const ZZZ_INTERVAL_MS = 900;
/** Inputs pressed while lying down are ignored briefly so the F that started sleep cannot wake it. */
const WAKE_INPUT_GRACE_MS = 400;

/**
 * Sleeping in a bed: lie down, doze off, then breathe slowly while HP returns.
 * The player wakes on any gameplay input or when hurt. Sleep never pauses the
 * simulation, so the world (and healing) keeps running around the sleeper.
 */
export class SleepController {
  private phase?: SleepPhase;
  private request?: SleepRequest;
  private phaseEndsAt = 0;
  private startedAt = 0;
  private nextZzzAt = 0;
  private pendingHeal = 0;
  private announcedRested = false;
  private readonly zzz = new Set<Phaser.GameObjects.Text>();

  constructor(private readonly ctx: SleepContext) {}

  get sleeping(): boolean {
    return this.phase !== undefined;
  }

  sleep(request: SleepRequest): boolean {
    if (this.phase) return false;
    this.request = request;
    this.startedAt = this.ctx.now();
    this.pendingHeal = 0;
    this.announcedRested = false;
    this.ctx.stopPlayerMotion();
    this.ctx.setActionLocked(true);
    this.ctx.teleportPlayer(request.wakePoint);
    this.ctx.setPlayerArtOffset({
      x: request.sleepPoint.x - request.wakePoint.x,
      y: request.sleepPoint.y - request.wakePoint.y,
    });
    this.phase = 'dozing';
    this.phaseEndsAt = this.startedAt + (this.ctx.animationDurationMs('doze') ?? 0);
    this.ctx.playAnimation('doze', true);
    this.nextZzzAt = this.phaseEndsAt;
    this.ctx.onFellAsleep(request);
    return true;
  }

  update(deltaMs: number): void {
    if (!this.phase || !this.request) return;
    const now = this.ctx.now();
    // Always drain input so presses made during the grace period are discarded.
    const wakeRequested = this.ctx.consumeWakeInput();
    if (wakeRequested && now - this.startedAt >= WAKE_INPUT_GRACE_MS) {
      this.wake('input');
      return;
    }
    if (this.phase === 'dozing') {
      if (now < this.phaseEndsAt) return;
      this.phase = 'sleeping';
      this.ctx.playAnimation('sleep', true);
      this.ctx.onSleepStateChanged(true);
    }
    this.restoreHealth(deltaMs);
    if (now >= this.nextZzzAt) {
      this.nextZzzAt = now + ZZZ_INTERVAL_MS;
      this.spawnZzz(this.request.sleepPoint);
    }
  }

  wake(reason: WakeReason): void {
    if (!this.phase || !this.request) return;
    const request = this.request;
    const wasAsleep = this.phase === 'sleeping';
    this.phase = undefined;
    this.request = undefined;
    this.ctx.setPlayerArtOffset({ x: 0, y: 0 });
    if (wasAsleep) this.ctx.onSleepStateChanged(false);
    if (reason === 'teardown') return;
    this.ctx.teleportPlayer(request.wakePoint);
    this.ctx.setActionLocked(false);
    if (reason !== 'death') this.ctx.playAnimation('idle', true);
  }

  destroy(): void {
    this.wake('teardown');
    for (const text of this.zzz) text.destroy();
    this.zzz.clear();
  }

  private restoreHealth(deltaMs: number): void {
    if (this.ctx.isAtFullHealth()) {
      this.pendingHeal = 0;
      if (!this.announcedRested && this.request) {
        this.announcedRested = true;
        this.ctx.onRested();
        this.ctx.showMessage({ x: this.request.sleepPoint.x, y: this.request.sleepPoint.y - 36 }, 'Fully rested', 'green');
      }
      return;
    }
    this.pendingHeal += (GAME_CONSTANTS.rest.sleepHpRegenPerSec * deltaMs) / 1000;
    const whole = Math.floor(this.pendingHeal);
    if (whole <= 0) return;
    this.pendingHeal -= whole;
    this.ctx.heal(whole);
  }

  private spawnZzz(anchor: WorldPoint): void {
    const size = 12 + Math.round(Math.random() * 6);
    const text = this.ctx.scene.add.text(anchor.x + 14, anchor.y - 24, 'z', {
      fontFamily: 'Trebuchet MS, Segoe UI Variable, sans-serif',
      fontSize: `${size}px`,
      fontStyle: 'bold',
      color: '#e7fff5',
      stroke: '#101a31',
      strokeThickness: 3,
    }).setOrigin(0.5).setDepth(DEPTH_BANDS['overhead-artwork']).setAlpha(0);
    this.zzz.add(text);
    this.ctx.scene.tweens.add({
      targets: text,
      x: text.x + 18,
      y: text.y - 38,
      alpha: { from: 0, to: 1, yoyo: true, duration: 700 },
      duration: 1400,
      ease: 'Sine.Out',
      onComplete: () => {
        this.zzz.delete(text);
        text.destroy();
      },
    });
  }
}
