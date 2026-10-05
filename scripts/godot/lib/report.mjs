/**
 * Conversion report: per-scene warnings (by kind), properties that have no
 * Godot equivalent, unported scripts and undeclared script properties, plus
 * project totals. Written to `generated/conversion_report.json`.
 */
export class ConversionReport {
  constructor() {
    this.scenes = new Map();
    this.global = [];
  }

  scene(sceneId, file) {
    if (!this.scenes.has(sceneId)) {
      this.scenes.set(sceneId, {
        file,
        nodes: 0,
        instances: 0,
        connections: 0,
        warnings: [],
        dropped: {},
        unportedScripts: {},
        undeclaredScriptProperties: {},
        expectedTreeNodes: 0,
      });
    }
    return new SceneReport(this.scenes.get(sceneId));
  }

  warnGlobal(kind, message) {
    this.global.push({ kind, message });
  }

  toJSON() {
    const warningsByKind = {};
    const droppedTotals = {};
    const unported = {};
    const undeclared = {};
    let nodes = 0;
    let instances = 0;
    let connections = 0;
    const addCount = (target, key, count = 1) => { target[key] = (target[key] ?? 0) + count; };
    for (const entry of this.scenes.values()) {
      nodes += entry.nodes;
      instances += entry.instances;
      connections += entry.connections;
      for (const warning of entry.warnings) addCount(warningsByKind, warning.kind);
      for (const [key, count] of Object.entries(entry.dropped)) addCount(droppedTotals, key, count);
      for (const [key, count] of Object.entries(entry.unportedScripts)) addCount(unported, key, count);
      for (const [key, props] of Object.entries(entry.undeclaredScriptProperties)) {
        undeclared[key] = [...new Set([...(undeclared[key] ?? []), ...props])].sort();
      }
    }
    for (const warning of this.global) addCount(warningsByKind, warning.kind);
    const sortObject = (object) => Object.fromEntries(Object.entries(object).sort(([a], [b]) => a.localeCompare(b)));
    return {
      summary: {
        scenes: this.scenes.size,
        nodes,
        instances,
        connections,
        warningsByKind: sortObject(warningsByKind),
        droppedProperties: sortObject(droppedTotals),
        unportedScripts: sortObject(unported),
        undeclaredScriptProperties: sortObject(undeclared),
      },
      globalWarnings: this.global,
      scenes: Object.fromEntries([...this.scenes.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([id, entry]) => [id, compactScene(entry)])),
    };
  }
}

function compactScene(entry) {
  const result = {
    file: entry.file,
    nodes: entry.nodes,
    instances: entry.instances,
    connections: entry.connections,
    expectedTreeNodes: entry.expectedTreeNodes,
  };
  if (entry.warnings.length) result.warnings = entry.warnings;
  if (Object.keys(entry.dropped).length) result.dropped = entry.dropped;
  if (Object.keys(entry.unportedScripts).length) result.unportedScripts = entry.unportedScripts;
  if (Object.keys(entry.undeclaredScriptProperties).length) result.undeclaredScriptProperties = entry.undeclaredScriptProperties;
  return result;
}

class SceneReport {
  constructor(entry) {
    this.entry = entry;
    this.seen = new Set();
  }

  /** Records a warning once per (kind, message) in this scene. */
  warn(kind, message) {
    const key = `${kind}|${message}`;
    if (this.seen.has(key)) return;
    this.seen.add(key);
    this.entry.warnings.push({ kind, message });
  }

  /** A property with no Godot equivalent (`Type.property`). */
  dropped(type, property) {
    const key = `${type}.${property}`;
    this.entry.dropped[key] = (this.entry.dropped[key] ?? 0) + 1;
  }

  unported(scriptId) {
    this.entry.unportedScripts[scriptId] = (this.entry.unportedScripts[scriptId] ?? 0) + 1;
  }

  undeclared(scriptId, property) {
    const list = (this.entry.undeclaredScriptProperties[scriptId] ??= []);
    if (!list.includes(property)) list.push(property);
  }

  /** Nodes Godot should build for this scene, instanced subtrees included. */
  setExpectedTreeNodes(count) { this.entry.expectedTreeNodes = count; }

  countNode() { this.entry.nodes += 1; }
  countInstance() { this.entry.instances += 1; }
  countConnection() { this.entry.connections += 1; }
}
