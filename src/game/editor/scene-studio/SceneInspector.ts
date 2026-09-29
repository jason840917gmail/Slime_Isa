import { capabilitiesForNode, propertiesForNode, type DescriptorRegistry, type PropertyDescriptor, type ScriptDescriptor } from '../../content/scenes/propertyDescriptors';
import type { JsonValue, SceneInstanceDocument, SceneNodeDocument, SceneOverrideDocument } from '../../content/scenes/types';
import { optionTags, type FormOptions } from './JsonPropertyForms';

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

export interface SceneInspectorRenderOptions {
  /** Replaces a JSON property's textarea (e.g. with a friendly form and a locked preview). */
  readonly jsonControl?: (property: InspectorProperty) => string | undefined;
  /** Resolves a string property's `optionSource` (e.g. 'effects') into dropdown options. */
  readonly selectOptions?: (source: string) => FormOptions;
  /**
   * Makes the header title an editable name field (committed on change). `name`
   * replaces the node's own name, e.g. with an instance's name.
   */
  readonly rename?: { readonly name: string; readonly label: string };
}

export function renderSceneInspector(model: SceneInspectorModel, options: SceneInspectorRenderOptions = {}): string {
  const input = (property: InspectorProperty): string => {
    const descriptor = property.descriptor;
    const attributes = `data-property="${escapeHtml(descriptor.key)}" aria-describedby="help-${escapeHtml(descriptor.key)}"`;
    if (descriptor.inspector === 'checkbox') return `<input type="checkbox" ${attributes} ${property.value === true ? 'checked' : ''} />`;
    if (descriptor.inspector === 'select' && descriptor.value.kind === 'enum') return `<select ${attributes}>${descriptor.value.values.map((value) => `<option ${property.value === value ? 'selected' : ''}>${escapeHtml(value)}</option>`).join('')}</select>`;
    if (descriptor.inspector === 'select' && descriptor.value.kind === 'string' && descriptor.value.optionSource && options.selectOptions) {
      return `<select ${attributes}>${optionTags(options.selectOptions(descriptor.value.optionSource), typeof property.value === 'string' ? property.value : '', '(none)')}</select>`;
    }
    if (descriptor.inspector === 'json') return `<textarea ${attributes}>${escapeHtml(JSON.stringify(property.value ?? null, null, 2))}</textarea>`;
    const type = descriptor.inspector === 'number' ? 'number' : descriptor.inspector === 'color' ? 'color' : 'text';
    const constraints = descriptor.value.kind === 'number' ? `${descriptor.value.min === undefined ? '' : ` min="${descriptor.value.min}"`}${descriptor.value.max === undefined ? '' : ` max="${descriptor.value.max}"`}${descriptor.value.integer ? ' step="1"' : ''}` : '';
    const value = typeof property.value === 'string' || typeof property.value === 'number' ? property.value : property.value === undefined ? '' : JSON.stringify(property.value);
    return `<input type="${type}" ${attributes}${constraints} value="${escapeHtml(value)}" />`;
  };
  const jsonProperty = (property: InspectorProperty): string | undefined => {
    const control = property.descriptor.inspector === 'json' ? options.jsonControl?.(property) : undefined;
    if (control === undefined) return undefined;
    const key = escapeHtml(property.descriptor.key);
    return `<div class="scene-property scene-json-property" role="group" aria-labelledby="json-${key}"><span id="json-${key}">${escapeHtml(property.descriptor.label)}</span><em>${property.origin}</em>${control}</div>`;
  };
  const groups = [...model.groups].map(([label, properties]) => `<fieldset><legend>${escapeHtml(label)}</legend>${properties.map((property) => property.descriptor.inspector === 'source-rect' ? renderSourceRect(property) : jsonProperty(property) ?? `<label class="scene-property"><span>${escapeHtml(property.descriptor.label)}${property.descriptor.units ? `<small>${escapeHtml(property.descriptor.units)}</small>` : ''}</span>${input(property)}<em>${property.origin}</em>${property.descriptor.help ? `<small id="help-${escapeHtml(property.descriptor.key)}">${escapeHtml(property.descriptor.help)}</small>` : ''}</label>`).join('')}</fieldset>`).join('');
  const script = model.script ? `<section class="scene-script-card"><span>SCRIPT</span><strong>${escapeHtml(model.script.displayName)}</strong><code>${escapeHtml(model.script.scriptId)}</code><button type="button" data-open-source="${escapeHtml(model.script.sourcePath)}">Open ${escapeHtml(model.script.sourcePath)}</button></section>` : '';
  const title = options.rename
    ? `<h2><input type="text" class="scene-name-field" data-node-name value="${escapeHtml(options.rename.name)}" aria-label="${escapeHtml(options.rename.label)}" title="${escapeHtml(options.rename.label)} (F2)" spellcheck="false" autocomplete="off" /></h2>`
    : `<h2>${escapeHtml(model.node.name)}</h2>`;
  return `<aside class="scene-inspector" aria-label="Inspector"><header><span>INSPECTOR</span>${title}<small>${escapeHtml(model.node.type)}</small></header>${script}${groups}${model.warnings.map((warning) => `<p role="alert">${escapeHtml(warning)}</p>`).join('')}</aside>`;
}

/** Guide colours shared with the in-game dev tools overlay (dev/WorldDebugRenderer.ts). */
const SOURCE_RECT_TONES: Readonly<Record<string, string>> = { occlusionBounds: 'occlusion', depthBounds: 'depth' };

/** Enable toggle plus X/Y/W/H pixel fields for a source-frame rectangle such as occlusion or depth bounds. */
function renderSourceRect(property: InspectorProperty): string {
  const key = property.descriptor.key;
  const value = property.value !== null && typeof property.value === 'object' && !Array.isArray(property.value) ? property.value as Readonly<Record<string, JsonValue>> : {};
  const enabled = ['offsetX', 'offsetY', 'width', 'height'].every((field) => typeof value[field] === 'number');
  const field = (name: string, label: string, min?: number): string => `<label><small>${label}</small><input type="number" step="1"${min === undefined ? '' : ` min="${min}"`} data-property="${escapeHtml(key)}" data-rect-field="${name}" value="${enabled ? escapeHtml(value[name]) : ''}" ${enabled ? '' : 'disabled'} /></label>`;
  const sortLine = key === 'depthBounds' && enabled ? `<small class="scene-rect-note">Sort line at source Y ${Number(value.offsetY) + Number(value.height)}px</small>` : '';
  return `<div class="scene-property scene-rect-property is-${SOURCE_RECT_TONES[key] ?? 'bounds'}" data-rect-property="${escapeHtml(key)}" role="group" aria-labelledby="rect-${escapeHtml(key)}">`
    + `<span id="rect-${escapeHtml(key)}"><i class="scene-rect-swatch" aria-hidden="true"></i>${escapeHtml(property.descriptor.label)}</span>`
    + `<label class="scene-rect-toggle"><input type="checkbox" data-property="${escapeHtml(key)}" data-rect-field="enabled" ${enabled ? 'checked' : ''} />${enabled ? 'On' : 'Off'}</label><em>${property.origin}</em>`
    + `<div class="scene-rect-fields">${field('offsetX', 'X')}${field('offsetY', 'Y')}${field('width', 'W', 1)}${field('height', 'H', 1)}</div>${sortLine}`
    + (property.descriptor.help ? `<small id="help-${escapeHtml(key)}">${escapeHtml(property.descriptor.help)} Drag its handles in the viewport to edit.</small>` : '')
    + '</div>';
}
