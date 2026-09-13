import type { Node } from './Node';

export class NodeReference<T extends Node = Node> {
  private target?: T;

  constructor(target?: T, readonly required = false) {
    this.target = target;
  }

  get configuredTarget(): T | undefined { return this.target; }

  resolve(owner: Node): T | undefined {
    const target = this.target;
    if (!target || owner.lifecycleState !== 'ready' || target.lifecycleState !== 'ready' || owner.get_tree() !== target.get_tree()) return undefined;
    return target;
  }

  configure(target: T | undefined): void { this.target = target; }

  duplicate(remap: ReadonlyMap<Node, Node>): NodeReference<T> {
    const mapped = this.target ? remap.get(this.target) as T | undefined : undefined;
    return new NodeReference(mapped, this.required);
  }
}
