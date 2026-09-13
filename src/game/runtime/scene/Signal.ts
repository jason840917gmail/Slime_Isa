import type { Node } from './Node';

interface SignalConnection {
  readonly order: number;
  readonly target: Node;
  readonly handlerId: string;
  active: boolean;
}

export interface SignalConnectionHandle {
  readonly connected: boolean;
  disconnect(): void;
}

let nextConnectionOrder = 1;

export class Signal<T = void> {
  private readonly connections: SignalConnection[] = [];

  constructor(readonly owner: Node, readonly id: string) {}

  connect(target: Node, handlerId: string): SignalConnectionHandle {
    if (this.owner.is_freed() || target.is_freed()) throw new Error('Cannot connect a signal to a freed node');
    if (!target._hasSignalHandler(handlerId)) throw new Error(`Node '${target.name}' has no signal handler '${handlerId}'`);
    const connection: SignalConnection = { order: nextConnectionOrder++, target, handlerId, active: true };
    this.connections.push(connection);
    const disconnect = (): void => { connection.active = false; };
    this.owner._ownSignalDisconnect(disconnect);
    target._ownSignalDisconnect(disconnect);
    return { get connected() { return connection.active; }, disconnect };
  }

  emit(payload: T): void {
    const tree = this.owner.get_tree();
    if (!tree || !this.owner._isSignalActive()) return;
    const snapshot = this.connections.filter((connection) => connection.active).sort((left, right) => left.order - right.order);
    tree._runBoundary('signal', this.owner, () => {
      for (const connection of snapshot) {
        if (!connection.active || !this.owner._isSignalActive() || !connection.target._isSignalActive() || connection.target.get_tree() !== tree) continue;
        tree._runBoundary('signal', connection.target, () => connection.target._invokeSignalHandler(connection.handlerId, payload));
      }
    });
  }

  /** @internal */
  _connections(): readonly { readonly target: Node; readonly handlerId: string; readonly active: boolean }[] { return this.connections; }
}
