/**
 * Godot 4 text-resource writer (`format=3`): a small value model plus the
 * serializers for `.tscn` scenes and `.tres` resources.
 *
 * Values are plain JS (string, boolean, number, array, object, null) or tagged
 * objects built with `gd.*`. Resources are symbolic: `gd.ext(type, path)` and
 * `gd.sub(type, key, props)` carry no ids; the writer assigns ids only for the
 * resources that the written properties actually reference, so callers can
 * build and compare property lists freely (instance-override diffs do).
 *
 * The formats follow what Godot 4.7.2 itself saves (checked with a probe scene):
 * `node_paths=PackedStringArray(...)` in a node header for Node-typed exports,
 * `libraries/ = SubResource(...)` on AnimationPlayer, typed collections as
 * `Array[String]([...])` / `Dictionary[String, int]({...})`.
 */

const TAG = Symbol('godot-value');

const tagged = (kind, fields) => ({ [TAG]: kind, ...fields });

export const gd = {
  /** Forces a float literal (`1.0`) where an int would change the Variant type. */
  float: (value) => tagged('float', { value }),
  int: (value) => tagged('int', { value }),
  vec2: (x, y) => tagged('Vector2', { x, y }),
  vec2i: (x, y) => tagged('Vector2i', { x, y }),
  color: (r, g, b, a = 1) => tagged('Color', { r, g, b, a }),
  rect2: (x, y, w, h) => tagged('Rect2', { x, y, w, h }),
  nodePath: (path) => tagged('NodePath', { path }),
  stringName: (value) => tagged('StringName', { value }),
  packedFloat32: (items) => tagged('PackedFloat32Array', { items }),
  packedInt32: (items) => tagged('PackedInt32Array', { items }),
  packedVector2: (points) => tagged('PackedVector2Array', { points }),
  packedString: (items) => tagged('PackedStringArray', { items }),
  packedByte: (bytes) => tagged('PackedByteArray', { bytes }),
  /** `Array[T]([...])`; `elementType` is the GDScript type name. */
  typedArray: (elementType, items) => tagged('TypedArray', { elementType, items }),
  /** `Dictionary[K, V]({...})`; `entries` is an array of [key, value]. */
  typedDict: (keyType, valueType, entries) => tagged('TypedDictionary', { keyType, valueType, entries }),
  /** A dictionary whose keys are not plain strings (e.g. StringName keys). */
  dict: (entries) => tagged('Dictionary', { entries }),
  ext: (type, path) => tagged('ExtResource', { type, path }),
  /** `key` dedupes identical sub-resources inside one file. */
  sub: (type, key, props) => tagged('SubResource', { type, key, props }),
  raw: (text) => tagged('raw', { text }),
};

const tagOf = (value) => (value !== null && typeof value === 'object' ? value[TAG] : undefined);

/** Shortest round-trip number text; integers stay integers. */
function formatNumber(value) {
  if (!Number.isFinite(value)) throw new Error(`Cannot write non-finite number ${value}`);
  if (Object.is(value, -0)) return '0';
  return String(value);
}

function formatFloat(value) {
  const text = formatNumber(value);
  return /[.e]/.test(text) ? text : `${text}.0`;
}

export function quote(text) {
  return `"${String(text)
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r')
    .replace(/\t/g, '\\t')}"`;
}

/**
 * Serializes one value. `refs` maps symbolic resources to ids (see
 * ResourceTable); it is optional for values that hold no resources.
 */
