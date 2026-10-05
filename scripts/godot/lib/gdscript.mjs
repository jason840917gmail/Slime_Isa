/**
 * Reads the hand-written GDScript ports under `godot/game/` far enough to know
 * what a converted ScriptNode may set: `@export var` declarations (with their
 * declared or inferred type), `signal`s and `func`s, following the `extends`
 * chain (a path string or a `class_name`). Inherited exports matter: player,
 * enemy and npc author `body`, `visual` and `animation` that `character.gd`
 * declares.
 */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

const VARIANT_TYPES = new Set([
  'bool', 'int', 'float', 'String', 'StringName', 'NodePath', 'Vector2', 'Vector2i', 'Vector3', 'Vector3i',
  'Rect2', 'Rect2i', 'Color', 'Array', 'Dictionary', 'Variant', 'Callable', 'Signal', 'Transform2D',
  'PackedByteArray', 'PackedInt32Array', 'PackedInt64Array', 'PackedFloat32Array', 'PackedFloat64Array',
  'PackedStringArray', 'PackedVector2Array', 'PackedVector3Array', 'PackedColorArray',
]);

/** Resource classes a JSON value can never become (besides PackedScene). */
const RESOURCE_TYPES = new Set([
  'Resource', 'Texture2D', 'Texture', 'AudioStream', 'Shape2D', 'Script', 'Animation', 'AnimationLibrary',
  'Theme', 'Font', 'TileSet', 'SpriteFrames', 'Curve', 'Gradient', 'Material', 'ShaderMaterial', 'Object',
]);

/** Strips `#` comments outside string literals, keeping line structure. */
function stripComments(source) {
  return source.split(/\r?\n/).map((line) => {
    let quoteChar = null;
    for (let index = 0; index < line.length; index += 1) {
      const char = line[index];
      if (quoteChar) {
        if (char === '\\') index += 1;
        else if (char === quoteChar) quoteChar = null;
      } else if (char === '"' || char === "'") quoteChar = char;
      else if (char === '#') return line.slice(0, index);
    }
    return line;
  }).join('\n');
}

