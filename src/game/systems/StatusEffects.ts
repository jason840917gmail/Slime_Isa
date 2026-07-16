import { gameEvents } from '../core/EventBus';
import { gameState } from '../core/GameState';
import type { StatusKind } from '../core/types';

/**
 * Status effect instance on the player.
 * Slime-themed: burn, poison, slow, sticky (root), bouncy (knockback up),
 * frenzy (atk+speed buff).
 */
export interface ActiveStatus {
  kind: StatusKind;
  /** Remaining time in ms. */
  timeLeft: number;
  /** Damage per tick (for burn/poison). */
  dps: number;
  /** Move-speed multiplier (for slow/frenzy). */
  speedMult: number;
  /** Last tick timestamp. */
  lastTick: number;
}

const STATUS_DEFS: Record<StatusKind, Omit<ActiveStatus, 'timeLeft' | 'lastTick'>> = {
  burn: { kind: 'burn', dps: 6, speedMult: 1 },
  poison: { kind: 'poison', dps: 4, speedMult: 1 },
  slow: { kind: 'slow', dps: 0, speedMult: 0.55 },
  sticky: { kind: 'sticky', dps: 0, speedMult: 0 },
  bouncy: { kind: 'bouncy', dps: 0, speedMult: 1 },
  frenzy: { kind: 'frenzy', dps: 0, speedMult: 1.4 },
};

const DEFAULT_DURATION_MS: Record<StatusKind, number> = {
  burn: 3000,
  poison: 5000,
  slow: 2500,
  sticky: 1200,
  bouncy: 1500,
  frenzy: 4000,
};

const TICK_MS = 500;

/**
 * StatusEffectManager is a scene-owned component (created once per area scene).
 * It ticks active statuses each update, applies DoT damage, and exposes the
 * composite speed multiplier for the movement system.
 */
export class StatusEffectManager {
  private active = new Map<StatusKind, ActiveStatus>();
  private now = 0;

  apply(kind: StatusKind, durationMs?: number): void {
    const def = STATUS_DEFS[kind];
    const dur = durationMs ?? DEFAULT_DURATION_MS[kind];
    const existing = this.active.get(kind);

    if (existing) {
      existing.timeLeft = Math.max(existing.timeLeft, dur);
    } else {
      this.active.set(kind, { ...def, timeLeft: dur, lastTick: this.now });
      gameEvents.emit('status.added', { kind, stacks: 1 });
    }
  }

  remove(kind: StatusKind): void {
    if (this.active.delete(kind)) {
      gameEvents.emit('status.removed', { kind });
    }
  }

  clear(): void {
    for (const kind of Array.from(this.active.keys())) {
      this.remove(kind);
    }
  }

  has(kind: StatusKind): boolean {
    return this.active.has(kind);
  }

  /** Combined speed multiplier across all active statuses. */
  get speedMultiplier(): number {
    let mult = 1;
    for (const s of this.active.values()) {
      mult *= s.speedMult;
    }
    return mult;
  }

  get attackMultiplier(): number {
    return this.has('frenzy') ? 1.4 : 1;
  }

  isRooted(): boolean {
    return this.has('sticky');
  }

  update(time: number, delta: number): void {
    this.now = time;
    for (const [kind, s] of Array.from(this.active.entries())) {
      s.timeLeft -= delta;
      if (s.timeLeft <= 0) {
        this.remove(kind);
        continue;
      }
      if (s.dps > 0 && time - s.lastTick >= TICK_MS) {
        s.lastTick = time;
        const dmg = (s.dps * TICK_MS) / 1000;
        gameState.damage(dmg, kind);
      }
    }
  }

  destroy(): void {
    this.clear();
  }
}
