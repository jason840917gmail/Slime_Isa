/**
 * ScriptNode → `Node` with a GDScript port.
 *
 * Ported (`res://game/scripts/<snake_id>.gd` exists): only `@export`s that the
 * script chain declares are written, each encoded for its declared type (a
 * Node-typed export gets a NodePath plus a `node_paths` header entry so Godot
 * resolves it to the node). Undeclared properties go to the report.
 *
 * Unported: `res://game/runtime/unported_script.gd` keeps `script_id`, the raw
 * `properties` (node references as NodePath strings, scene references as
 * scene ids) and `signal_names`, which it registers as user signals so the
 * scene's connections still load.
 */
import { gd } from './tscn.mjs';
import { parseType, scriptResPath } from './gdscript.mjs';
import { relativePath } from './scene-model.mjs';
import { sceneResPath } from './inputs.mjs';

export const UNPORTED_SCRIPT = 'res://game/runtime/unported_script.gd';

/**
 * Script properties whose snake_case name risks colliding with a member or a
 * `.tscn` keyword (`metadata/…` lines are meta entries). The preferred name
 * is used when the port declares it, the plain snake_case name otherwise.
 */
const PROPERTY_RENAMES = { metadata: 'world_metadata' };

export const snakeCase = (key) => key.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();

/** Export name for a JSON key, given the script's declared exports. */
function exportName(key, exports) {
  const preferred = PROPERTY_RENAMES[key];
  if (preferred && (exports.has(preferred) || !exports.has(snakeCase(key)))) return preferred;
  return snakeCase(key);
}

const isNodeReference = (value) => value !== null && typeof value === 'object' && !Array.isArray(value)
  && typeof value.nodeId === 'string' && Object.keys(value).every((key) => key === 'nodeId' || key === 'instancePath');

const isSceneReference = (value) => value !== null && typeof value === 'object' && !Array.isArray(value)
  && typeof value.sceneId === 'string' && Object.keys(value).length === 1;

export function scriptIdOf(node) {
  return node.scriptId ?? node.properties?.scriptId;
}

/** Properties of a ScriptNode: { props, nodePaths }. */
export function convertScriptProps(ctx) {
  const scriptId = scriptIdOf(ctx.node);
  const path = scriptResPath(scriptId);
  const described = ctx.project.scripts.describe(path);
  const authored = Object.entries(ctx.props).filter(([key]) => key !== 'scriptId');
  if (!described) return convertUnported(ctx, scriptId, authored);
  const props = [['script', gd.ext('Script', path)]];
  const nodePaths = [];
  for (const [key, value] of authored) {
    const name = exportName(key, described.exports);
    const declared = described.exports.get(name);
    if (!declared) {
      ctx.report.undeclared(scriptId, name);
      ctx.warn('undeclared-script-property', `${ctx.label}: ${path} declares no @export '${name}'`);
      continue;
    }
    const encoded = encodeForType(ctx, value, declared, `${scriptId}.${name}`);
    if (encoded === undefined) continue;
    props.push([name, encoded.value]);
    if (encoded.nodePath) nodePaths.push(name);
  }
  return { props, nodePaths };
}

function convertUnported(ctx, scriptId, authored) {
  ctx.report.unported(scriptId);
  const properties = {};
  for (const [key, value] of authored) properties[key] = encodeRaw(ctx, value);
  const props = [
    ['script', gd.ext('Script', UNPORTED_SCRIPT)],
    ['script_id', scriptId],
    ['properties', properties],
  ];
  const signals = ctx.project.signalsBySource.get(scriptId);
  if (signals?.size) props.push(['signal_names', gd.packedString([...signals].sort())]);
  return { props, nodePaths: [] };
}

/** Raw JSON for unported scripts: references become path / id strings. */
function encodeRaw(ctx, value) {
  if (isNodeReference(value)) return nodeReferencePath(ctx, value);
  if (isSceneReference(value)) return value.sceneId;
  if (Array.isArray(value)) return value.map((item) => encodeGeneric(item));
  return encodeGeneric(value);
}

/** JSON value with no type information: numbers stay int when integral. */
function encodeGeneric(value) {
  if (value === null || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map(encodeGeneric);
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, encodeGeneric(item)]));
}

function nodeReferencePath(ctx, reference) {
  const target = ctx.scene.resolveReference(reference);
  return relativePath(ctx.scene.nodeSegments(ctx.node.id), target.segments);
}

/**
 * Encodes `value` for a declared export. Returns { value, nodePath? } or
 * undefined when the value cannot become that type (reported).
 */
