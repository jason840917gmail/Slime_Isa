import type Phaser from 'phaser';

import type { ResourceId } from '../../content/scenes/identifiers';
import type { SceneResourceDocument } from '../../content/scenes/types';
import type { SceneHostBackend } from './PhaserSceneTreeHost';
import { PresentationSync, type PresentationParticipant } from '../phaser-nodes/PresentationSync';

export type PhaserHostCallbackPhase =
  | 'physics-animation'
  | 'physics-sync'
  | 'physics-readback'
  | 'contacts'
  | 'attack-resolution'
  | 'post-physics'
  | 'render-animation'
  | 'clear-input';

const manualOwners = new WeakSet<object>();

export class PhaserNodeContext implements SceneHostBackend {
  private readonly presentation = new PresentationSync();
  private readonly callbacks = new Map<PhaserHostCallbackPhase, Set<(deltaSeconds: number) => void>>();
  private ownsManualStepping = false;
  private stopped = false;
  private physicsSteps = 0;

  constructor(
    readonly scene: Phaser.Scene,
    private readonly resources: ReadonlyMap<ResourceId, SceneResourceDocument> = new Map(),
  ) {}

  get managedPresentationCount(): number { return this.presentation.size; }
  get physicsStepCount(): number { return this.physicsSteps; }

  resource(resourceId: ResourceId): SceneResourceDocument {
    const resource = this.resources.get(resourceId);
    if (!resource) throw new Error(`Scene resource '${resourceId}' is not available in this Phaser context`);
    return resource;
  }

  registerPresentation(participant: PresentationParticipant): () => void {
    return this.presentation.register(participant);
  }

  registerCallback(phase: PhaserHostCallbackPhase, callback: (deltaSeconds: number) => void): () => void {
    const callbacks = this.callbacks.get(phase) ?? new Set();
    callbacks.add(callback);
    this.callbacks.set(phase, callbacks);
    let active = true;
    return () => { if (!active) return; active = false; callbacks.delete(callback); if (callbacks.size === 0) this.callbacks.delete(phase); };
  }

  startManualStepping(): void {
    this.assertRunning();
    const physics = this.scene.physics as unknown as object;
    if (manualOwners.has(physics)) throw new Error('Arcade Physics already has a managed manual-step owner');
    manualOwners.add(physics);
    this.scene.physics.disableUpdate();
    this.ownsManualStepping = true;
  }

  advancePhysicsAnimations(deltaSeconds: number): void { this.run('physics-animation', deltaSeconds); }
  synchronizePhysicsToBackend(): void { this.run('physics-sync', 0); }
  stepPhysics(deltaSeconds: number): void { this.scene.physics.world.step(deltaSeconds); this.physicsSteps += 1; }
  readAuthoritativePhysicsState(): void { this.run('physics-readback', 0); }
  collectManagedContacts(): void { this.run('contacts', 0); }
  resolveManagedAttacks(): void { this.run('attack-resolution', 0); }
  runPostPhysics(deltaSeconds: number): void { this.run('post-physics', deltaSeconds); }
  advanceRenderAnimations(deltaSeconds: number): void { this.run('render-animation', deltaSeconds); }
  synchronizePresentation(alpha: number): void { this.presentation.synchronize(alpha); }
  clearHeldInputTransitions(): void { this.run('clear-input', 0); }

  shutdown(): void {
    if (this.stopped) return;
    this.stopped = true;
    this.presentation.clear();
    this.callbacks.clear();
    if (this.ownsManualStepping) {
      const physics = this.scene.physics as typeof this.scene.physics & { readonly systems?: unknown };
      if (physics.systems) physics.enableUpdate();
      manualOwners.delete(physics as unknown as object);
      this.ownsManualStepping = false;
    }
  }

  private run(phase: PhaserHostCallbackPhase, deltaSeconds: number): void {
    for (const callback of [...(this.callbacks.get(phase) ?? [])]) callback(deltaSeconds);
  }

  private assertRunning(): void { if (this.stopped) throw new Error('Phaser node context has shut down'); }
}
