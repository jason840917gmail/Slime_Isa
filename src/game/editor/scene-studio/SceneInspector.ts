import { capabilitiesForNode, propertiesForNode, type DescriptorRegistry, type PropertyDescriptor, type ScriptDescriptor } from '../../content/scenes/propertyDescriptors';
import type { JsonValue, SceneInstanceDocument, SceneNodeDocument, SceneOverrideDocument } from '../../content/scenes/types';

export interface InspectorProperty {
  readonly descriptor: PropertyDescriptor;
  readonly value: JsonValue | undefined;
  readonly origin: 'authored' | 'default' | 'override';
  readonly canReset: boolean;
  readonly canAnimate: boolean;
}

export interface SceneInspectorModel {
  readonly node: SceneNodeDocument;
  readonly groups: ReadonlyMap<string, readonly InspectorProperty[]>;
  readonly script?: ScriptDescriptor;
  readonly capabilities: readonly string[];
  readonly warnings: readonly string[];
}

function overrideFor(node: SceneNodeDocument, instance: SceneInstanceDocument | undefined, descriptor: PropertyDescriptor): SceneOverrideDocument | undefined {
  return instance?.overrides.find((candidate) => candidate.sourceInstancePath.length === 0 && candidate.sourceNodeId === node.id && candidate.property === descriptor.key);
}

export function sceneInspectorModel(node: SceneNodeDocument, registry: DescriptorRegistry, instance?: SceneInstanceDocument): SceneInspectorModel {
  const descriptors = propertiesForNode(node.type, node.scriptId, registry) ?? [];
  const groups = new Map<string, InspectorProperty[]>();
  for (const descriptor of descriptors) {
    const override = overrideFor(node, instance, descriptor);
    const authored = node.properties[descriptor.key];
    const value = override?.value ?? authored ?? descriptor.defaultValue;
    const origin = override ? 'override' : authored === undefined ? 'default' : 'authored';
    const group = groups.get(descriptor.group ?? 'Properties') ?? [];
    group.push({ descriptor, value, origin, canReset: origin !== 'default', canAnimate: descriptor.animation !== undefined });
    groups.set(descriptor.group ?? 'Properties', group);
  }
  const script = node.scriptId ? registry.scripts.get(node.scriptId) : undefined;
  const warnings: string[] = [];
  if (node.scriptId && !script) warnings.push(`Script '${node.scriptId}' is not registered`);
  if (script) {
    for (const reference of script.references ?? []) {
      if (reference.required && node.properties[reference.key] === undefined) warnings.push(`Required reference '${reference.label}' is not assigned`);
    }
  }
  return { node, groups, script, capabilities: [...capabilitiesForNode(node.type, node.scriptId, registry)].sort(), warnings };
}

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character] ?? character);
}

export function renderSceneInspector(model: SceneInspectorModel): string {
  const input = (property: InspectorProperty): string => {
    const descriptor = property.descriptor;
    const attributes = `data-property="${escapeHtml(descriptor.key)}" aria-describedby="help-${escapeHtml(descriptor.key)}"`;
    if (descriptor.inspector === 'checkbox') return `<input type="checkbox" ${attributes} ${property.value === true ? 'checked' : ''} />`;
    if (descriptor.inspector === 'select' && descriptor.value.kind === 'enum') return `<select ${attributes}>${descriptor.value.values.map((value) => `<option ${property.value === value ? 'selected' : ''}>${escapeHtml(value)}</option>`).join('')}</select>`;
    if (descriptor.inspector === 'json') return `<textarea ${attributes}>${escapeHtml(JSON.stringify(property.value ?? null, null, 2))}</textarea>`;
    const type = descriptor.inspector === 'number' ? 'number' : descriptor.inspector === 'color' ? 'color' : 'text';
    const constraints = descriptor.value.kind === 'number' ? `${descriptor.value.min === undefined ? '' : ` min="${descriptor.value.min}"`}${descriptor.value.max === undefined ? '' : ` max="${descriptor.value.max}"`}${descriptor.value.integer ? ' step="1"' : ''}` : '';
    const value = typeof property.value === 'string' || typeof property.value === 'number' ? property.value : JSON.stringify(property.value ?? '');
    return `<input type="${type}" ${attributes}${constraints} value="${escapeHtml(value)}" />`;
  };
  const groups = [...model.groups].map(([label, properties]) => `<fieldset><legend>${escapeHtml(label)}</legend>${properties.map((property) => `<label class="scene-property"><span>${escapeHtml(property.descriptor.label)}${property.descriptor.units ? `<small>${escapeHtml(property.descriptor.units)}</small>` : ''}</span>${input(property)}<em>${property.origin}</em>${property.descriptor.help ? `<small id="help-${escapeHtml(property.descriptor.key)}">${escapeHtml(property.descriptor.help)}</small>` : ''}</label>`).join('')}</fieldset>`).join('');
  const script = model.script ? `<section class="scene-script-card"><span>SCRIPT</span><strong>${escapeHtml(model.script.displayName)}</strong><code>${escapeHtml(model.script.scriptId)}</code><button type="button" data-open-source="${escapeHtml(model.script.sourcePath)}">Open ${escapeHtml(model.script.sourcePath)}</button></section>` : '';
  return `<aside class="scene-inspector" aria-label="Inspector"><header><span>INSPECTOR</span><h2>${escapeHtml(model.node.name)}</h2><small>${escapeHtml(model.node.type)}</small></header>${script}${groups}${model.warnings.map((warning) => `<p role="alert">${escapeHtml(warning)}</p>`).join('')}</aside>`;
}
