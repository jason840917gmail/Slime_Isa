import type { SceneTreeInputEvent } from '../../../runtime/scene/SceneTree';

export interface LegacyWorldHooks {
  readonly input?: (event: SceneTreeInputEvent) => void;
  readonly prePhysics?: (deltaSeconds: number) => void;
  readonly postPhysics?: (deltaSeconds: number) => void;
  readonly render?: (deltaSeconds: number) => void;
  readonly dispose?: () => void;
}

export class LegacyWorldAdapter {
  private disposed = false;

  constructor(private readonly hooks: LegacyWorldHooks = {}) {}

  input(event: SceneTreeInputEvent): void { if (!this.disposed) this.hooks.input?.(event); }
  prePhysics(deltaSeconds: number): void { if (!this.disposed) this.hooks.prePhysics?.(deltaSeconds); }
  postPhysics(deltaSeconds: number): void { if (!this.disposed) this.hooks.postPhysics?.(deltaSeconds); }
  render(deltaSeconds: number): void { if (!this.disposed) this.hooks.render?.(deltaSeconds); }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.hooks.dispose?.();
  }
}
