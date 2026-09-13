import type { PersistenceKey, RuntimeNodeId, SceneId } from '../../content/scenes/identifiers';
import { Node } from './Node';
import { Node2D, type Transform2D } from './Node2D';
import { SceneMutationQueue, type PendingSceneMutation, type SceneMutation } from './SceneMutationQueue';
import type { SceneDiagnostic, SceneDiagnosticSink, SceneLifecyclePhase } from './SceneDiagnostic';

export interface SceneTreeInputEvent {
  handled: boolean;
  readonly type?: string;
  readonly timestamp?: number;
  readonly payload?: unknown;
}

export interface SceneTreeOptions {
  readonly sceneId?: SceneId;
  readonly diagnosticSink?: SceneDiagnosticSink;
  readonly validateParent?: (node: Node, parent: Node) => string | undefined;
}

export class SceneTree {
  root?: Node;
  paused = false;
  readonly diagnostics: SceneDiagnostic[] = [];
  private readonly runtimeIndex = new Map<RuntimeNodeId, Node>();
  private readonly persistenceIndex = new Map<PersistenceKey, Node>();
  private readonly groupIndex = new Map<string, Set<Node>>();
  private readonly mutations = new SceneMutationQueue();
  private boundaryDepth = 0;
  private flushing = false;
  private currentExternalCommands?: Array<{ readonly node: Node; readonly action: () => void }>;
  private stagedNodes?: ReadonlySet<Node>;
  private stagedRoot?: Node;
  private fatalState = false;

  constructor(private readonly options: SceneTreeOptions = {}) {}

  setRoot(root: Node): void {
    if (this.root) throw new Error('SceneTree already has a root');
    if (root.get_parent() || root.get_tree() || root.is_freed()) throw new Error('SceneTree root must be a live detached root node');
    this.boundaryDepth += 1;
    this.currentExternalCommands = [];
    this.stagedRoot = root;
    try {
      this.enterSubtree(root);
      this.root = root;
      const commands = this.currentExternalCommands;
      this.currentExternalCommands = undefined;
      this.stagedRoot = undefined;
      this.runExternalCommands(commands);
    } catch (error) {
      this.report(root, 'mutation', error);
      this.currentExternalCommands = undefined;
      this.stagedRoot = undefined;
      this.discardQueuedMutations();
    } finally {
      this.boundaryDepth -= 1;
      if (this.boundaryDepth === 0 && !this.flushing) this.flushMutations();
    }
  }

  getNodeById(runtimeId: RuntimeNodeId): Node | undefined { return this.runtimeIndex.get(runtimeId); }
  getNodeByPersistenceKey(key: PersistenceKey): Node | undefined { return this.persistenceIndex.get(key); }
  getNodesInGroup(group: string): readonly Node[] {
    const members = this.groupIndex.get(group);
    return members ? this.treeOrder().filter((node) => members.has(node)) : [];
  }
  get indexedNodeCount(): number { return this.runtimeIndex.size; }
  get indexedPersistenceKeyCount(): number { return this.persistenceIndex.size; }
  get indexedGroupCount(): number { return this.groupIndex.size; }
  get queuedMutationCount(): number { return this.mutations.size; }
  get isFatal(): boolean { return this.fatalState; }

