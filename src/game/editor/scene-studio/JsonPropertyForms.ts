import type { JsonValue } from '../../content/scenes/types';

/**
 * Friendly forms for script properties stored as JSON. Each form is declared
 * as fields over paths into the value; the inspector renders the form above a
 * locked, read-only JSON preview. Keys a form does not know are kept as-is, so
 * the advanced parts of a value stay editable through "Edit JSON".
 */

type JsonRecord = { readonly [key: string]: JsonValue };
export type JsonPath = readonly (string | number)[];

export interface FormOption {
  readonly value: string;
  readonly label: string;
}

/** Option list for a select; `strict` lists are complete, so other values are reported. */
export interface FormOptions {
  readonly options: readonly FormOption[];
  readonly strict: boolean;
}

export interface JsonFormContext {
  /** Options by source name; `parent` is the object holding the field (for dependent lists). */
  readonly options: (source: string, parent: JsonRecord) => FormOptions;
}

interface FieldBase {
  readonly key: string;
  readonly label: string;
  /** Optional fields are removed from the value when cleared. */
  readonly optional?: boolean;
  readonly help?: string;
}

export type FormField =
  | FieldBase & { readonly kind: 'number'; readonly min?: number; readonly integer?: boolean; readonly step?: number; readonly placeholder?: string }
  | FieldBase & { readonly kind: 'text'; readonly placeholder?: string }
  | FieldBase & { readonly kind: 'checkbox' }
  | FieldBase & { readonly kind: 'select'; readonly source: string }
  /** Array of objects, one row per entry. */
  | FieldBase & { readonly kind: 'rows'; readonly fields: readonly FormField[]; readonly create: () => JsonRecord; readonly addLabel: string }
  /** Array of strings picked from a list, shown as removable chips. */
  | FieldBase & { readonly kind: 'chips'; readonly source: string; readonly addLabel: string }
  /** Record of option → whole number, e.g. item → quantity. */
  | FieldBase & { readonly kind: 'counts'; readonly source: string; readonly valueLabel: string; readonly addLabel: string };

export interface JsonForm {
  /** Fields of the value's top-level object; empty for forms that are only a note. */
  readonly fields: readonly FormField[];
  /** When set, the whole value is one field (`key` is ignored), e.g. a tag list. */
  readonly whole?: FormField;
  /** `{}` means "off": a checkbox switches the fields on with these defaults. */
  readonly toggle?: { readonly label: string; readonly create: () => JsonRecord };
  readonly note?: string;
}