export function formatValue(value, refs) {
  if (value === null || value === undefined) return 'null';
  if (typeof value === 'boolean') return value ? 'true' : 'false';
  if (typeof value === 'number') return formatNumber(value);
  if (typeof value === 'string') return quote(value);
  if (Array.isArray(value)) return `[${value.map((item) => formatValue(item, refs)).join(', ')}]`;
  const kind = tagOf(value);
  switch (kind) {
    case undefined:
      return formatEntries(Object.entries(value).map(([key, item]) => [key, item]), refs);
    case 'float': return formatFloat(value.value);
    case 'int': return String(Math.round(value.value));
    case 'Vector2': return `Vector2(${formatNumber(value.x)}, ${formatNumber(value.y)})`;
    case 'Vector2i': return `Vector2i(${Math.round(value.x)}, ${Math.round(value.y)})`;
    case 'Color': return `Color(${[value.r, value.g, value.b, value.a].map(formatNumber).join(', ')})`;
    case 'Rect2': return `Rect2(${[value.x, value.y, value.w, value.h].map(formatNumber).join(', ')})`;
    case 'NodePath': return `NodePath(${quote(value.path)})`;
    case 'StringName': return `&${quote(value.value)}`;
    case 'PackedFloat32Array': return `PackedFloat32Array(${value.items.map(formatNumber).join(', ')})`;
    case 'PackedInt32Array': return `PackedInt32Array(${value.items.map((n) => String(Math.round(n))).join(', ')})`;
    case 'PackedVector2Array':
      return `PackedVector2Array(${value.points.flatMap(([x, y]) => [formatNumber(x), formatNumber(y)]).join(', ')})`;
    case 'PackedStringArray': return `PackedStringArray(${value.items.map(quote).join(', ')})`;
    case 'PackedByteArray': return `PackedByteArray(${value.bytes.join(', ')})`;
    case 'TypedArray':
      return `Array[${value.elementType}]([${value.items.map((item) => formatValue(item, refs)).join(', ')}])`;
    case 'TypedDictionary':
      return `Dictionary[${value.keyType}, ${value.valueType}](${formatEntries(value.entries, refs)})`;
    case 'Dictionary': return formatEntries(value.entries, refs);
    case 'ExtResource': return `ExtResource(${quote(requireRefs(refs).idOf(value))})`;
    case 'SubResource': return `SubResource(${quote(requireRefs(refs).idOf(value))})`;
    case 'raw': return value.text;
    default: throw new Error(`Unknown Godot value kind '${String(kind)}'`);
  }
}

function formatEntries(entries, refs) {
  if (entries.length === 0) return '{}';
  const lines = entries.map(([key, item]) => `${typeof key === 'string' ? quote(key) : formatValue(key, refs)}: ${formatValue(item, refs)}`);
  return `{\n${lines.join(',\n')}\n}`;
}

function requireRefs(refs) {
  if (!refs) throw new Error('A resource reference was written outside a resource table');
  return refs;
}

/** Calls `visit` for every ExtResource / SubResource inside `value`. */
function forEachResource(value, visit) {
  if (value === null || typeof value !== 'object') return;
  if (Array.isArray(value)) {
    for (const item of value) forEachResource(item, visit);
    return;
  }
  const kind = tagOf(value);
  if (kind === 'ExtResource' || kind === 'SubResource') {
    visit(value);
    return;
  }
  if (kind === 'TypedArray') return forEachResource(value.items, visit);
  if (kind === 'TypedDictionary' || kind === 'Dictionary') {
    for (const [key, item] of value.entries) {
      forEachResource(key, visit);
      forEachResource(item, visit);
    }
    return;
  }
  if (kind === undefined) for (const item of Object.values(value)) forEachResource(item, visit);
}

/**
 * Collects the resources a file references and gives them stable ids in order
 * of first use. Sub-resources are listed dependencies-first.
 */
class ResourceTable {
  constructor() {
    this.ext = new Map();
    this.sub = new Map();
    this.subOrder = [];
  }

  collect(value) {
    forEachResource(value, (resource) => {
      if (tagOf(resource) === 'ExtResource') {
        if (!this.ext.has(resource.path)) this.ext.set(resource.path, { id: String(this.ext.size + 1), resource });
        return;
      }
      const key = `${resource.type}|${resource.key}`;
      if (this.sub.has(key)) return;
      this.sub.set(key, null); // Reserve against cycles; dependencies come first.
      for (const [, item] of resource.props) this.collect(item);
      const entry = { id: `${resource.type}_${this.subOrder.length + 1}`, resource };
      this.sub.set(key, entry);
      this.subOrder.push(entry);
    });
  }

