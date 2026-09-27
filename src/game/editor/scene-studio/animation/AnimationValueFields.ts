import type { PropertyDescriptor } from '../../../content/scenes/propertyDescriptors';
import type { JsonValue } from '../../../content/scenes/types';

/**
 * Typed value editors shared by the timeline rows, the key inspector and the
 * node inspector's keyframe section. Angles are authored in radians (the
 * runtime and Phaser use radians) but shown in degrees, like Godot.
 */

export type AnimationValueKind = 'number' | 'integer' | 'angle' | 'vector' | 'boolean' | 'enum' | 'json';

const ANGLE_PROPERTIES = new Set(['rotation', 'angleRad']);

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character] ?? character);
}

function round(value: number, digits = 2): number {
  const scale = 10 ** digits;
  return Math.round(value * scale) / scale;
}

export function animationValueKind(property: string, descriptor: PropertyDescriptor | undefined, value?: JsonValue): AnimationValueKind {
  if (ANGLE_PROPERTIES.has(property)) return 'angle';
  const kind = descriptor?.value.kind;
  if (kind === 'boolean' || typeof value === 'boolean') return 'boolean';
  if (kind === 'vector2' || (Array.isArray(value) && value.length === 2)) return 'vector';
  if (kind === 'enum') return 'enum';
  if (kind === 'number' || typeof value === 'number') return descriptor?.value.kind === 'number' && descriptor.value.integer ? 'integer' : 'number';
  return 'json';
}

/** Short human-readable value; angles in degrees. */
export function formatAnimationValue(property: string, value: JsonValue | undefined): string {
  if (value === undefined) return '—';
  if (ANGLE_PROPERTIES.has(property) && typeof value === 'number') return `${round(value * 180 / Math.PI, 1)}°`;
  if (typeof value === 'number') return String(round(value));
  if (typeof value === 'boolean') return value ? 'on' : 'off';
  if (Array.isArray(value)) return value.map((entry) => typeof entry === 'number' ? String(round(entry)) : String(entry)).join(', ');
  if (value === null) return 'null';
  if (typeof value === 'object') return '{…}';
  return String(value);
}

/**
 * Renders inputs for a value. Every input carries `data-value-part`, so
 * `readAnimationValue` can rebuild the value from the enclosing element.
 */
export function renderAnimationValueFields(kind: AnimationValueKind, value: JsonValue | undefined, options: { readonly disabled: boolean; readonly descriptor?: PropertyDescriptor; readonly label: string; readonly compact?: boolean }): string {
  const disabled = options.disabled ? 'disabled' : '';
  const label = escapeHtml(options.label);
  const compact = options.compact ? ' is-compact' : '';
  switch (kind) {
    case 'boolean':
      return `<input type="checkbox" class="anim-value-input${compact}" data-value-part="value" aria-label="${label}" ${value === true ? 'checked' : ''} ${disabled} />`;
    case 'vector': {
      const [x, y] = Array.isArray(value) ? value : [0, 0];
      return `<input type="number" step="any" class="anim-value-input${compact}" data-value-part="x" aria-label="${label} X" title="X" value="${escapeHtml(typeof x === 'number' ? round(x) : x)}" ${disabled} /><input type="number" step="any" class="anim-value-input${compact}" data-value-part="y" aria-label="${label} Y" title="Y" value="${escapeHtml(typeof y === 'number' ? round(y) : y)}" ${disabled} />`;
    }
    case 'angle':
      return `<input type="number" step="1" class="anim-value-input${compact}" data-value-part="degrees" aria-label="${label} in degrees" title="Degrees" value="${typeof value === 'number' ? round(value * 180 / Math.PI, 2) : 0}" ${disabled} /><span class="anim-unit">°</span>`;
    case 'integer':
    case 'number':
      return `<input type="number" step="${kind === 'integer' ? 1 : 'any'}" class="anim-value-input${compact}" data-value-part="value" aria-label="${label}" value="${typeof value === 'number' ? round(value, 4) : ''}" ${disabled} />`;
    case 'enum': {
      const values = options.descriptor?.value.kind === 'enum' ? options.descriptor.value.values : [];
      return `<select class="anim-value-input${compact}" data-value-part="value" aria-label="${label}" ${disabled}>${values.map((option) => `<option value="${escapeHtml(option)}" ${option === value ? 'selected' : ''}>${escapeHtml(option)}</option>`).join('')}</select>`;
    }
    default:
      return `<input type="text" class="anim-value-input${compact}" data-value-part="json" aria-label="${label} (JSON)" value="${escapeHtml(JSON.stringify(value ?? null))}" ${disabled} />`;
  }
}

/** Rebuilds a value from the fields inside `container`; throws on invalid input. */
export function readAnimationValue(container: Element, kind: AnimationValueKind): JsonValue {
  const field = (part: string): HTMLInputElement | HTMLSelectElement | null => container.querySelector(`[data-value-part="${part}"]`);
  const number = (part: string): number => {
    const input = field(part);
    const parsed = Number(input?.value);
    if (!input || input.value.trim() === '' || !Number.isFinite(parsed)) throw new Error('Enter a number');
    return parsed;
  };
  switch (kind) {
    case 'boolean': return (field('value') as HTMLInputElement | null)?.checked === true;
    case 'vector': return [number('x'), number('y')];
    case 'angle': return number('degrees') * Math.PI / 180;
    case 'integer': return Math.round(number('value'));
    case 'number': return number('value');
    case 'enum': return field('value')?.value ?? '';
    default: return JSON.parse(field('json')?.value ?? 'null') as JsonValue;
  }
}
