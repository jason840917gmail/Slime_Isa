/** Scroll in pixels that counts as one wheel notch (browsers report 50–120 per notch). */
export const WHEEL_NOTCH_PX = 50;

/**
 * Turns raw wheel scrolling into single steps (roadmap 4.10). Scrolling adds up
 * until it reaches one notch; after a step the wheel must stay still for
 * `quietMs` before the next one, so a trackpad swipe or a free-spinning wheel
 * moves one weapon, not several. Times are event timestamps in milliseconds.
 */
export class WheelStepper {
  private direction?: string;
  private accumulatedPx = 0;
  private quietUntilMs = Number.NEGATIVE_INFINITY;

  constructor(private readonly quietMs: () => number) {}

  /** True when this scroll completes a step in `direction`. */
  step(direction: string, deltaPx: number, timestampMs: number): boolean {
    if (timestampMs < this.quietUntilMs) {
      this.quietUntilMs = timestampMs + this.quietMs();
      this.accumulatedPx = 0;
      return false;
    }
    if (direction !== this.direction) {
      this.direction = direction;
      this.accumulatedPx = 0;
    }
    this.accumulatedPx += Math.max(0, deltaPx);
    if (this.accumulatedPx < WHEEL_NOTCH_PX) return false;
    this.accumulatedPx = 0;
    this.quietUntilMs = timestampMs + this.quietMs();
    return true;
  }

  reset(): void {
    this.direction = undefined;
    this.accumulatedPx = 0;
    this.quietUntilMs = Number.NEGATIVE_INFINITY;
  }
}
