export type DisposeAction = () => void;

export interface Disposable {
  dispose(): void;
}

/**
 * Owns cleanup callbacks for a scene or feature controller.
 * Callbacks run once in reverse registration order.
 */
export class DisposableBag implements Disposable {
  private actions: DisposeAction[] = [];
  private disposed = false;

  add(action: DisposeAction): DisposeAction {
    if (this.disposed) {
      action();
      return action;
    }

    this.actions.push(action);
    return action;
  }

  addDisposable(disposable: Disposable): Disposable {
    this.add(() => disposable.dispose());
    return disposable;
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;

    for (let index = this.actions.length - 1; index >= 0; index -= 1) {
      this.actions[index]();
    }
    this.actions = [];
  }
}
