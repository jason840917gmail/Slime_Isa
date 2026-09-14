import type { PropertyDescriptor } from '../../content/scenes/propertyDescriptors';
import type { JsonValue } from '../../content/scenes/types';

export interface PropertyEditorContext {
  readonly nodeOptions?: readonly { readonly id: string; readonly label: string }[];
  readonly resourceOptions?: readonly { readonly id: string; readonly label: string }[];
  readonly sceneOptions?: readonly { readonly id: string; readonly label: string }[];
}

export interface PropertyEditorDefinition {
  readonly kind: PropertyDescriptor['inspector'];
  parse(raw: string | boolean, descriptor: PropertyDescriptor): JsonValue;
}

function numeric(raw: string, descriptor: PropertyDescriptor): number {
  const value = Number(raw);
  if (!Number.isFinite(value)) throw new Error(`${descriptor.label} must be a finite number`);
  if (descriptor.value.kind === 'number' && descriptor.value.integer && !Number.isInteger(value)) throw new Error(`${descriptor.label} must be an integer`);
  if (descriptor.value.kind === 'number' && descriptor.value.min !== undefined && value < descriptor.value.min) throw new Error(`${descriptor.label} must be at least ${descriptor.value.min}`);
  if (descriptor.value.kind === 'number' && descriptor.value.max !== undefined && value > descriptor.value.max) throw new Error(`${descriptor.label} must be at most ${descriptor.value.max}`);
  return value;
}

export class PropertyEditorRegistry {
  private readonly editors = new Map<PropertyDescriptor['inspector'], PropertyEditorDefinition>();

  constructor() {
    this.register({ kind: 'checkbox', parse: (raw) => Boolean(raw) });
    this.register({ kind: 'number', parse: (raw, descriptor) => numeric(String(raw), descriptor) });
    this.register({ kind: 'vector2', parse: (raw, descriptor) => {
      const values = String(raw).split(',').map((part) => numeric(part.trim(), descriptor));
      if (values.length !== 2) throw new Error(`${descriptor.label} requires x and y`);
      return values;
    } });
    this.register({ kind: 'json', parse: (raw) => JSON.parse(String(raw)) as JsonValue });
    for (const kind of ['text', 'select', 'color'] as const) this.register({ kind, parse: (raw) => String(raw) });
    this.register({ kind: 'node', parse: (raw) => ({ nodeId: String(raw) }) });
    this.register({ kind: 'resource', parse: (raw) => ({ resourceId: String(raw) }) });
    this.register({ kind: 'scene', parse: (raw) => ({ sceneId: String(raw) }) });
  }

  register(editor: PropertyEditorDefinition): this { this.editors.set(editor.kind, editor); return this; }
  get(kind: PropertyDescriptor['inspector']): PropertyEditorDefinition {
    const editor = this.editors.get(kind);
    if (!editor) throw new Error(`No property editor is registered for '${kind}'`);
    return editor;
  }
}