function encodeForType(ctx, value, declared, label) {
  const { base, args } = parseType(declared.type);
  const mismatch = () => {
    ctx.warn('script-property-type-mismatch', `${ctx.label}: ${label} (${JSON.stringify(value).slice(0, 60)}) does not fit '${declared.type}'`);
    return undefined;
  };
  if (isNodeReference(value)) {
    const path = nodeReferencePath(ctx, value);
    if (base === 'NodePath') return { value: gd.nodePath(path) };
    if (base === 'String') return { value: path };
    if (ctx.project.scripts.isNodeType(declared.type)) return { value: gd.nodePath(path), nodePath: true };
    return mismatch();
  }
  if (isSceneReference(value)) {
    if (base === 'PackedScene') {
      const entry = ctx.project.sceneEntries.get(value.sceneId);
      if (!entry) return mismatch();
      return { value: gd.ext('PackedScene', sceneResPath(entry.file)) };
    }
    if (base === 'String' || base === 'StringName' || base === 'Variant') {
      return { value: base === 'StringName' ? gd.stringName(value.sceneId) : value.sceneId };
    }
    return mismatch();
  }
  const encoded = encodeTyped(value, base, args, declared);
  return encoded === undefined ? mismatch() : { value: encoded };
}

/** Typed encoding of plain JSON; undefined when it does not fit. */
function encodeTyped(value, base, args, declared) {
  switch (base) {
    case 'Variant': return encodeGeneric(value);
    case 'bool': return typeof value === 'boolean' ? value : undefined;
    case 'int':
      if (typeof value === 'number') return gd.int(value);
      if (typeof value === 'string' && declared?.enumValues?.has(value)) return declared.enumValues.get(value);
      return undefined;
    case 'float': return typeof value === 'number' ? gd.float(value) : undefined;
    case 'String': return typeof value === 'string' ? value : undefined;
    case 'StringName': return typeof value === 'string' ? gd.stringName(value) : undefined;
    case 'NodePath': return typeof value === 'string' ? gd.nodePath(value) : undefined;
    case 'Vector2': return vectorOf(value);
    case 'Vector2i': {
      const vector = vectorOf(value);
      return vector && gd.vec2i(vector.x, vector.y);
    }
    case 'Color': {
      const match = typeof value === 'string' ? /^#?([0-9a-f]{6})([0-9a-f]{2})?$/i.exec(value) : null;
      if (!match) return undefined;
      const channel = (hex, index) => parseInt(hex.slice(index, index + 2), 16) / 255;
      return gd.color(channel(match[1], 0), channel(match[1], 2), channel(match[1], 4), match[2] ? channel(match[2], 0) : 1);
    }
    case 'Array': {
      if (!Array.isArray(value)) return undefined;
      if (!args.length) return encodeGeneric(value);
      const { base: elementBase, args: elementArgs } = parseType(args[0]);
      const items = value.map((item) => encodeTyped(item, elementBase, elementArgs));
      return items.some((item) => item === undefined) ? undefined : gd.typedArray(args[0], items);
    }
    case 'Dictionary': {
      if (value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
      if (args.length !== 2) return encodeGeneric(value);
      const valueType = parseType(args[1]);
      const entries = Object.entries(value).map(([key, item]) => [key, encodeTyped(item, valueType.base, valueType.args)]);
      return entries.some(([, item]) => item === undefined) ? undefined : gd.typedDict(args[0], args[1], entries);
    }
    case 'PackedStringArray':
      return Array.isArray(value) && value.every((item) => typeof item === 'string') ? gd.packedString(value) : undefined;
    case 'PackedFloat32Array': case 'PackedFloat64Array':
      return Array.isArray(value) && value.every((item) => typeof item === 'number') ? gd.packedFloat32(value) : undefined;
    case 'PackedInt32Array': case 'PackedInt64Array':
      return Array.isArray(value) && value.every((item) => Number.isInteger(item)) ? gd.packedInt32(value) : undefined;
    case 'PackedVector2Array':
      return Array.isArray(value) && value.every((item) => vectorOf(item)) ? gd.packedVector2(value.map((item) => { const v = vectorOf(item); return [v.x, v.y]; })) : undefined;
    default:
      return undefined;
  }
}

function vectorOf(value) {
  if (Array.isArray(value) && value.length === 2 && value.every((n) => typeof n === 'number')) return gd.vec2(value[0], value[1]);
  if (value && typeof value === 'object' && typeof value.x === 'number' && typeof value.y === 'number') return gd.vec2(value.x, value.y);
  return undefined;
}