function isRecord(value: JsonValue | undefined): value is JsonRecord {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

// ---------------------------------------------------------------------------
// Form declarations
// ---------------------------------------------------------------------------

const damageRuleForm: JsonForm = {
  fields: [
    { kind: 'number', key: 'priority', label: 'Priority', integer: true, help: 'Higher rules win when several apply.' },
    { kind: 'number', key: 'damageMultiplier', label: 'Damage multiplier', min: 0, step: 0.05 },
  ],
  note: 'Accepted weapons, blocked tags and immunities are advanced: use Edit JSON.',
};

const FORMS: Readonly<Record<string, JsonForm>> = {
  'game.chest/initialContents': {
    fields: [],
    whole: { kind: 'counts', key: '', label: 'Items inside', source: 'items', valueLabel: 'Quantity', addLabel: '+ Add item' },
  },
  'game.world-exit/gate': {
    toggle: { label: 'Locked until the player has an item', create: () => ({ id: 'gate', requiredItemId: '', consumeOnUnlock: true, lockedMessage: 'It is locked.' }) },
    fields: [
      { kind: 'select', key: 'requiredItemId', label: 'Required item', source: 'items' },
      { kind: 'checkbox', key: 'consumeOnUnlock', label: 'Use up the item when unlocking' },
      { kind: 'text', key: 'lockedMessage', label: 'Message while locked' },
      { kind: 'text', key: 'id', label: 'Gate ID', help: 'Remembers the unlock in the save; keep it unique per world.' },
    ],
  },
  'game.resource-node/drop': {
    fields: [
      { kind: 'select', key: 'objectId', label: 'Drops', source: 'collectibles' },
      { kind: 'select', key: 'visualId', label: 'Look', source: 'objectVisuals' },
      { kind: 'number', key: 'pieces', label: 'Pieces', min: 1, integer: true },
    ],
  },
  'game.resource-node/harvestRequirement': {
    fields: [
      { kind: 'select', key: 'targetTag', label: 'Tool must harvest', source: 'resourceTags' },
      { kind: 'number', key: 'minimumTier', label: 'Minimum tool tier', min: 0, integer: true },
      { kind: 'text', key: 'failureMessage', label: 'Message when the tool is too weak', placeholder: 'Requires an Axe' },
    ],
  },
  'game.destructible/tags': {
    fields: [],
    whole: { kind: 'chips', key: '', label: 'Tags', source: 'resourceTags', addLabel: '+ Add tag' },
  },
  'game.destructible/damageRule': damageRuleForm,
  'game.enemy/damageRule': damageRuleForm,
  'game.enemy/projectile': {
    fields: [
      { kind: 'select', key: 'projectileId', label: 'Projectile', source: 'projectiles', optional: true },
      { kind: 'number', key: 'damage', label: 'Damage', min: 0 },
      { kind: 'text', key: 'assetId', label: 'Asset ID', optional: true, placeholder: 'only without a projectile' },
      { kind: 'number', key: 'stickMs', label: 'Sticks the player (ms)', min: 0, integer: true, optional: true, placeholder: 'no', help: 'Webs: the player cannot move for this long.' },
    ],
    note: 'Only ranged enemies use this. Leave it empty ({}) for melee enemies.',
  },
  'game.enemy/impactEffect': {
    fields: [
      { kind: 'select', key: 'effectId', label: 'Hit effect', source: 'effects' },
      { kind: 'number', key: 'distance', label: 'Distance from the enemy', min: 0, optional: true, placeholder: 'default' },
    ],
  },
  'game.enemy/attributes': {
    fields: [
      { kind: 'number', key: 'contactDamage', label: 'Contact damage', min: 0, optional: true },
      { kind: 'number', key: 'wanderSpeed', label: 'Wander speed', min: 0, optional: true },
      { kind: 'number', key: 'attackWindupMs', label: 'Attack wind-up (ms)', min: 0, integer: true, optional: true },
      { kind: 'number', key: 'attackRecoveryMs', label: 'Attack recovery (ms)', min: 0, integer: true, optional: true },
      { kind: 'number', key: 'knockbackStrength', label: 'Knockback dealt', min: 0, optional: true },
      { kind: 'number', key: 'knockbackResist', label: 'Knockback resist', min: 0, step: 0.05, optional: true },
      { kind: 'checkbox', key: 'isRanged', label: 'Ranged attacker', optional: true },
      { kind: 'number', key: 'projectileSpeed', label: 'Projectile speed', min: 0, optional: true },
      { kind: 'number', key: 'fleeRange', label: 'Flee range', min: 0, optional: true },
      { kind: 'select', key: 'behavior', label: 'Special behavior', source: 'enemyBehaviors', optional: true },
    ],
  },
};

const WORLD_AREA_FORMS: Readonly<Record<string, JsonForm>> = {
  'npc-wander': {
    fields: [{ kind: 'select', key: 'npcInstanceId', label: 'NPC that wanders here', source: 'npcs' }],
  },
  'enemy-spawn': {
    fields: [
      {
        kind: 'rows', key: 'enemies', label: 'Enemies (picked by weight)', addLabel: '+ Add enemy',
        create: () => ({ type: '', weight: 1, maxAlive: 1 }),
        fields: [
          { kind: 'select', key: 'type', label: 'Enemy', source: 'enemyTypes' },
          { kind: 'number', key: 'weight', label: 'Weight', min: 1, integer: true },
          { kind: 'number', key: 'maxAlive', label: 'Max alive', min: 1, integer: true, optional: true, placeholder: 'any' },
        ],
      },
      { kind: 'number', key: 'intervalMs', label: 'Spawn every (ms)', min: 1, integer: true, step: 100 },
      { kind: 'number', key: 'maxPopulation', label: 'Max population', min: 1, integer: true },
    ],
  },
  'enemy-safe-zone': { fields: [], note: 'Safe zones need no settings: only their rectangle matters.' },
};

/** The friendly form for a script property, if it has one. */
export function jsonFormFor(scriptId: string | undefined, property: string, properties: JsonRecord): JsonForm | undefined {
  if (!scriptId) return undefined;
  if (scriptId === 'game.world-area' && property === 'data') return WORLD_AREA_FORMS[String(properties.areaKind ?? '')];
  return FORMS[`${scriptId}/${property}`];
}

// ---------------------------------------------------------------------------
// Paths
// ---------------------------------------------------------------------------

function read(value: JsonValue | undefined, path: JsonPath): JsonValue | undefined {
  let current = value;
  for (const segment of path) {
    if (typeof segment === 'number') current = Array.isArray(current) ? current[segment] : undefined;
    else current = isRecord(current) ? current[segment] : undefined;
  }
  return current;
}

/** Copy of `root` with `path` set to `next` (undefined deletes an object key). */
function write(root: JsonValue | undefined, path: JsonPath, next: JsonValue | undefined): JsonValue {
  if (path.length === 0) return next ?? {};
  const [head, ...rest] = path;
  if (typeof head === 'number') {
    const list = Array.isArray(root) ? [...root] : [];
    if (next === undefined && rest.length === 0) list.splice(head, 1);
    else list[head] = write(list[head], rest, next);
    return list;
  }
  const record: Record<string, JsonValue> = isRecord(root) ? { ...root } : {};
  if (next === undefined && rest.length === 0) delete record[head];
  else record[head] = write(record[head], rest, next);
  return record;
}

/** The field a path points at, walking into rows. */
function fieldAt(form: JsonForm, path: JsonPath): FormField | undefined {
  if (form.whole) return path.length <= 1 ? form.whole : undefined;
  let fields = form.fields;
  let found: FormField | undefined;
  for (const segment of path) {
    if (typeof segment === 'number') continue;
    found = fields.find((field) => field.key === segment);
    if (!found) return undefined;
    fields = found.kind === 'rows' ? found.fields : [];
  }
  return found;
}

// ---------------------------------------------------------------------------
// Editing
// ---------------------------------------------------------------------------

export type JsonFormEdit =
  | { readonly kind: 'set'; readonly path: JsonPath; readonly raw: string | boolean }
  | { readonly kind: 'add'; readonly path: JsonPath; readonly option?: string }
  | { readonly kind: 'remove'; readonly path: JsonPath }
  | { readonly kind: 'toggle'; readonly on: boolean }
  /** Renames a key of a `counts` field, keeping its quantity. */
  | { readonly kind: 'rename'; readonly path: JsonPath; readonly to: string };

function parseNumber(field: FormField & { readonly kind: 'number' }, raw: string): number | undefined {
  if (raw.trim() === '') {
    if (field.optional) return undefined;
    throw new Error(`${field.label} is required`);
  }
  const value = Number(raw);
  if (!Number.isFinite(value)) throw new Error(`${field.label} must be a number`);
  if (field.integer && !Number.isInteger(value)) throw new Error(`${field.label} must be a whole number`);
  if (field.min !== undefined && value < field.min) throw new Error(`${field.label} must be at least ${field.min}`);
  return value;
}

/** Returns `value` with one form edit applied; throws a readable message for bad input. */
export function applyJsonFormEdit(form: JsonForm, value: JsonValue | undefined, edit: JsonFormEdit): JsonValue {
  if (edit.kind === 'toggle') return edit.on ? { ...form.toggle?.create() } : {};
  if (edit.kind === 'remove') return write(value, edit.path, undefined);
  const field = fieldAt(form, edit.path);
  if (!field) throw new Error('That field no longer exists');
  if (edit.kind === 'rename') {
    const from = edit.path[edit.path.length - 1];
    const counts = read(value, edit.path.slice(0, -1));
    if (!isRecord(counts) || typeof from !== 'string') throw new Error('That row no longer exists');
    if (edit.to !== from && counts[edit.to] !== undefined) throw new Error(`'${edit.to}' is already in the list`);
    const renamed = Object.fromEntries(Object.entries(counts).map(([key, amount]) => [key === from ? edit.to : key, amount]));
    return write(value, edit.path.slice(0, -1), renamed);
  }
  if (edit.kind === 'add') {
    const target = form.whole ? [] : edit.path;
    const current = read(value, target);
    if (field.kind === 'rows') return write(value, target, [...(Array.isArray(current) ? current : []), field.create()]);
    if (field.kind === 'chips') {
      const list = Array.isArray(current) ? current : [];
      if (!edit.option || list.includes(edit.option)) return value ?? [];
      return write(value, target, [...list, edit.option]);
    }
    if (field.kind === 'counts') {
      const counts = isRecord(current) ? current : {};
      if (!edit.option) throw new Error('Choose an item to add');
      if (counts[edit.option] !== undefined) throw new Error(`'${edit.option}' is already in the list`);
      return write(value, target, { ...counts, [edit.option]: 1 });
    }
    throw new Error(`${field.label} cannot add entries`);
  }
  const raw = edit.raw;
  let next: JsonValue | undefined;
  if (field.kind === 'number' || field.kind === 'counts') {
    const numberField = field.kind === 'number' ? field : { kind: 'number' as const, key: '', label: field.valueLabel, min: 1, integer: true };
    next = parseNumber(numberField, String(raw));
  } else if (field.kind === 'checkbox') next = raw === true ? true : field.optional ? undefined : false;
  else if (field.kind === 'text' || field.kind === 'select') next = String(raw) === '' && field.optional ? undefined : String(raw);
  else throw new Error(`${field.label} is edited with its buttons`);
  return write(value, edit.path, next);
}

// ---------------------------------------------------------------------------
// Validation (applied to hand-edited JSON before it is saved)
// ---------------------------------------------------------------------------

function fieldIssues(field: FormField, value: JsonValue | undefined, parent: JsonRecord, context: JsonFormContext, where: string): string[] {
  const label = `${where}${field.label}`;
  if (value === undefined) return field.optional || field.kind === 'rows' || field.kind === 'chips' || field.kind === 'counts' ? [] : [`${label} is missing`];
  const known = (source: string, candidate: string): string[] => {
    const { options, strict } = context.options(source, parent);
    return strict && !options.some((option) => option.value === candidate) ? [`${label}: '${candidate}' is not a known option`] : [];
  };
  switch (field.kind) {
    case 'number':
      if (typeof value !== 'number') return [`${label} must be a number`];
      if (field.integer && !Number.isInteger(value)) return [`${label} must be a whole number`];
      return field.min !== undefined && value < field.min ? [`${label} must be at least ${field.min}`] : [];
    case 'text':
      return typeof value === 'string' ? [] : [`${label} must be text`];
    case 'checkbox':
      return typeof value === 'boolean' ? [] : [`${label} must be true or false`];
    case 'select':
      return typeof value !== 'string' ? [`${label} must be text`] : value === '' ? [`${label} is not chosen`] : known(field.source, value);
    case 'chips':
      if (!Array.isArray(value)) return [`${label} must be a list`];
      return value.flatMap((entry) => typeof entry === 'string' ? known(field.source, entry) : [`${label} entries must be text`]);
    case 'counts':
      if (!isRecord(value)) return [`${label} must be an object of name: quantity`];
      return Object.entries(value).flatMap(([key, amount]) => [
        ...known(field.source, key),
        ...(typeof amount === 'number' && Number.isInteger(amount) && amount >= 1 ? [] : [`${label}: '${key}' needs a whole quantity of at least 1`]),
      ]);
    case 'rows':
      if (!Array.isArray(value)) return [`${label} must be a list`];
      return value.flatMap((entry, index) => isRecord(entry)
        ? field.fields.flatMap((child) => fieldIssues(child, entry[child.key], entry, context, `${label} #${index + 1} · `))
        : [`${label} #${index + 1} must be an object`]);
  }
}

/** Problems that stop a hand-edited value from being saved; empty when it is fine. */
export function validateJsonForm(form: JsonForm, value: JsonValue, context: JsonFormContext): readonly string[] {
  if (form.whole) return fieldIssues(form.whole, value, {}, context, '');
  if (!isRecord(value)) return ['The value must be a JSON object ({ … })'];
  if (form.toggle && Object.keys(value).length === 0) return [];
  return form.fields.flatMap((field) => fieldIssues(field, value[field.key], value, context, ''));
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character] ?? character);
}

