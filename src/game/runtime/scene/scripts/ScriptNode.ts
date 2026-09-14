import type { ScriptDescriptor } from '../../../content/scenes/propertyDescriptors';
import type { RuntimeNodeId } from '../../../content/scenes/identifiers';
import type { JsonValue } from '../../../content/scenes/types';
import { Node, type NodeOptions } from '../Node';

export type ScriptServiceMap = Readonly<Record<string, unknown>>;
export type ScriptConfigurationWarning = (node: ScriptNode) => string | undefined;

export interface ResolvedScriptMetadata extends ScriptDescriptor {
  readonly capabilities: readonly string[];
  readonly exclusiveCapabilities: readonly string[];
  readonly properties: ScriptDescriptor['properties'];
  readonly signals: NonNullable<ScriptDescriptor['signals']>;
  readonly handlers: NonNullable<ScriptDescriptor['handlers']>;
  readonly references: NonNullable<ScriptDescriptor['references']>;
}

export interface ScriptNodeOptions extends NodeOptions {
  readonly scriptId: string;
  readonly exportedProperties?: Readonly<Record<string, JsonValue>>;
}

const unresolvedMetadata = (scriptId: string): ResolvedScriptMetadata => ({
  scriptId,
  displayName: scriptId,
  sourcePath: '',
  capabilities: [],
  exclusiveCapabilities: [],
  properties: [],
  signals: [],
  handlers: [],
  references: [],
});

export class ScriptNode extends Node {
  private readonly scriptIdentity: string;
  private metadataValue: ResolvedScriptMetadata;
  private services: ScriptServiceMap = {};
  private warningProviders: readonly ScriptConfigurationWarning[] = [];
  readonly exportedProperties: Readonly<Record<string, JsonValue>>;

  constructor(private readonly scriptOptions: ScriptNodeOptions) {
    super(scriptOptions);
    if (scriptOptions.scriptId.length === 0) throw new Error('ScriptNode requires a stable scriptId');
    this.scriptIdentity = scriptOptions.scriptId;
    this.metadataValue = unresolvedMetadata(scriptOptions.scriptId);
    this.exportedProperties = Object.freeze(structuredClone(scriptOptions.exportedProperties ?? {}));
  }

  get scriptId(): string { return this.scriptIdentity; }
  get metadata(): ResolvedScriptMetadata { return this.metadataValue; }
  get capabilities(): ReadonlySet<string> { return new Set(this.metadataValue.capabilities); }
  get sourcePath(): string { return this.metadataValue.sourcePath; }

  service<T>(serviceId: string): T {
    if (!(serviceId in this.services)) throw new Error(`Script '${this.scriptId}' requires unavailable service '${serviceId}'`);
    return this.services[serviceId] as T;
  }

  get_configuration_warnings(): readonly string[] {
    const warnings: string[] = [];
    for (const reference of this.metadataValue.references) {
      const target = this.getReference(reference.key)?.configuredTarget;
      if (reference.required && !target) warnings.push(`Required node reference '${reference.key}' is not configured`);
      if (target && reference.expectedNodeType && target.runtimeType !== reference.expectedNodeType) warnings.push(`Node reference '${reference.key}' expects ${reference.expectedNodeType}, received ${target.runtimeType}`);
      if (target && reference.expectedCapability && !target.has_runtime_capability(reference.expectedCapability)) warnings.push(`Node reference '${reference.key}' requires capability '${reference.expectedCapability}'`);
    }
    for (const provider of this.warningProviders) {
      const warning = provider(this);
      if (warning) warnings.push(warning);
    }
    return warnings;
  }

  override _enter_tree(): void {
    const exclusive = new Set(this.metadataValue.exclusiveCapabilities);
    if (exclusive.size === 0) return;
    const siblings = this.get_parent()?.get_children() ?? [];
    for (const sibling of siblings) {
      if (sibling === this || !(sibling instanceof ScriptNode)) continue;
      const conflict = sibling.metadataValue.exclusiveCapabilities.find((capability) => exclusive.has(capability));
      if (conflict) throw new Error(`Script capability '${conflict}' is exclusively owned by both '${sibling.scriptId}' and '${this.scriptId}' under '${this.get_parent()?.name ?? '<root>'}'`);
    }
  }

  /** @internal Registry-owned initialization performed before tree insertion. */
  _configureScriptRegistration(
    metadata: ResolvedScriptMetadata,
    services: ScriptServiceMap,
    warnings: readonly ScriptConfigurationWarning[],
  ): void {
    if (metadata.scriptId !== this.scriptId) throw new Error(`Script registration '${metadata.scriptId}' cannot configure '${this.scriptId}'`);
    this.metadataValue = metadata;
    this._setRuntimeDescriptorInternal('ScriptNode', metadata.capabilities);
    this.services = services;
    this.warningProviders = warnings;
  }

  protected override _duplicateSelf(runtimeId: RuntimeNodeId): ScriptNode {
    const duplicate = new ScriptNode({ ...this.scriptOptions, runtimeId, name: this.name, exportedProperties: this.exportedProperties });
    duplicate._configureScriptRegistration(this.metadataValue, this.services, this.warningProviders);
    return duplicate;
  }
}
