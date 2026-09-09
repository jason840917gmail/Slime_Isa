import type { BuiltNpcRegistration } from '../world/MapBuilder';
import type { NpcActor } from './NpcActor';

/** Scene-owned lifecycle boundary for authored NPC actors. */
export class NpcRuntimeController {
  private readonly actors = new Map<string, NpcActor>();
  private paused = false;
  private destroyed = false;

  register(registration: BuiltNpcRegistration): void {
    if (this.destroyed) {
      registration.actor.destroy();
      return;
    }
    const existing = this.actors.get(registration.instanceId);
    existing?.destroy();
    this.actors.set(registration.instanceId, registration.actor);
    registration.actor.setPaused(this.paused);
  }

  values(): readonly NpcActor[] {
    return [...this.actors.values()];
  }

  update(deltaMs: number): void {
    if (this.destroyed || this.paused) return;
    for (const actor of this.actors.values()) actor.update(deltaMs);
  }

  setSimulationPaused(paused: boolean): void {
    this.paused = paused;
    for (const actor of this.actors.values()) actor.setPaused(paused);
  }

  stopMoving(): void {
    for (const actor of this.actors.values()) actor.setPaused(true);
  }

  destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    for (const actor of this.actors.values()) actor.destroy();
    this.actors.clear();
  }
}
