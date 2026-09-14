import { validateDescriptorRegistry, type ScriptDescriptor } from '../../../content/scenes/propertyDescriptors';
import { Node } from '../Node';
import { ScriptNode, type ResolvedScriptMetadata, type ScriptConfigurationWarning, type ScriptServiceMap } from '../scripts/ScriptNode';
import type { NodeConstructionContext, NodeFactory } from './NodeTypeRegistry';

export interface ScriptRegistration {
  readonly descriptor: ScriptDescriptor;
  readonly factory: NodeFactory;
  readonly configurationWarnings?: readonly ScriptConfigurationWarning[];
}

export class ScriptRegistry {
  private readonly registrations = new Map<string, ScriptRegistration>();

  constructor(private readonly services: ScriptServiceMap = {}) {}

  register(scriptId: string, factory: NodeFactory): this {
    return this.registerDefinition({ descriptor: { scriptId, displayName: scriptId, sourcePath: '', properties: [] }, factory });
  }

  registerDefinition(registration: ScriptRegistration): this {
    const { scriptId } = registration.descriptor;
    if (this.registrations.has(scriptId)) throw new Error(`Script '${scriptId}' is already registered`);
    this.registrations.set(scriptId, registration);
    return this;
  }

  has(scriptId: string): boolean { return this.registrations.has(scriptId); }

  descriptors(): readonly ScriptDescriptor[] { return [...this.registrations.values()].map(({ descriptor }) => descriptor); }

  validate(): void {
    const issues = validateDescriptorRegistry({ nodeTypes: new Map(), scripts: new Map(this.descriptors().map((entry) => [entry.scriptId, entry])) });
    if (issues.length > 0) throw new Error(`Invalid script registry: ${issues.map((issue) => `${issue.path}: ${issue.message}`).join('; ')}`);
  }

  metadata(scriptId: string): ResolvedScriptMetadata {
    const chain: ScriptRegistration[] = [];
    const visited = new Set<string>();
    let currentId: string | undefined = scriptId;
    while (currentId) {
      if (visited.has(currentId)) throw new Error(`Script inheritance cycle at '${currentId}'`);
      visited.add(currentId);
      const registration = this.registrations.get(currentId);
      if (!registration) throw new Error(`Unknown script '${currentId}' in inheritance chain for '${scriptId}'`);
      chain.unshift(registration);
      currentId = registration.descriptor.extends;
    }
    const leaf = chain.at(-1)?.descriptor;
    if (!leaf) throw new Error(`No runtime constructor is registered for script '${scriptId}'`);
    const properties = new Map();
    const capabilities = new Set<string>();
    const exclusiveCapabilities = new Set<string>();
    const signals = new Map();
    const handlers = new Map();
    const references = new Map();
    for (const { descriptor } of chain) {
      for (const property of descriptor.properties) {
        const inherited = properties.get(property.key);
        if (inherited && inherited.value.kind !== property.value.kind) throw new Error(`Script '${scriptId}' cannot change inherited property '${property.key}' type`);
        properties.set(property.key, property);
      }
      for (const capability of descriptor.capabilities ?? []) capabilities.add(capability);
      for (const capability of descriptor.exclusiveCapabilities ?? []) exclusiveCapabilities.add(capability);
      for (const signal of descriptor.signals ?? []) {
        if (signals.has(signal.id)) throw new Error(`Script '${scriptId}' duplicates inherited signal '${signal.id}'`);
        signals.set(signal.id, signal);
      }
      for (const handler of descriptor.handlers ?? []) handlers.set(handler.id, handler);
      for (const reference of descriptor.references ?? []) references.set(reference.key, reference);
    }
    return {
      ...leaf,
      capabilities: [...capabilities],
      exclusiveCapabilities: [...exclusiveCapabilities],
      properties: [...properties.values()],
      signals: [...signals.values()],
      handlers: [...handlers.values()],
      references: [...references.values()],
    };
  }

  construct(context: NodeConstructionContext): Node {
    if (!context.scriptId) throw new Error('Script construction requires scriptId');
    const registration = this.registrations.get(context.scriptId);
    if (!registration) throw new Error(`No runtime constructor is registered for script '${context.scriptId}'`);
    const metadata = this.metadata(context.scriptId);
    const node = registration.factory(context);
    if (node.runtimeId !== context.runtimeId || node.name !== context.name) throw new Error(`Script factory '${context.scriptId}' changed immutable identity`);
    node._setRuntimeDescriptorInternal(context.type, metadata.capabilities);
    if (node instanceof ScriptNode) node._configureScriptRegistration(metadata, this.services, chainWarnings(context.scriptId, this.registrations));
    return node;
  }
}

function chainWarnings(scriptId: string, registrations: ReadonlyMap<string, ScriptRegistration>): readonly ScriptConfigurationWarning[] {
  const warnings: ScriptConfigurationWarning[] = [];
  const visited = new Set<string>();
  let currentId: string | undefined = scriptId;
  while (currentId && !visited.has(currentId)) {
    visited.add(currentId);
    const registration = registrations.get(currentId);
    if (!registration) break;
    warnings.unshift(...(registration.configurationWarnings ?? []));
    currentId = registration.descriptor.extends;
  }
  return warnings;
}