  replaceRoot(replacement: Node): boolean {
    if (this.fatalState) throw new Error('Cannot replace the root of a fatal SceneTree');
    if (this.boundaryDepth > 0 || this.flushing || this.mutations.size > 0) throw new Error('Root replacement requires a stable scene boundary');
    if (replacement.get_parent() || replacement.get_tree() || replacement.is_freed()) throw new Error('Replacement root must be a live detached root node');
    const previous = this.root;
    if (!previous) { this.setRoot(replacement); return replacement.get_tree() === this; }

    const wasPaused = this.paused;
    this.paused = true;
    this.boundaryDepth += 1;
    this.currentExternalCommands = [];
    try {
      this.exitSubtree(previous);
      this.root = undefined;
      this.stagedRoot = replacement;
      this.enterSubtree(replacement);
      this.root = replacement;
      this.stagedRoot = undefined;
      const commands = this.currentExternalCommands;
      this.currentExternalCommands = undefined;
      previous._freeDetachedSubtree((error) => this.report(previous, 'dispose', error));
      this.runExternalCommands(commands);
      return true;
    } catch (error) {
      this.report(replacement, 'mutation', error);
      this.currentExternalCommands = undefined;
      this.stagedRoot = undefined;
      this.discardQueuedMutations();
      if (replacement.get_tree() === this) this.exitSubtree(replacement);
      this.stagedRoot = previous;
      this.currentExternalCommands = [];
      try {
        this.enterSubtree(previous);
        this.root = previous;
        this.stagedRoot = undefined;
        const restoreCommands = this.currentExternalCommands;
        this.currentExternalCommands = undefined;
        this.runExternalCommands(restoreCommands);
      } catch (restoreError) {
        this.currentExternalCommands = undefined;
        this.stagedRoot = undefined;
        this.root = undefined;
        this.fatalState = true;
        this.paused = true;
        this.report(previous, 'mutation', new AggregateError([error, restoreError], 'Replacement failed and the previous root could not be restored'));
        return false;
      }
      return false;
    } finally {
      this.boundaryDepth -= 1;
      if (!this.fatalState) this.paused = wasPaused;
      if (this.boundaryDepth === 0 && !this.flushing) this.flushMutations();
    }
  }

  queueAdd(parent: Node, node: Node): void {
    this.accepts(parent);
    if (node.is_freed()) throw new Error(`Cannot add freed node '${node.name}'`);
    node._setMutationOwnerInternal(this);
    try { this.enqueue({ kind: 'add', node, parent }); }
    catch (error) { node._setMutationOwnerInternal(undefined); throw error; }
  }

  queueRemove(node: Node): void {
    this.accepts(node);
    if (node === this.root) this.enqueue({ kind: 'remove', node });
    else if (!node.get_parent()) throw new Error(`Node '${node.name}' has no parent`);
    else this.enqueue({ kind: 'remove', node });
  }

  queueReparent(node: Node, parent: Node): void {
    this.accepts(node);
    this.accepts(parent);
    this.enqueue({ kind: 'reparent', node, parent });
  }

  queueFree(node: Node): void {
    if (node.get_tree() !== this && node.get_tree() !== undefined) throw new Error('Cannot free a node owned by another tree');
    this.enqueue({ kind: 'free', node });
  }

  flushMutations(): void {
    if (this.flushing || this.mutations.size === 0) return;
    this.flushing = true;
    const batch = this.mutations.takeBatch();
    const freeRoots = batch.filter((mutation): mutation is Extract<SceneMutation, { kind: 'free' }> => mutation.kind === 'free').map((mutation) => mutation.node);
    const suppressed = new Set(batch.filter((mutation) => freeRoots.some((ancestor) => {
      if (ancestor === mutation.node) return false;
      if (ancestor._isAncestorOf(mutation.node)) return true;
      return (mutation.kind === 'add' || mutation.kind === 'reparent') && (ancestor === mutation.parent || ancestor._isAncestorOf(mutation.parent));
    })));
    try {
      for (const mutation of batch) {
        if (suppressed.has(mutation)) { if (mutation.kind === 'add') mutation.node._setMutationOwnerInternal(undefined); continue; }
        try { this.applyMutation(mutation); }
        catch (error) { if (mutation.kind === 'add') mutation.node._setMutationOwnerInternal(undefined); this.report(mutation.node, 'mutation', error); }
      }
    } finally {
      this.flushing = false;
    }
  }

  process(deltaSeconds: number): void {
    if (!Number.isFinite(deltaSeconds) || deltaSeconds < 0) throw new Error('Process delta must be a non-negative finite number');
    this.dispatch(() => {
      for (const node of this.treeOrder()) {
        if (!node.is_processing() || (this.paused && !node.can_process_while_paused())) continue;
        this.invoke(node, 'process', () => node._process(deltaSeconds), () => node.set_process(false));
      }
    });
  }