const pathAttribute = (path: JsonPath): string => escapeHtml(JSON.stringify(path));

export function optionTags(source: FormOptions, selected: string, placeholder: string | undefined): string {
  const known = source.options.some((option) => option.value === selected);
  const options = [
    ...(placeholder !== undefined ? [{ value: '', label: placeholder }] : []),
    ...source.options,
    ...(selected && !known ? [{ value: selected, label: `${selected} (unknown)` }] : []),
  ];
  return options.map((option) => `<option value="${escapeHtml(option.value)}" ${option.value === selected ? 'selected' : ''}>${escapeHtml(option.label)}</option>`).join('');
}

function renderField(field: FormField, value: JsonValue | undefined, parent: JsonRecord, path: JsonPath, context: JsonFormContext, compact = false): string {
  const at = `data-json-path="${pathAttribute(path)}"`;
  const label = (control: string): string => `<label class="scene-json-field${field.kind === 'checkbox' ? ' is-check' : ''}"><small>${escapeHtml(field.label)}</small>${control}${field.help && !compact ? `<i>${escapeHtml(field.help)}</i>` : ''}</label>`;
  switch (field.kind) {
    case 'number': {
      const constraints = `${field.min === undefined ? '' : ` min="${field.min}"`} step="${field.step ?? (field.integer ? 1 : 'any')}"`;
      return label(`<input type="number" ${at}${constraints} value="${typeof value === 'number' ? value : ''}" placeholder="${escapeHtml(field.placeholder ?? '')}" />`);
    }
    case 'text':
      return label(`<input type="text" ${at} value="${escapeHtml(typeof value === 'string' ? value : '')}" placeholder="${escapeHtml(field.placeholder ?? '')}" />`);
    case 'checkbox':
      return label(`<input type="checkbox" ${at} ${value === true ? 'checked' : ''} />`);
    case 'select': {
      const selected = typeof value === 'string' ? value : '';
      return label(`<select ${at}>${optionTags(context.options(field.source, parent), selected, field.optional ? '(none)' : selected ? undefined : '(choose)')}</select>`);
    }
    case 'rows': {
      const rows = Array.isArray(value) ? value : [];
      const body = rows.map((entry, index) => {
        const record = isRecord(entry) ? entry : {};
        return `<div class="scene-json-row">${field.fields.map((child) => renderField(child, record[child.key], record, [...path, index, child.key], context, true)).join('')}`
          + `<button type="button" class="scene-json-remove" data-json-remove="${pathAttribute([...path, index])}" aria-label="Remove row ${index + 1}">×</button></div>`;
      }).join('');
      return `<div class="scene-json-group"><small>${escapeHtml(field.label)}</small>${body || '<p class="scene-json-empty">None yet</p>'}<button type="button" class="scene-link" data-json-add="${pathAttribute(path)}">${escapeHtml(field.addLabel)}</button></div>`;
    }
    case 'chips': {
      const list = Array.isArray(value) ? value.filter((entry): entry is string => typeof entry === 'string') : [];
      const source = context.options(field.source, parent);
      const addable = { ...source, options: source.options.filter((option) => !list.includes(option.value)) };
      const chips = list.map((entry, index) => `<span class="scene-json-chip">${escapeHtml(source.options.find((option) => option.value === entry)?.label ?? entry)}<button type="button" data-json-remove="${pathAttribute([...path, index])}" aria-label="Remove ${escapeHtml(entry)}">×</button></span>`).join('');
      return `<div class="scene-json-group"><small>${escapeHtml(field.label)}</small><div class="scene-json-chips">${chips || '<p class="scene-json-empty">No tags</p>'}</div>`
        + `<div class="scene-json-adder"><select data-json-pick>${optionTags(addable, '', 'Choose…')}</select><button type="button" class="scene-link" data-json-add="${pathAttribute(path)}">${escapeHtml(field.addLabel)}</button></div></div>`;
    }
    case 'counts': {
      const counts = isRecord(value) ? value : {};
      const source = context.options(field.source, parent);
      const rows = Object.entries(counts).map(([key, amount]) => `<div class="scene-json-row">`
        + `<label class="scene-json-field"><small>Item</small><select data-json-rename="${pathAttribute([...path, key])}">${optionTags(source, key, undefined)}</select></label>`
        + `<label class="scene-json-field"><small>${escapeHtml(field.valueLabel)}</small><input type="number" min="1" step="1" data-json-path="${pathAttribute([...path, key])}" value="${typeof amount === 'number' ? amount : ''}" /></label>`
        + `<button type="button" class="scene-json-remove" data-json-remove="${pathAttribute([...path, key])}" aria-label="Remove ${escapeHtml(key)}">×</button></div>`).join('');
      const addable = { ...source, options: source.options.filter((option) => counts[option.value] === undefined) };
      return `<div class="scene-json-group"><small>${escapeHtml(field.label)}</small>${rows || '<p class="scene-json-empty">Empty</p>'}`
        + `<div class="scene-json-adder"><select data-json-pick>${optionTags(addable, '', 'Choose…')}</select><button type="button" class="scene-link" data-json-add="${pathAttribute(path)}">${escapeHtml(field.addLabel)}</button></div></div>`;
    }
  }
}

/** The form controls for a value (without the JSON preview). */
export function renderJsonForm(form: JsonForm, value: JsonValue | undefined, context: JsonFormContext): string {
  const record = isRecord(value) ? value : {};
  const on = !form.toggle || Object.keys(record).length > 0;
  const toggle = form.toggle ? `<label class="scene-json-field is-check is-toggle"><small>${escapeHtml(form.toggle.label)}</small><input type="checkbox" data-json-toggle ${on ? 'checked' : ''} /></label>` : '';
  const fields = !on ? '' : form.whole ? renderField(form.whole, value, {}, [], context) : form.fields.map((field) => renderField(field, record[field.key], record, [field.key], context)).join('');
  const note = form.note ? `<p class="scene-json-note">${escapeHtml(form.note)}</p>` : '';
  return `${toggle}${fields}${note}`;
}
