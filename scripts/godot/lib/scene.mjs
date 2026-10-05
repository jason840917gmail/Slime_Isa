/**
 * Converts one SceneModel into a TscnScene: nodes in tree order, instances
 * with their overrides, generated children and `[connection]`s.
 *
 * Instance overrides are converted by running the instanced node's converter
 * twice (authored properties, then authored + overrides) and writing only the
 * Godot properties that differ. That keeps derived values right without
 * special cases: a `visualOffset` override becomes an `offset` that includes
 * the sprite's origin, a sprite `scale` override on a depthBounds sprite also
 * moves its sort line, and a re-anchored character's `position` override
 * gains `+ depth_anchor·scale`.
 */
import { gd, TscnScene, valueKey } from './tscn.mjs';
import { convertNode } from './nodes.mjs';
import { rootPath } from './scene-model.mjs';
import { sceneResPath } from './inputs.mjs';
import { scriptIdOf } from './script-props.mjs';

const vec = (value, fallback) => (Array.isArray(value) && value.length === 2 ? value : fallback);

/** Godot defaults of properties an override can switch back off. */
const GODOT_DEFAULTS = {
  position: gd.vec2(0, 0),
  rotation: gd.float(0),
  scale: gd.vec2(1, 1),
  offset: gd.vec2(0, 0),
  flip_h: false,
  flip_v: false,
  frame: 0,
  visible: true,
  disabled: false,
  monitoring: true,
  monitorable: true,
  self_modulate: gd.color(1, 1, 1, 1),
  z_index: 0,
  y_sort_enabled: false,
};

/** Handler ids that collide with Object methods or name audio cues. */
const HANDLER_RENAMES = { play: 'play_cue', stop: 'stop_cue', set: 'on_set' };

/** Signals Godot declares per Godot type (the ones scene JSON can connect). */
const ENGINE_SIGNALS = {
  Area2D: ['body_entered', 'body_exited', 'area_entered', 'area_exited', 'body_shape_entered', 'body_shape_exited', 'area_shape_entered', 'area_shape_exited'],
  AnimationPlayer: ['animation_finished', 'animation_started', 'animation_changed'],
  AudioStreamPlayer: ['finished'],
  AudioStreamPlayer2D: ['finished'],
  Button: ['pressed', 'toggled', 'button_down', 'button_up'],
  HSlider: ['value_changed', 'drag_ended', 'drag_started'],
  ItemList: ['item_selected', 'item_activated', 'item_clicked', 'multi_selected'],
};

/** Signals the converter's helper scripts add, per JSON node type. */
const HELPER_SIGNALS = {
  AnimationPlayer: ['animation_event'],
  ItemList: ['item_secondary', 'item_dropped'],
  ModalRoot: ['close_requested'],
};

/** Phaser signal names whose Godot equivalent has another name. */
const SIGNAL_RENAMES = { playback_finished: 'finished' };

/** Conversion context for one node (or one node inside an instanced scene). */
class NodeContext {
  constructor(project, scene, node, props, report) {
    this.project = project;
    this.scene = scene;
    this.node = node;
    this.props = props;
    this.report = report;
    this.label = `${scene.sceneId}:${node.id}`;
  }

  warn(kind, message) {
    this.report.warn(kind, message);
  }

  /** A scene-local sub-resource or a shared resource, optionally checked for kind. */
  resource(resourceId, kind) {
    const resource = this.scene.subresources.get(resourceId) ?? this.project.sharedResources.get(resourceId);
    if (!resource) {
      this.warn('resource-missing', `${this.label}: resource '${resourceId}' not found`);
      return null;
    }
    if (kind && resource.kind !== kind) {
      this.warn('resource-kind', `${this.label}: resource '${resourceId}' is ${resource.kind}, expected ${kind}`);
      return null;
    }
    return resource;
  }