  physicsProcess(deltaSeconds: number): void {
    if (!Number.isFinite(deltaSeconds) || deltaSeconds < 0) throw new Error('Physics delta must be a non-negative finite number');
    this.dispatch(() => {
      for (const node of this.treeOrder()) {
        if (!node.is_physics_processing() || (this.paused && !node.can_process_while_paused())) continue;
        this.invoke(node, 'physics-process', () => node._physics_process(deltaSeconds), () => node.set_physics_process(false));
      }
    });
  }

  dispatchInput(event: SceneTreeInputEvent): void {
    this.dispatch(() => {
      for (const node of this.treeOrder()) {
        if (!node.is_processing_input() || (this.paused && !node.can_process_while_paused())) continue;
        this.invoke(node, 'input', () => node._input(event));
      }
      if (!event.handled) {
        for (const node of this.treeOrder()) {
          if (event.handled) break;
          if (!node.is_processing_unhandled_input() || (this.paused && !node.can_process_while_paused())) continue;
          this.invoke(node, 'unhandled-input', () => node._unhandled_input(event));
        }
      }
    });
  }

  shutdown(): void {
    if (this.root && !this.root.is_freed()) this.root.queue_free();
    let flushes = 0;
    while (this.mutations.size > 0 && flushes < 100) { this.flushMutations(); flushes += 1; }
    if (this.mutations.size > 0) throw new Error('SceneTree shutdown did not reach a stable mutation state');
  }

  /** @internal */
  _runBoundary(phase: SceneLifecyclePhase, node: Node, callback: () => void): void {
    this.boundaryDepth += 1;
    try { this.invoke(node, phase, callback); }
    finally {
      this.boundaryDepth -= 1;
      if (this.boundaryDepth === 0 && !this.flushing) this.flushMutations();
    }
  }

  /** @internal */
  _refreshGroups(node: Node): void {
    for (const [group, members] of this.groupIndex) { members.delete(node); if (members.size === 0) this.groupIndex.delete(group); }
    if (this.stagedNodes?.has(node)) return;
    if (!node.is_inside_tree()) return;
    for (const group of node.get_groups()) {
      const members = this.groupIndex.get(group) ?? new Set<Node>();
      members.add(node);
      this.groupIndex.set(group, members);
    }
  }

  /** @internal */
  _queueExternalCommand(node: Node, action: () => void): void {
    if (node.get_tree() !== this) throw new Error(`Node '${node.name}' is not in this tree`);
    if (this.currentExternalCommands) this.currentExternalCommands.push({ node, action });
    else this.invoke(node, 'mutation', action);
  }

  /** @internal */
  _rootForLookup(node: Node): Node | undefined {
    if (this.stagedNodes?.has(node)) return this.root ?? this.stagedRoot;
    return this.root;
  }

  private accepts(node: Node): void {
    if (node.get_tree() !== this) throw new Error(`Node '${node.name}' is not in this tree`);
    if (node.is_freed() || node.lifecycleState === 'queued-for-free') throw new Error(`Node '${node.name}' cannot accept mutations in state '${node.lifecycleState}'`);
  }

  private enqueue(mutation: PendingSceneMutation): void {
    try { this.mutations.enqueue(mutation); } catch (error) { this.report(mutation.node, 'mutation', error); throw error; }
  }

  private dispatch(callback: () => void): void {
    this.boundaryDepth += 1;
    try { callback(); }
    finally { this.boundaryDepth -= 1; if (this.boundaryDepth === 0) this.flushMutations(); }
  }

  private invoke(node: Node, phase: SceneLifecyclePhase, callback: () => void, onError?: () => void): void {
    try { callback(); } catch (error) { onError?.(); this.report(node, phase, error); }
  }

  private report(node: Node, phase: SceneLifecyclePhase, error: unknown): void {
    const diagnostic: SceneDiagnostic = {
      sceneId: this.options.sceneId,
      nodePath: node.get_path(),
      runtimeId: node.runtimeId,
      phase,
      message: error instanceof Error ? error.message : String(error),
      error,
    };
    this.diagnostics.push(diagnostic);
    this.options.diagnosticSink?.(diagnostic);
  }

