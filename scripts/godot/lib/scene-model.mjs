/**
 * One authored scene document as a tree: ordered children, Godot node names
 * and paths, node-reference resolution (including references that walk into
 * instances), the feet re-anchoring of depth sources and the y-sort policy.
 */

/** Characters Godot forbids in node names (conventions); never authored today. */
const ILLEGAL_NAME_CHARS = /[.:@/"%]/g;

const vec = (value, fallback) => (Array.isArray(value) && value.length === 2 ? value : fallback);

export class SceneModel {
  /**
   * @param entry { sceneId, file, doc }
   * @param project gives `sceneModel(sceneId)` for walking into instances.
   */
  constructor(entry, project) {
    this.sceneId = entry.sceneId;
    this.file = entry.file;
    this.doc = entry.doc;
    this.project = project;
    this.nodes = new Map(this.doc.nodes.map((node) => [node.id, node]));
    this.instances = new Map((this.doc.instances ?? []).map((instance) => [instance.instanceId, instance]));
    this.subresources = new Map((this.doc.subresources ?? []).map((resource) => [resource.resourceId, resource]));
    this.root = this.nodes.get(this.doc.rootNodeId);
    if (!this.root) throw new Error(`${this.file}: root node '${this.doc.rootNodeId}' is missing`);
    this.childLists = this.buildChildLists();
    this.names = this.buildNames();
    this.paths = new Map();
    this.buildPaths(this.root.id, []);
  }

  /** Children of every node: authored nodes and instances merged by `order`. */
  buildChildLists() {
    const lists = new Map();
    const push = (parentId, item) => {
      if (!lists.has(parentId)) lists.set(parentId, []);
      lists.get(parentId).push(item);
    };
    for (const node of this.doc.nodes) if (node.parentId !== null) push(node.parentId, { kind: 'node', key: `n:${node.id}`, item: node, order: node.order });
    for (const instance of this.instances.values()) push(instance.parentNodeId, { kind: 'instance', key: `i:${instance.instanceId}`, item: instance, order: instance.order });
    for (const list of lists.values()) list.sort((a, b) => a.order - b.order);
    return lists;
  }

  buildNames() {
    const names = new Map([[`n:${this.root.id}`, sanitizeName(this.root.name)]]);
    for (const list of this.childLists.values()) {
      const used = new Set();
      for (const child of list) {
        const base = sanitizeName(child.item.name);
        let name = base;
        for (let suffix = 2; used.has(name); suffix += 1) name = `${base}_${suffix}`;
        used.add(name);
        names.set(child.key, name);
      }
    }
    return names;
  }

  buildPaths(nodeId, segments) {
    this.paths.set(`n:${nodeId}`, segments);
    for (const child of this.children(nodeId)) {
      const childSegments = [...segments, this.names.get(child.key)];
      if (child.kind === 'node') this.buildPaths(child.item.id, childSegments);
      else this.paths.set(child.key, childSegments);
    }
  }

  children(nodeId) {
    return this.childLists.get(nodeId) ?? [];
  }

  nameOf(key) {
    return this.names.get(key);
  }

  /** Path segments from the root ([] is the root itself). */
  nodeSegments(nodeId) {
    const segments = this.paths.get(`n:${nodeId}`);
    if (!segments) throw new Error(`${this.file}: node '${nodeId}' is not in the tree`);
    return segments;
  }

  instanceSegments(instanceId) {
    const segments = this.paths.get(`i:${instanceId}`);
    if (!segments) throw new Error(`${this.file}: instance '${instanceId}' is not in the tree`);
    return segments;
  }

  /**
   * Resolves `{ nodeId, instancePath? }` to { segments, scene, node }: the path
   * from this scene's root and the authored node it lands on (which may live
   * in an instanced scene).
   */
  resolveReference(reference) {
    const instancePath = reference.instancePath ?? [];
    if (instancePath.length === 0) {
      const node = this.nodes.get(reference.nodeId);
      if (!node) throw new Error(`${this.file}: reference to missing node '${reference.nodeId}'`);
      return { segments: this.nodeSegments(node.id), scene: this, node };
    }
    const [first, ...rest] = instancePath;
    const instance = this.instances.get(first);
    if (!instance) throw new Error(`${this.file}: reference walks into missing instance '${first}'`);
    const inner = this.project.sceneModel(instance.sceneId).resolveReference({ nodeId: reference.nodeId, instancePath: rest });
    return { segments: [...this.instanceSegments(first), ...inner.segments], scene: inner.scene, node: inner.node };
  }

  /** The node's parent node (null for the root). */
  parentOf(node) {
    return node.parentId === null ? null : this.nodes.get(node.parentId);
  }

  /**
   * Follows an animation binding such as `../Visual` or `../AttackArea/x`
   * from `fromNode`. Returns { node } or null.
   */
  resolveBinding(fromNode, binding) {
    let current = fromNode;
    for (const part of binding.split('/')) {
      if (part === '' || part === '.') continue;
      if (part === '..') {
        current = this.parentOf(current);
        if (!current) return null;
        continue;
      }
      const child = this.children(current.id).find((entry) => entry.kind === 'node' && entry.item.name === part);
      if (!child) return null;
      current = child.item;
    }
    return { node: current };
  }

  /** The root's depth anchor (feet), or null when the root is not a depth source. */
  get depthAnchor() {
    const anchor = this.root.properties?.depthAnchor;
    return Array.isArray(anchor) ? anchor : null;
  }

  /** Root scale (re-anchoring multiplies the anchor by it). */
  get rootScale() {
    return vec(this.root.properties?.scale, [1, 1]);
  }

  /** Offset added to positions of direct children of a re-anchored root. */
  childShift(node) {
    const anchor = this.depthAnchor;
    if (!anchor || node.parentId !== this.root.id) return [0, 0];
    return [-anchor[0], -anchor[1]];
  }

  /**
   * Y-sort policy. A depth source (root with `depthAnchor`) draws as one unit
   * at its feet in child order, and so does a scene whose relative sprites
   * get their depth source at run time (weapons, mounted under the player).
   * Everything else y-sorts each container so nested sprites sort by their
   * own global Y, as Phaser's world-sorted sprites do.
   */
  get ySorted() {
    if (this.ySortedValue !== undefined) return this.ySortedValue;
    const relativeWithoutSource = !this.depthAnchor
      && this.doc.nodes.some((node) => node.type === 'Sprite2D' && node.properties?.depthMode === 'relative');
    this.ySortedValue = !this.depthAnchor && !relativeWithoutSource;
    return this.ySortedValue;
  }
}

export function sanitizeName(name) {
  const clean = String(name).replace(ILLEGAL_NAME_CHARS, '_');
  return clean.length ? clean : '_';
}

/** Relative NodePath text from `from` to `to` (segment arrays from one root). */
export function relativePath(from, to) {
  let common = 0;
  while (common < from.length && common < to.length && from[common] === to[common]) common += 1;
  const parts = [...Array(from.length - common).fill('..'), ...to.slice(common)];
  return parts.length ? parts.join('/') : '.';
}

/** Path text from the scene root, as `parent=`/`from=` attributes use it. */
export function rootPath(segments) {
  return segments.length ? segments.join('/') : '.';
}