  /** Pushes position / rotation / scale when they differ from Godot's defaults. */
  node2d(props, { position, rotation, ignoreRotation = false } = {}) {
    const [x, y] = position ?? vec(this.props.position, [0, 0]);
    if (x !== 0 || y !== 0) props.push(['position', gd.vec2(round(x), round(y))]);
    const angle = ignoreRotation ? (rotation ?? 0) : (rotation ?? this.props.rotation ?? 0);
    if (angle) props.push(['rotation', gd.float(angle)]);
    const [sx, sy] = vec(this.props.scale, [1, 1]);
    if (sx !== 1 || sy !== 1) props.push(['scale', gd.vec2(sx, sy)]);
  }
}

const round = (value) => Math.round(value * 1e6) / 1e6;

/** A report that keeps warnings but no counters (used while diffing overrides). */
function diffReport(report) {
  return {
    warn: (kind, message) => report.warn(kind, message),
    dropped: () => {},
    unported: () => {},
    undeclared: (scriptId, property) => report.undeclared(scriptId, property),
  };
}

/**
 * Converts one scene. Returns { text, generatedNodes } where generatedNodes
 * counts the nodes the converter added (tile collision, captions), for the
 * expected tree size the verifier checks.
 */
export function convertScene(project, scene, report) {
  const tscn = new TscnScene();
  const counter = { generated: 0 };
  emitNode(project, scene, scene.root, undefined, tscn, report, counter);
  emitConnections(project, scene, tscn, report);
  return { text: tscn.toString(), generatedNodes: counter.generated };
}

function emitNode(project, scene, node, parentPath, tscn, report, counter) {
  const ctx = new NodeContext(project, scene, node, node.properties ?? {}, report);
  const converted = convertNode(ctx);
  report.countNode();
  tscn.addNode({ name: scene.nameOf(`n:${node.id}`), type: converted.type, parent: parentPath, props: converted.props, nodePaths: converted.nodePaths });
  const ownPath = parentPath === undefined ? '.' : rootPath(scene.nodeSegments(node.id));
  for (const child of scene.children(node.id)) {
    if (child.kind === 'node') emitNode(project, scene, child.item, ownPath, tscn, report, counter);
    else emitInstance(project, scene, child.item, ownPath, tscn, report);
  }
  for (const generated of converted.children) emitGenerated(generated, ownPath, tscn, counter);
}

function emitGenerated(generated, parentPath, tscn, counter) {
  counter.generated += 1;
  tscn.addNode({ name: generated.name, type: generated.type, parent: parentPath, props: generated.props });
  const ownPath = parentPath === '.' ? generated.name : `${parentPath}/${generated.name}`;
  for (const child of generated.children ?? []) emitGenerated(child, ownPath, tscn, counter);
}

/**
 * Converted properties of `node` (from instanced `inner`) with the overrides
 * applied, minus those equal to the instanced scene's own conversion.
 */
function overrideDiff(project, inner, node, overrides, report) {
  const quiet = diffReport(report);
  const base = convertNode(new NodeContext(project, inner, node, node.properties ?? {}, quiet));
  const merged = convertNode(new NodeContext(project, inner, node, { ...(node.properties ?? {}), ...overrides }, quiet));
  const baseByKey = new Map(base.props.map(([key, value]) => [key, valueKey(value)]));
  const mergedKeys = new Set(merged.props.map(([key]) => key));
  const props = merged.props.filter(([key, value]) => baseByKey.get(key) !== valueKey(value));
  for (const [key] of base.props) {
    if (mergedKeys.has(key)) continue;
    if (Object.hasOwn(GODOT_DEFAULTS, key)) props.push([key, GODOT_DEFAULTS[key]]);
    else report.warn('override-reset-unsupported', `${inner.sceneId}:${node.id}: an override removes '${key}', which has no known Godot default`);
  }
  const nodePaths = merged.nodePaths.filter((name) => props.some(([key]) => key === name));
  return { props, nodePaths };
}