  private applyMutation(mutation: SceneMutation): void {
    if (mutation.kind === 'free') { this.freeNode(mutation.node); return; }
    if (mutation.node.is_freed() || mutation.node.lifecycleState === 'queued-for-free') throw new Error(`Node '${mutation.node.name}' cannot complete '${mutation.kind}' while queued or freed`);
    if (mutation.kind === 'remove') { this.removeNode(mutation.node); return; }
    if (mutation.kind === 'reparent') { this.reparentNode(mutation.node, mutation.parent); return; }
    this.addNode(mutation.parent, mutation.node);
  }

  private validatePlacement(node: Node, parent: Node): void {
    if (parent.get_tree() !== this || parent.is_freed() || parent.lifecycleState === 'queued-for-free') throw new Error(`Parent '${parent.name}' is not an active destination`);
    if (node === parent || node._isAncestorOf(parent)) throw new Error('Cannot create a node ancestry cycle');
    if (parent.get_children().some((sibling) => sibling !== node && sibling.name === node.name)) throw new Error(`Sibling name '${node.name}' already exists under '${parent.name}'`);
    const parentIssue = this.options.validateParent?.(node, parent);
    if (parentIssue) throw new Error(parentIssue);
  }

  private addNode(parent: Node, node: Node): void {
    if (node.get_tree() || node.get_parent()) throw new Error(`Node '${node.name}' must be detached before add`);
    this.validatePlacement(node, parent);
    node._setMutationOwnerInternal(undefined);
    parent._attachDetachedChild(node);
    try { this.enterSubtree(node); }
    catch (error) { if (node.get_parent() === parent) parent._detachImmediate(node); throw error; }
  }

  private removeNode(node: Node): void {
    if (node.get_tree() !== this) throw new Error(`Node '${node.name}' is no longer in this tree`);
    const parent = node.get_parent();
    this.exitSubtree(node);
    if (parent) parent._detachImmediate(node);
    else if (this.root === node) this.root = undefined;
  }

  private reparentNode(node: Node, parent: Node): void {
    if (node.get_tree() !== this || parent.get_tree() !== this) throw new Error('Reparent endpoints must remain in the accepting tree');
    if (node === this.root) throw new Error('Scene root cannot be reparented');
    this.validatePlacement(node, parent);
    const oldParent = node.get_parent();
    if (!oldParent || oldParent === parent) return;
    const oldIndex = oldParent.get_children().indexOf(node);
    const global: Transform2D | undefined = node instanceof Node2D ? node.get_global_transform() : undefined;
    oldParent._detachImmediate(node);
    try {
      parent._attachDetachedChild(node);
      if (global && node instanceof Node2D) node.set_global_transform(global);
    } catch (error) {
      if (node.get_parent() === parent) parent._detachImmediate(node);
      oldParent._attachDetachedChild(node);
      oldParent._reorderChildInternal(node, oldIndex);
      if (global && node instanceof Node2D) node.set_global_transform(global);
      throw error;
    }
  }

  private freeNode(node: Node): void {
    if (node.is_freed()) return;
    if (node.get_tree() === this) {
      const parent = node.get_parent();
      this.exitSubtree(node);
      if (parent) parent._detachImmediate(node);
      else if (this.root === node) this.root = undefined;
    }
    node._setMutationOwnerInternal(undefined);
    node._freeDetachedSubtree((error) => this.report(node, 'dispose', error));
  }