  idOf(resource) {
    if (tagOf(resource) === 'ExtResource') return this.ext.get(resource.path).id;
    const entry = this.sub.get(`${resource.type}|${resource.key}`);
    if (!entry) throw new Error(`Sub-resource '${resource.type}|${resource.key}' was not collected`);
    return entry.id;
  }

  writeHeaders(lines) {
    for (const { id, resource } of this.ext.values()) {
      lines.push(`[ext_resource type=${quote(resource.type)} path=${quote(resource.path)} id=${quote(id)}]`);
    }
    if (this.ext.size) lines.push('');
    for (const { id, resource } of this.subOrder) {
      lines.push(`[sub_resource type=${quote(resource.type)} id=${quote(id)}]`);
      for (const [key, item] of resource.props) lines.push(`${key} = ${formatValue(item, this)}`);
      lines.push('');
    }
  }
}

/**
 * A `.tscn` document. Nodes must be added parents-first, as Godot reads them.
 * node: { name, type?, parent?, instance?, props: [[key, value]], nodePaths?: string[] }
 */
export class TscnScene {
  constructor() {
    this.nodes = [];
    this.connections = [];
    this.editable = [];
  }

  addNode(node) {
    const keys = new Set();
    for (const [key] of node.props) {
      if (keys.has(key)) throw new Error(`Node '${node.name}' sets '${key}' twice`);
      keys.add(key);
    }
    this.nodes.push(node);
  }

  addConnection(connection) {
    this.connections.push(connection);
  }

  addEditable(path) {
    if (!this.editable.includes(path)) this.editable.push(path);
  }

  toString() {
    const table = new ResourceTable();
    for (const node of this.nodes) {
      if (node.instance) table.collect(node.instance);
      for (const [, value] of node.props) table.collect(value);
    }
    const lines = ['[gd_scene format=3]', ''];
    table.writeHeaders(lines);
    for (const node of this.nodes) {
      let header = `[node name=${quote(node.name)}`;
      if (node.type) header += ` type=${quote(node.type)}`;
      if (node.parent !== undefined) header += ` parent=${quote(node.parent)}`;
      if (node.nodePaths?.length) header += ` node_paths=${formatValue(gd.packedString(node.nodePaths))}`;
      if (node.instance) header += ` instance=${formatValue(node.instance, table)}`;
      lines.push(`${header}]`);
      for (const [key, value] of node.props) lines.push(`${key} = ${formatValue(value, table)}`);
      lines.push('');
    }
    for (const connection of this.connections) {
      lines.push(`[connection signal=${quote(connection.signal)} from=${quote(connection.from)} to=${quote(connection.to)} method=${quote(connection.method)}]`);
    }
    if (this.connections.length) lines.push('');
    for (const path of this.editable) lines.push(`[editable path=${quote(path)}]`);
    if (this.editable.length) lines.push('');
    return `${lines.join('\n').trimEnd()}\n`;
  }
}

/** A `.tres` document whose main resource has `props`. */
export function writeTres(type, props) {
  const table = new ResourceTable();
  for (const [, value] of props) table.collect(value);
  const lines = [`[gd_resource type=${quote(type)} format=3]`, ''];
  table.writeHeaders(lines);
  lines.push('[resource]');
  for (const [key, value] of props) lines.push(`${key} = ${formatValue(value, table)}`);
  return `${lines.join('\n')}\n`;
}

/** Stable text of a value for equality checks (resources by identity key). */
export function valueKey(value) {
  return formatValue(value, {
    idOf: (resource) => (tagOf(resource) === 'ExtResource' ? `ext:${resource.path}` : `sub:${resource.type}|${resource.key}`),
  });
}
