import Phaser from 'phaser';

import { getEffectDefinition } from '../../content/effects/EffectCatalog';
import type { EffectDirection } from '../../content/effects/types';
import { AnimationClock } from '../../shared/animation';
import { LayeredAnimationVisual } from '../visuals/LayeredAnimationVisual';
import { WorldEffectAdapter } from './WorldEffectAdapter';

interface EffectSlot {
  readonly adapter: WorldEffectAdapter;
  readonly clock: AnimationClock;
  readonly visual: LayeredAnimationVisual;
  timeout?: Phaser.Time.TimerEvent;
  active: boolean;
}

export interface WorldEffectSpawnRequest {
  readonly effectId: string;
  readonly direction: EffectDirection;
  readonly x: number;
  readonly y: number;
  readonly depth: number;
}

/** Scene-owned pool; confirmed effects are independent of weapon lifecycle. */
export class WorldEffectPool {
  private readonly slots: EffectSlot[] = [];
  private readonly diagnostics = new Set<string>();
  private destroyed = false;

  constructor(private readonly scene: Phaser.Scene) {
    scene.events.once(Phaser.Scenes.Events.SHUTDOWN, this.handleShutdown);
  }

  spawn(request: WorldEffectSpawnRequest): boolean {
    if (this.destroyed) return false;
    let variant;
    try { variant = getEffectDefinition(request.effectId).variants[request.direction]; }
    catch {
      this.diagnostic(request.effectId, `Missing confirmed-hit effect '${request.effectId}'`);
      return false;
    }
    let slot = this.slots.find((candidate) => !candidate.active);
    if (!slot) {
      const adapter = new WorldEffectAdapter(request.x, request.y, request.depth, variant.mirrored);
      let created: EffectSlot;
      const clock = new AnimationClock({ onComplete: () => this.release(created) });
      const visual = new LayeredAnimationVisual(this.scene, adapter, clock, variant.animation, {
        onDiagnostic: (message) => this.diagnostic(request.effectId, message),
      });
      created = { adapter, clock, visual, active: false };
      this.slots.push(created);
      slot = created;
    }
    slot.timeout?.remove();
    slot.adapter.reset(request.x, request.y, request.depth, variant.mirrored);
    slot.visual.setAnimation(variant.animation);
    slot.visual.setVisible(true);
    slot.active = true;
    slot.clock.start(variant.animation, [], true);
    const safetyMs = Math.max(100, variant.animation.durationSeconds * 1000 + 250);
    slot.timeout = this.scene.time.delayedCall(safetyMs, () => this.release(slot!));
    return true;
  }

  update(deltaMs: number): void {
    for (const slot of this.slots) if (slot.active) { slot.clock.update(deltaMs); slot.visual.updateAnchor(); }
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.scene.events.off(Phaser.Scenes.Events.SHUTDOWN, this.handleShutdown);
    for (const slot of this.slots) { slot.timeout?.remove(); slot.visual.destroy(); slot.clock.destroy(); }
    this.slots.length = 0;
  }

  private release(slot: EffectSlot): void {
    if (!slot.active) return;
    slot.active = false;
    slot.timeout?.remove();
    slot.timeout = undefined;
    slot.clock.stop();
    slot.visual.setVisible(false);
  }

  private diagnostic(effectId: string, message: string): void {
    if (!import.meta.env.DEV || this.diagnostics.has(effectId)) return;
    this.diagnostics.add(effectId);
    console.warn(message);
  }

  private readonly handleShutdown = (): void => { this.destroy(); };
}