  private enterSubtree(root: Node): void {
    const nodes = this.subtreePreorder(root);
    const localIds = new Set<RuntimeNodeId>();
    const localPersistenceKeys = new Set<PersistenceKey>();
    for (const node of nodes) {
      if (node.is_freed()) throw new Error(`Cannot enter freed node '${node.name}'`);
      if (localIds.has(node.runtimeId) || this.runtimeIndex.has(node.runtimeId)) throw new Error(`Duplicate runtime node ID '${node.runtimeId}'`);
      localIds.add(node.runtimeId);
      const key = node.explicitPersistenceKey;
      if (key && (localPersistenceKeys.has(key) || this.persistenceIndex.has(key))) throw new Error(`Duplicate persistence key '${key}'`);
      if (key) localPersistenceKeys.add(key);
    }
    const available = new Set(nodes);
    for (const node of nodes) {
      for (const reference of node._getReferencesInternal()) {
        const target = reference.configuredTarget;
        if (reference.required && (!target || (!available.has(target) && target.get_tree() !== this))) {
          throw new Error(`Required node reference on '${node.name}' is unresolved`);
        }
      }
    }
    const ownsCommands = this.currentExternalCommands === undefined;
    if (ownsCommands) this.currentExternalCommands = [];
    const previousStagedNodes = this.stagedNodes;
    this.stagedNodes = new Set(nodes);
    for (const node of nodes) node._setTreeInternal(this);
    const entered: Node[] = [];
    let activeNode = root;
    let activePhase: 'enter' | 'ready' = 'enter';
    try {
      for (const node of nodes) {
        activeNode = node;
        activePhase = 'enter';
        node._resetEntryScopeInternal();
        node._setLifecycleInternal('entering');
        node._enter_tree();
        entered.push(node);
        node._setLifecycleInternal('inside-not-ready');
      }
      for (const node of this.subtreePostorder(root)) {
        activeNode = node;
        activePhase = 'ready';
        if (!node.was_ready()) {
          if (node.lifecycleState !== 'queued-for-free') { node._ready(); node._markReadyInternal(); }
        } else node._setLifecycleInternal('ready');
      }
      this.stagedNodes = previousStagedNodes;
      for (const node of nodes) {
        this.runtimeIndex.set(node.runtimeId, node);
        const key = node.explicitPersistenceKey;
        if (key) this.persistenceIndex.set(key, node);
        this._refreshGroups(node);
      }
      if (ownsCommands) {
        const commands = this.currentExternalCommands;
        this.currentExternalCommands = undefined;
        this.runExternalCommands(commands);
      }
    } catch (error) {
      this.stagedNodes = previousStagedNodes;
      this.report(activeNode, activePhase, error);
      for (const node of [...entered].reverse()) this.exitOne(node);
      for (const node of nodes) {
        if (!entered.includes(node)) node._disposeEntryInternal((disposeError) => this.report(node, 'dispose', disposeError));
        this.removeFromIndexes(node);
        node._setTreeInternal(undefined);
        node._setLifecycleInternal('detached');
      }
      if (ownsCommands) {
        this.currentExternalCommands = undefined;
        this.discardQueuedMutations();
      }
      throw error;
    }
  }

  private exitSubtree(root: Node): void {
    for (const node of this.subtreePostorder(root)) this.exitOne(node);
  }

  private exitOne(node: Node): void {
    if (node.get_tree() !== this) return;
    node._setLifecycleInternal('exiting');
    this.invoke(node, 'exit', () => node._exit_tree());
    node._disposeEntryInternal((error) => this.report(node, 'dispose', error));
    this.removeFromIndexes(node);
    node._setTreeInternal(undefined);
    node._setLifecycleInternal('detached');
  }

  private removeFromIndexes(node: Node): void {
    this.runtimeIndex.delete(node.runtimeId);
    const key = node.explicitPersistenceKey;
    if (key && this.persistenceIndex.get(key) === node) this.persistenceIndex.delete(key);
    for (const [group, members] of this.groupIndex) { members.delete(node); if (members.size === 0) this.groupIndex.delete(group); }
  }

  private treeOrder(): Node[] { return this.root ? this.subtreePreorder(this.root).filter((node) => node.lifecycleState === 'ready') : []; }

  private subtreePreorder(root: Node): Node[] {
    const output: Node[] = [];
    const visit = (node: Node): void => { output.push(node); for (const child of node._getChildrenInternal()) visit(child); };
    visit(root);
    return output;
  }

  private subtreePostorder(root: Node): Node[] {
    const output: Node[] = [];
    const visit = (node: Node): void => { for (const child of node._getChildrenInternal()) visit(child); output.push(node); };
    visit(root);
    return output;
  }

  private runExternalCommands(commands: readonly { readonly node: Node; readonly action: () => void }[] | undefined): void {
    for (const command of commands ?? []) this.invoke(command.node, 'mutation', command.action);
  }

  private discardQueuedMutations(): void {
    for (const mutation of this.mutations.clear()) {
      if (mutation.kind === 'free') mutation.node._clearQueuedForFreeInternal();
      if (mutation.kind === 'add') mutation.node._setMutationOwnerInternal(undefined);
    }
  }
}