/** Type of `:= <expression>` from the literal's shape. */
function inferType(expression) {
  const text = expression.trim();
  if (/^-?\d+\.\d*(e-?\d+)?$|^-?\d+e-?\d+$/i.test(text)) return 'float';
  if (/^-?\d+$/.test(text)) return 'int';
  if (/^(true|false)$/.test(text)) return 'bool';
  if (/^["']/.test(text)) return 'String';
  if (/^&["']/.test(text)) return 'StringName';
  if (/^\^["']|^NodePath\(/.test(text)) return 'NodePath';
  const constructor = /^([A-Z]\w*)\s*[(.]/.exec(text);
  if (constructor && VARIANT_TYPES.has(constructor[1])) return constructor[1];
  if (text.startsWith('[')) return 'Array';
  if (text.startsWith('{')) return 'Dictionary';
  return 'Variant';
}

/** Splits `Array[String]` / `Dictionary[String, int]` into base and arguments. */
export function parseType(text) {
  const match = /^([A-Za-z_][\w.]*)\s*(?:\[(.*)\])?$/.exec(text.trim());
  if (!match) return { base: 'Variant', args: [] };
  const args = match[2] ? match[2].split(',').map((part) => part.trim()).filter(Boolean) : [];
  return { base: match[1], args };
}

/** Parses the annotation arguments of `@export_enum("a", "b:3")` into names → values. */
function parseEnumArgs(text) {
  const values = new Map();
  let next = 0;
  for (const match of text.matchAll(/["']([^"']*)["']/g)) {
    const [name, explicit] = match[1].split(':');
    const value = explicit === undefined ? next : Number(explicit);
    values.set(name.trim(), value);
    next = value + 1;
  }
  return values;
}

function parseScript(source) {
  const text = stripComments(source);
  const info = { extends: null, className: null, exports: new Map(), signals: new Set(), methods: new Set() };
  const extendsMatch = /^extends\s+(?:"([^"]+)"|'([^']+)'|([A-Za-z_][\w.]*))/m.exec(text);
  if (extendsMatch) info.extends = extendsMatch[1] ?? extendsMatch[2] ?? extendsMatch[3];
  const classMatch = /^class_name\s+([A-Za-z_]\w*)/m.exec(text);
  if (classMatch) info.className = classMatch[1];
  for (const match of text.matchAll(/^signal\s+([A-Za-z_]\w*)/gm)) info.signals.add(match[1]);
  for (const match of text.matchAll(/^(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(/gm)) info.methods.add(match[1]);
  // `@export…` annotations (not groups) followed, possibly after other
  // annotations and newlines, by `var name`.
  const exportPattern = /^[ \t]*@export(?!_(?:group|subgroup|category)\b)(_\w+)?(\([^)]*\))?((?:\s+@\w+(?:\([^)]*\))?)*)\s+var\s+([A-Za-z_]\w*)([^\n]*)/gm;
  for (const match of text.matchAll(exportPattern)) {
    const [, variant = '', args = '', , name, rest] = match;
    const declaration = rest.trim();
    let type = 'Variant';
    let inferred = false;
    if (declaration.startsWith(':=')) {
      type = inferType(declaration.slice(2));
      inferred = true;
    } else if (declaration.startsWith(':')) {
      type = declaration.slice(1).split(/[=:]/)[0].trim() || 'Variant';
    }
    const entry = { name, type, inferred, annotation: `@export${variant}` };
    if (variant === '_enum') entry.enumValues = parseEnumArgs(args);
    info.exports.set(name, entry);
  }
  return info;
}

const toPosix = (path) => path.split(sep).join('/');

export class ScriptIndex {
  constructor(godotRoot) {
    this.godotRoot = godotRoot;
    this.parsed = new Map();
    this.classNames = new Map();
    const gameRoot = join(godotRoot, 'game');
    if (existsSync(gameRoot)) this.scan(gameRoot);
  }

  scan(directory) {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const full = join(directory, entry.name);
      if (entry.isDirectory()) this.scan(full);
      else if (entry.name.endsWith('.gd')) {
        const resPath = `res://${toPosix(relative(this.godotRoot, full))}`;
        const info = parseScript(readFileSync(full, 'utf8'));
        this.parsed.set(resPath, info);
        if (info.className) this.classNames.set(info.className, resPath);
      }
    }
  }

  has(resPath) {
    return this.parsed.has(resPath);
  }

  /** Resolves an `extends` target of `fromPath` to a res:// path, or null for engine classes. */
  resolveExtends(fromPath, target) {
    if (!target) return null;
    if (target.startsWith('res://')) return target;
    if (/[/.]gd$/.test(target)) return `${fromPath.slice(0, fromPath.lastIndexOf('/') + 1)}${target}`;
    return this.classNames.get(target) ?? null;
  }

  /** The engine class a script chain ends in (e.g. 'Node', 'AnimationPlayer'). */
  engineBase(resPath) {
    let path = resPath;
    for (let depth = 0; depth < 32 && path; depth += 1) {
      const info = this.parsed.get(path);
      if (!info) return null;
      const next = this.resolveExtends(path, info.extends);
      if (!next) return info.extends ?? 'RefCounted';
      path = next;
    }
    return null;
  }

  /**
   * Exports, signals and methods of a script merged along its `extends`
   * chain (leaf declarations win). Null if the file does not exist.
   */
  describe(resPath) {
    if (!this.parsed.has(resPath)) return null;
    const chain = [];
    let path = resPath;
    while (path && this.parsed.has(path) && chain.length < 32 && !chain.includes(path)) {
      chain.push(path);
      path = this.resolveExtends(path, this.parsed.get(path).extends);
    }
    const merged = { path: resPath, chain, exports: new Map(), signals: new Set(), methods: new Set() };
    for (const link of [...chain].reverse()) {
      const info = this.parsed.get(link);
      for (const [name, entry] of info.exports) merged.exports.set(name, entry);
      for (const signal of info.signals) merged.signals.add(signal);
      for (const method of info.methods) merged.methods.add(method);
    }
    return merged;
  }

  /** True when `type` names a Node class (engine or a script class_name). */
  isNodeType(type) {
    const { base } = parseType(type);
    if (VARIANT_TYPES.has(base) || RESOURCE_TYPES.has(base) || base === 'PackedScene') return false;
    if (this.classNames.has(base)) {
      const engine = this.engineBase(this.classNames.get(base));
      return engine !== null && !RESOURCE_TYPES.has(engine) && engine !== 'RefCounted';
    }
    return /^[A-Z]/.test(base);
  }

  isResourceType(type) {
    return RESOURCE_TYPES.has(parseType(type).base);
  }
}

/** `game.world-area` → `res://game/scripts/world_area.gd`. */
export function scriptResPath(scriptId) {
  const id = scriptId.startsWith('game.') ? scriptId.slice('game.'.length) : scriptId;
  return `res://game/scripts/${id.replace(/[-.]/g, '_')}.gd`;
}
