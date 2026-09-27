/**
 * ComboSystem tracks consecutive attacks within a chain window. Each hit
 * increases the combo count and damage multiplier. The 3rd hit applies bonus
 * knockback. If the chain window expires, the combo resets.
 *
 * Visual feedback is delegated to callbacks so the scene can show combo
 * counters, floating text, etc.
 */

const CHAIN_WINDOW_MS = 600;
const MAX_COMBO = 3;
const DAMAGE_MULT: readonly number[] = [1.0, 1.15, 1.5];

export interface ComboCallbacks {
  onComboHit: (combo: number, damageMult: number) => void;
  onComboReset: () => void;
  onComboFinish: (combo: number) => void;
}

export class ComboSystem {
  private readonly now: () => number;
  private cb: ComboCallbacks;
  private combo = 0;
  private lastHitAt = 0;

  /** `now` is the gameplay clock the chain window is measured on. */
  constructor(now: () => number, cb: ComboCallbacks) {
    this.now = now;
    this.cb = cb;
  }

  get current(): number {
    return this.combo;
  }

  get damageMultiplier(): number {
    return DAMAGE_MULT[Math.min(this.combo, DAMAGE_MULT.length - 1)];
  }

  get isFinishingHit(): boolean {
    return this.combo >= MAX_COMBO - 1;
  }

  /** Register a hit. Returns the damage multiplier to apply. */
  registerHit(): number {
    const now = this.now();

    if (now - this.lastHitAt > CHAIN_WINDOW_MS) {
      this.combo = 0;
    }

    this.combo = Math.min(this.combo + 1, MAX_COMBO);
    this.lastHitAt = now;

    const mult = this.damageMultiplier;
    this.cb.onComboHit(this.combo, mult);

    if (this.combo >= MAX_COMBO) {
      this.cb.onComboFinish(this.combo);
      // Reset after the finishing hit.
      this.combo = 0;
    }

    return mult;
  }

  update(): void {
    if (this.combo > 0 && this.now() - this.lastHitAt > CHAIN_WINDOW_MS) {
      this.combo = 0;
      this.cb.onComboReset();
    }
  }

  reset(): void {
    this.combo = 0;
    this.lastHitAt = 0;
    this.cb.onComboReset();
  }
}

export { CHAIN_WINDOW_MS, MAX_COMBO };
