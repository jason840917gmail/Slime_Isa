import type { SceneTree, SceneTreeInputEvent } from '../../runtime/scene/SceneTree';
import type { LegacyWorldAdapter } from './compatibility/LegacyWorldAdapter';

export const DEFAULT_FIXED_DELTA_SECONDS = 1 / 60;
export const MAX_FIXED_STEPS_PER_FRAME = 5;

export type SceneHostPhase =
  | 'physics-animation'
  | 'physics-sync'
  | 'physics-step'
  | 'physics-readback'
  | 'contacts'
  | 'attack-resolution'
  | 'post-physics'
  | 'render-animation'
  | 'presentation';

export interface SceneHostDiagnostic {
  readonly phase: SceneHostPhase | 'frame';
  readonly message: string;
  readonly error?: unknown;
}

export interface SceneHostBackend {
  startManualStepping(): void;
  advancePhysicsAnimations(deltaSeconds: number): void;
  synchronizePhysicsToBackend(): void;
  stepPhysics(deltaSeconds: number): void;
  readAuthoritativePhysicsState(): void;
  collectManagedContacts(): void;
  resolveManagedAttacks(): void;
  runPostPhysics(deltaSeconds: number): void;
  advanceRenderAnimations(deltaSeconds: number): void;
  synchronizePresentation(alpha: number): void;
  clearHeldInputTransitions(): void;
  shutdown(): void;
}

export interface PhaserSceneTreeHostOptions {
  readonly tree: SceneTree;
  readonly backend: SceneHostBackend;
  readonly legacy?: LegacyWorldAdapter;
  readonly fixedDeltaSeconds?: number;
  readonly diagnosticSink?: (diagnostic: SceneHostDiagnostic) => void;
}

interface QueuedInput {
  readonly event: SceneTreeInputEvent;
  readonly timestamp: number;
  readonly order: number;
}

export class PhaserSceneTreeHost {
  private readonly fixedDeltaSeconds: number;
  private readonly queuedInputs: QueuedInput[] = [];
  private accumulatorSeconds = 0;
  private nextInputOrder = 1;
  private stopped = false;
  private observedPaused: boolean;

  constructor(private readonly options: PhaserSceneTreeHostOptions) {
    this.fixedDeltaSeconds = options.fixedDeltaSeconds ?? DEFAULT_FIXED_DELTA_SECONDS;
    if (!Number.isFinite(this.fixedDeltaSeconds) || this.fixedDeltaSeconds <= 0) throw new Error('Fixed delta must be positive and finite');
    this.observedPaused = options.tree.paused;
    options.backend.startManualStepping();
  }

  get pendingInputCount(): number { return this.queuedInputs.length; }
  get accumulatedSeconds(): number { return this.accumulatorSeconds; }

  enqueueInput(event: SceneTreeInputEvent): void {
    this.assertRunning();
    const timestamp = event.timestamp ?? this.nextInputOrder;
    if (!Number.isFinite(timestamp)) throw new Error('Input timestamp must be finite');
    this.queuedInputs.push({ event, timestamp, order: this.nextInputOrder++ });
  }

  advanceFrame(deltaSeconds: number): number {
    this.assertRunning();
    if (!Number.isFinite(deltaSeconds) || deltaSeconds < 0) throw new Error('Frame delta must be a non-negative finite number');
    const { tree, backend, legacy } = this.options;
    try {
      if (this.observedPaused && !tree.paused) this.clearResumeState();
      this.observedPaused = tree.paused;
      tree.flushMutations();
      this.drainInput();
      let steps = 0;
      if (!tree.paused) {
        this.accumulatorSeconds += deltaSeconds;
        while (this.accumulatorSeconds + Number.EPSILON >= this.fixedDeltaSeconds && steps < MAX_FIXED_STEPS_PER_FRAME) {
          tree._deferMutations(() => {
            legacy?.prePhysics(this.fixedDeltaSeconds);
            backend.advancePhysicsAnimations(this.fixedDeltaSeconds);
            tree.physicsProcess(this.fixedDeltaSeconds);
            backend.synchronizePhysicsToBackend();
            backend.stepPhysics(this.fixedDeltaSeconds);
            backend.readAuthoritativePhysicsState();
            backend.collectManagedContacts();
            backend.resolveManagedAttacks();
            backend.runPostPhysics(this.fixedDeltaSeconds);
            legacy?.postPhysics(this.fixedDeltaSeconds);
          });
          this.accumulatorSeconds -= this.fixedDeltaSeconds;
          steps += 1;
        }
        if (this.accumulatorSeconds + Number.EPSILON >= this.fixedDeltaSeconds) {
          const retained = this.accumulatorSeconds % this.fixedDeltaSeconds;
          const dropped = this.accumulatorSeconds - retained;
          this.accumulatorSeconds = retained < 1e-12 ? 0 : retained;
          this.report('frame', `Dropped ${dropped.toFixed(6)}s of accumulated physics time after ${MAX_FIXED_STEPS_PER_FRAME} catch-up steps`);
        }
      }
      tree._deferMutations(() => {
        legacy?.render(deltaSeconds);
        backend.advanceRenderAnimations(deltaSeconds);
        tree.process(deltaSeconds);
        backend.synchronizePresentation(this.fixedDeltaSeconds === 0 ? 1 : Math.min(1, this.accumulatorSeconds / this.fixedDeltaSeconds));
      });
      return steps;
    } catch (error) {
      tree.paused = true;
      this.observedPaused = true;
      this.report('frame', error instanceof Error ? error.message : String(error), error);
      throw error;
    }
  }

  setPaused(paused: boolean): void {
    this.assertRunning();
    const wasPaused = this.options.tree.paused;
    this.options.tree.paused = paused;
    if (wasPaused && !paused) this.clearResumeState();
    this.observedPaused = paused;
  }

  shutdown(): void {
    if (this.stopped) return;
    this.stopped = true;
    this.queuedInputs.length = 0;
    const errors: unknown[] = [];
    try { this.options.tree.shutdown(); } catch (error) { errors.push(error); }
    try { this.options.legacy?.dispose(); } catch (error) { errors.push(error); }
    try { this.options.backend.shutdown(); } catch (error) { errors.push(error); }
    this.accumulatorSeconds = 0;
    if (errors.length > 0) throw new AggregateError(errors, 'Scene tree host shutdown failed');
  }

  private drainInput(): void {
    this.queuedInputs.sort((left, right) => left.timestamp - right.timestamp || left.order - right.order);
    for (const queued of this.queuedInputs.splice(0)) {
      this.options.tree.dispatchInput(queued.event);
      if (!queued.event.handled) this.options.legacy?.input(queued.event);
      this.options.tree.flushMutations();
    }
  }

  private report(phase: SceneHostDiagnostic['phase'], message: string, error?: unknown): void {
    this.options.diagnosticSink?.({ phase, message, ...(error === undefined ? {} : { error }) });
  }

  private clearResumeState(): void {
    this.accumulatorSeconds = 0;
    this.options.backend.clearHeldInputTransitions();
  }

  private assertRunning(): void { if (this.stopped) throw new Error('Scene tree host has shut down'); }
}
