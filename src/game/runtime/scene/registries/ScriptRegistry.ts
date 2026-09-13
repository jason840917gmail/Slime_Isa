import { Node } from '../Node';
import type { NodeConstructionContext, NodeFactory } from './NodeTypeRegistry';

export class ScriptRegistry {
  private readonly factories = new Map<string, NodeFactory>();

  register(scriptId: string, factory: NodeFactory): this {
    if (this.factories.has(scriptId)) throw new Error(`Script '${scriptId}' is already registered`);
    this.factories.set(scriptId, factory);
    return this;
  }

  has(scriptId: string): boolean { return this.factories.has(scriptId); }

  construct(context: NodeConstructionContext): Node {
    if (!context.scriptId) throw new Error('Script construction requires scriptId');
    const factory = this.factories.get(context.scriptId);
    if (!factory) throw new Error(`No runtime constructor is registered for script '${context.scriptId}'`);
    const node = factory(context);
    if (node.runtimeId !== context.runtimeId || node.name !== context.name) throw new Error(`Script factory '${context.scriptId}' changed immutable identity`);
    return node;
  }
}
