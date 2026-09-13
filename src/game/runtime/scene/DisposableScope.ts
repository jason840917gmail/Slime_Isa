import type { Disposable, DisposeAction } from '../../shared/lifecycle/Disposable';

export class DisposableScope implements Disposable {
  private actions: DisposeAction[] = [];
  private disposed = false;

  get isDisposed(): boolean { return this.disposed; }
  get size(): number { return this.actions.length; }

  add(action: DisposeAction): DisposeAction {
    if (this.disposed) {
      action();
      return action;
    }
    this.actions.push(action);
    return action;
  }

  addDisposable<T extends Disposable>(disposable: T): T {
    this.add(() => disposable.dispose());
    return disposable;
  }

  disposeSafely(onError: (error: unknown) => void = () => undefined): void {
    if (this.disposed) return;
    this.disposed = true;
    for (let index = this.actions.length - 1; index >= 0; index -= 1) {
      try { this.actions[index](); } catch (error) { onError(error); }
    }
    this.actions = [];
  }

  dispose(): void {
    const errors: unknown[] = [];
    this.disposeSafely((error) => errors.push(error));
    if (errors.length > 0) throw new AggregateError(errors, 'One or more disposable cleanup actions failed');
  }
}