function emitInstance(project, scene, instance, parentPath, tscn, report) {
  const inner = project.sceneModel(instance.sceneId);
  const entry = project.sceneEntries.get(instance.sceneId);
  report.countInstance();
  const name = scene.nameOf(`i:${instance.instanceId}`);
  const instancePath = rootPath(scene.instanceSegments(instance.instanceId));
  const byNode = new Map();
  for (const override of instance.overrides ?? []) {
    if ((override.sourceInstancePath ?? []).length) {
      report.warn('nested-override', `${scene.sceneId}:${instance.instanceId}: override into a nested instance is not converted`);
      continue;
    }
    if (!inner.nodes.has(override.sourceNodeId)) {
      report.warn('stale-override', `${scene.sceneId}:${instance.instanceId}: override targets missing node '${override.sourceNodeId}'`);
      continue;
    }
    if (!byNode.has(override.sourceNodeId)) byNode.set(override.sourceNodeId, {});
    byNode.get(override.sourceNodeId)[override.property] = override.value;
  }
  const rootOverrides = byNode.get(inner.root.id) ?? {};
  const rootDiff = overrideDiff(project, inner, inner.root, rootOverrides, report);
  const props = [...rootDiff.props, ['metadata/instance_id', instance.instanceId]];
  if (instance.persistenceKey) props.push(['metadata/persistence_key', instance.persistenceKey]);
  tscn.addNode({
    name,
    parent: parentPath,
    instance: gd.ext('PackedScene', sceneResPath(entry.file)),
    props,
    nodePaths: rootDiff.nodePaths,
  });
  let editable = false;
  for (const [nodeId, overrides] of byNode) {
    if (nodeId === inner.root.id) continue;
    const node = inner.nodes.get(nodeId);
    const diff = overrideDiff(project, inner, node, overrides, report);
    if (!diff.props.length) continue;
    const segments = inner.nodeSegments(nodeId);
    const parent = [instancePath, ...segments.slice(0, -1)].join('/');
    tscn.addNode({ name: segments.at(-1), parent, props: diff.props, nodePaths: diff.nodePaths });
    editable = true;
  }
  if (editable) tscn.addEditable(instancePath);
}

/** Script description of a ScriptNode (null when unported). */
function scriptOf(project, node) {
  if (node.type !== 'ScriptNode') return null;
  return project.scripts.describe(project.scriptPath(scriptIdOf(node)));
}

function emitConnections(project, scene, tscn, report) {
  for (const connection of scene.doc.connections ?? []) {
    let source;
    let target;
    try {
      source = scene.resolveReference(connection.source);
      target = scene.resolveReference(connection.target);
    } catch (error) {
      report.warn('connection-unresolved', `${scene.sceneId}: ${connection.signal} → ${connection.handler}: ${error.message}`);
      continue;
    }
    const signal = SIGNAL_RENAMES[connection.signal] ?? connection.signal;
    const method = HANDLER_RENAMES[connection.handler] ?? connection.handler;
    const label = `${scene.sceneId}: ${source.node.id}.${signal} → ${target.node.id}.${method}`;
    if (!sourceDeclaresSignal(project, source.node, signal, report, label)) continue;
    checkTargetMethod(project, target.node, method, report, label);
    report.countConnection();
    tscn.addConnection({ signal, from: rootPath(source.segments), to: rootPath(target.segments), method });
  }
}

function sourceDeclaresSignal(project, node, signal, report, label) {
  if (node.type === 'ScriptNode') {
    const described = scriptOf(project, node);
    if (!described) return true; // unported_script.gd registers every connected signal by name.
    if (described.signals.has(signal)) return true;
    report.warn('missing-script-signal', `${label}: ${described.path} declares no signal '${signal}' (connection skipped)`);
    return false;
  }
  const type = project.godotTypeOf(node);
  if ((ENGINE_SIGNALS[type] ?? []).includes(signal) || (HELPER_SIGNALS[node.type] ?? []).includes(signal)) return true;
  report.warn('unknown-node-signal', `${label}: ${type} has no signal '${signal}' (connection skipped)`);
  return false;
}

function checkTargetMethod(project, node, method, report, label) {
  if (node.type !== 'ScriptNode') return;
  const described = scriptOf(project, node);
  if (!described) {
    report.warn('unported-handler', `${label}: handler on an unported script (no-op until ported)`);
    return;
  }
  if (!described.methods.has(method)) report.warn('missing-handler', `${label}: ${described.path} has no func '${method}'`);
}
