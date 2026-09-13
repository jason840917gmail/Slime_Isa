import type { Node } from './Node';

export type SceneMutation =
  | { readonly kind: 'add'; readonly node: Node; readonly parent: Node; readonly order: number }
  | { readonly kind: 'reparent'; readonly node: Node; readonly parent: Node; readonly order: number }
  | { readonly kind: 'remove'; readonly node: Node; readonly order: number }
  | { readonly kind: 'free'; readonly node: Node; readonly order: number };

export type PendingSceneMutation = SceneMutation extends infer Mutation
  ? Mutation extends SceneMutation ? Omit<Mutation, 'order'> : never
  : never;

const precedence: Readonly<Record<SceneMutation['kind'], number>> = { add: 0, reparent: 1, remove: 2, free: 3 };

export class SceneMutationQueue {
  private pending = new Map<Node, SceneMutation>();
  private nextOrder = 1;

  get size(): number { return this.pending.size; }

  enqueue(mutation: PendingSceneMutation): void {
    const candidate = { ...mutation, order: this.nextOrder++ } as SceneMutation;
    const existing = this.pending.get(candidate.node);
    if (existing?.kind === 'remove' && candidate.kind === 'add') throw new Error(`Ambiguous same-flush remove/add for '${candidate.node.name}'; use reparent()`);
    if (!existing || precedence[candidate.kind] > precedence[existing.kind] || precedence[candidate.kind] === precedence[existing.kind]) {
      this.pending.set(candidate.node, candidate);
    }
  }

  isQueuedForFree(node: Node): boolean { return this.pending.get(node)?.kind === 'free'; }

  takeBatch(): readonly SceneMutation[] {
    const batch = [...this.pending.values()];
    this.pending = new Map();
    return batch.sort((left, right) => {
      const phase = (mutation: SceneMutation): number => mutation.kind === 'free' ? 0 : mutation.kind === 'remove' ? 1 : mutation.kind === 'reparent' ? 2 : 3;
      return phase(left) - phase(right) || left.order - right.order;
    });
  }

  clear(): readonly SceneMutation[] {
    const discarded = [...this.pending.values()];
    this.pending = new Map();
    return discarded;
  }
}
