import { instanceId, type PersistenceKey, type RuntimeNodeId } from '../../content/scenes/identifiers';
import type { SceneInstanceProvenance } from '../../content/scenes/types';
import { DisposableScope } from './DisposableScope';
import { NodePath, nodePath } from './NodePath';
import { NodeReference } from './NodeReference';
import type { SceneTree, SceneTreeInputEvent } from './SceneTree';
import { Signal } from './Signal';

export type NodeLifecycleState = 'detached' | 'entering' | 'inside-not-ready' | 'ready' | 'exiting' | 'queued-for-free' | 'freed';

export interface NodeOptions {
  readonly runtimeId: RuntimeNodeId;
  readonly name: string;
}

let nextDuplicateNamespace = 1;
let nextDuplicateInstance = 1;

export function validateNodeName(name: string): void {
  if (name.length === 0 || name === '.' || name === '..' || name.includes('/')) throw new Error(`Invalid node name '${name}'`);
}

function duplicateRuntimeId(source: RuntimeNodeId): RuntimeNodeId {
  const authoredSegment = source.split('/').at(-1) ?? 'node';
  return `duplicate-${nextDuplicateNamespace++}/${authoredSegment}` as RuntimeNodeId;
}

export class Node {
  readonly runtimeId: RuntimeNodeId;
  private _name: string;
  private parent?: Node;
  private children: Node[] = [];
  private tree?: SceneTree;
  private mutationOwner?: SceneTree;
  private lifecycle: Exclude<NodeLifecycleState, 'queued-for-free'> = 'detached';
  private queuedForFree = false;
  private readyCalled = false;
  private processEnabled = false;
  private physicsProcessEnabled = false;
  private inputEnabled = false;
  private unhandledInputEnabled = false;
  private processWhenPaused = false;
  private readonly groups = new Set<string>();
  private entryScope = new DisposableScope();
  private readonly lifetimeScope = new DisposableScope();
  private readonly signals = new Map<string, Signal<unknown>>();
  private readonly signalHandlers = new Map<string, (payload: unknown) => void>();
  private readonly signalDisconnects = new Set<() => void>();
  private readonly references = new Map<string, NodeReference>();
  private instanceProvenance?: SceneInstanceProvenance;
  private persistenceKey?: PersistenceKey;

  constructor(options: NodeOptions) {
    validateNodeName(options.name);
    this.runtimeId = options.runtimeId;
    this._name = options.name;
  }

  get name(): string { return this._name; }
  set name(value: string) {
    validateNodeName(value);
    if (this.parent?.children.some((sibling) => sibling !== this && sibling.name === value)) throw new Error(`Sibling name '${value}' already exists`);
    this._name = value;
  }

  get lifecycleState(): NodeLifecycleState { return this.queuedForFree ? 'queued-for-free' : this.lifecycle; }
  get entryDisposables(): DisposableScope { return this.entryScope; }
  get lifetimeDisposables(): DisposableScope { return this.lifetimeScope; }
  get authoredInstanceProvenance(): SceneInstanceProvenance | undefined { return this.instanceProvenance; }
  get explicitPersistenceKey(): PersistenceKey | undefined { return this.persistenceKey; }

  add_child(node: Node): void {
    this.assertMutable();
    node.assertMutable();
    if (this.tree) { this.tree.queueAdd(this, node); return; }
    if (node.tree) throw new Error('Cannot add a node from another tree; detach it first');
    this._attachDetachedChild(node);
  }

  remove_child(node: Node): void {
    this.assertMutable();
    if (node.parent !== this) throw new Error(`Node '${node.name}' is not a child of '${this.name}'`);
    if (this.tree) { this.tree.queueRemove(node); return; }
    this._detachImmediate(node);
  }

  reparent(parent: Node): void {
    this.assertMutable();
    parent.assertMutable();
    if (this.tree || parent.tree) {
      if (!this.tree || this.tree !== parent.tree) throw new Error('Cross-tree reparent is not supported');
      this.tree.queueReparent(this, parent);
      return;
    }
    const oldParent = this.parent;
    const oldIndex = oldParent?.children.indexOf(this) ?? -1;
    oldParent?._detachImmediate(this);
    try { parent._attachDetachedChild(this); }
    catch (error) {
      if (oldParent) { oldParent._attachDetachedChild(this); oldParent._reorderChildInternal(this, oldIndex); }
      throw error;
    }
  }

  queue_free(): void {
    if (this.lifecycle === 'freed' || this.queuedForFree) return;
    this.queuedForFree = true;
    if (this.tree) this.tree.queueFree(this);
    else if (this.mutationOwner) this.mutationOwner.queueFree(this);
    else this._freeDetachedSubtree(() => undefined);
  }

  duplicate(): Node {
    const remap = new Map<Node, Node>();
    const cloneTree = (source: Node): Node => {
      const copy = source._duplicateSelf(duplicateRuntimeId(source.runtimeId));
      copy.processEnabled = source.processEnabled;
      copy.physicsProcessEnabled = source.physicsProcessEnabled;
      copy.inputEnabled = source.inputEnabled;
      copy.unhandledInputEnabled = source.unhandledInputEnabled;
      copy.processWhenPaused = source.processWhenPaused;
      for (const group of source.groups) copy.groups.add(group);
      for (const signalId of source.signals.keys()) if (!copy.signals.has(signalId)) copy.createSignal(signalId);
      source._copyConfigurationTo(copy);
      if (source.instanceProvenance) {
        copy.instanceProvenance = {
          ...structuredClone(source.instanceProvenance),
          authoredInstanceId: instanceId(`duplicate-${nextDuplicateInstance++}`),
        };
      }
      remap.set(source, copy);
      for (const child of source.children) copy._attachDetachedChild(cloneTree(child));
      return copy;
    };
    const copy = cloneTree(this);
    for (const [source, target] of remap) {
      for (const [key, reference] of source.references) target.references.set(key, reference.duplicate(remap));
      for (const [signalId, signal] of source.signals) {
        const copiedSignal = target.signals.get(signalId);
        for (const connection of signal._connections()) {
          const copiedTarget = remap.get(connection.target);
          if (connection.active && copiedSignal && copiedTarget?._hasSignalHandler(connection.handlerId)) copiedSignal.connect(copiedTarget, connection.handlerId);
        }
      }
    }
    return copy;
  }

  get_parent(): Node | undefined { return this.parent; }
  get_children(): readonly Node[] { return [...this.children]; }
  get_child(index: number): Node | undefined { return this.children[index]; }
  get_child_count(): number { return this.children.length; }
  get_tree(): SceneTree | undefined { return this.tree; }
  is_inside_tree(): boolean { return this.tree !== undefined && this.lifecycle !== 'detached' && this.lifecycle !== 'freed'; }
  is_freed(): boolean { return this.lifecycle === 'freed'; }
  was_ready(): boolean { return this.readyCalled; }

  get_path(): string {
    const names: string[] = [];
    let current: Node | undefined = this;
    while (current) { names.unshift(current.name); current = current.parent; }
    return `/${names.join('/')}`;
  }

  get_node(path: string | NodePath): Node {
    const parsed = nodePath(path);
    let current: Node | undefined = parsed.absolute ? this.tree?._rootForLookup(this) : this;
    if (!current) throw new Error(`Cannot resolve absolute path '${parsed}' outside a tree`);
    const segments = [...parsed.segments];
    if (parsed.absolute && segments[0] === current.name) segments.shift();
    for (const segment of segments) {
      if (segment === '.') continue;
      if (segment === '..') current = current.parent;
      else current = current.children.find((child) => child.name === segment);
      if (!current) throw new Error(`Node path '${parsed}' does not resolve from '${this.get_path()}'`);
    }
    return current;
  }

  has_node(path: string | NodePath): boolean {
    try { this.get_node(path); return true; } catch { return false; }
  }

  set_process(enabled: boolean): void { this.processEnabled = enabled; }
  set_physics_process(enabled: boolean): void { this.physicsProcessEnabled = enabled; }
  set_process_input(enabled: boolean): void { this.inputEnabled = enabled; }
  set_process_unhandled_input(enabled: boolean): void { this.unhandledInputEnabled = enabled; }
  set_process_when_paused(enabled: boolean): void { this.processWhenPaused = enabled; }
  is_processing(): boolean { return this.processEnabled; }
  is_physics_processing(): boolean { return this.physicsProcessEnabled; }
  is_processing_input(): boolean { return this.inputEnabled; }
  is_processing_unhandled_input(): boolean { return this.unhandledInputEnabled; }
  can_process_while_paused(): boolean { return this.processWhenPaused; }

  add_to_group(group: string): void { if (group.length === 0) throw new Error('Group cannot be empty'); this.groups.add(group); this.tree?._refreshGroups(this); }
  remove_from_group(group: string): void { this.groups.delete(group); this.tree?._refreshGroups(this); }
  is_in_group(group: string): boolean { return this.groups.has(group); }
  get_groups(): readonly string[] { return [...this.groups].sort(); }

  createSignal<T = void>(id: string): Signal<T> {
    if (this.signals.has(id)) throw new Error(`Signal '${id}' already exists on '${this.name}'`);
    const signal = new Signal<T>(this, id);
    this.signals.set(id, signal as Signal<unknown>);
    return signal;
  }

  getSignal<T = void>(id: string): Signal<T> | undefined { return this.signals.get(id) as Signal<T> | undefined; }

  registerSignalHandler<T>(id: string, handler: (payload: T) => void): void {
    if (this.signalHandlers.has(id)) throw new Error(`Signal handler '${id}' already exists on '${this.name}'`);
    this.signalHandlers.set(id, handler as (payload: unknown) => void);
  }

  defineReference<T extends Node>(key: string, reference: NodeReference<T>): NodeReference<T> {
    if (this.references.has(key)) throw new Error(`Node reference '${key}' already exists on '${this.name}'`);
    this.references.set(key, reference);
    return reference;
  }

  getReference<T extends Node>(key: string): NodeReference<T> | undefined { return this.references.get(key) as NodeReference<T> | undefined; }

  queue_external_command(action: () => void): void {
    if (!this.tree) throw new Error(`Node '${this.name}' cannot queue an external command while detached`);
    this.tree._queueExternalCommand(this, action);
  }

  create_entry_abort_controller(): AbortController {
    if (!this.tree) throw new Error(`Node '${this.name}' cannot create an entry abort controller while detached`);
    const controller = new AbortController();
    this.entryScope.add(() => controller.abort());
    return controller;
  }

  _enter_tree(): void {}
  _ready(): void {}
  _process(_deltaSeconds: number): void {}
  _physics_process(_deltaSeconds: number): void {}
  _input(_event: SceneTreeInputEvent): void {}
  _unhandled_input(_event: SceneTreeInputEvent): void {}
  _exit_tree(): void {}

  protected _duplicateSelf(runtimeId: RuntimeNodeId): Node { return new Node({ runtimeId, name: this.name }); }
  protected _copyConfigurationTo(_copy: Node): void {}

  /** @internal */
  _getChildrenInternal(): readonly Node[] { return this.children; }
  /** @internal */
  _getParentInternal(): Node | undefined { return this.parent; }
  /** @internal */
  _setTreeInternal(tree: SceneTree | undefined): void { this.tree = tree; }
  /** @internal */
  _setMutationOwnerInternal(tree: SceneTree | undefined): void { this.mutationOwner = tree; }
  /** @internal */
  _setInstanceProvenanceInternal(provenance: SceneInstanceProvenance | undefined): void { this.instanceProvenance = provenance; }
  /** @internal */
  _setPersistenceKeyInternal(key: PersistenceKey | undefined): void { this.persistenceKey = key; }
  /** @internal */
  _setLifecycleInternal(state: Exclude<NodeLifecycleState, 'queued-for-free'>): void { this.lifecycle = state; }
  /** @internal */
  _markReadyInternal(): void { this.readyCalled = true; this.lifecycle = 'ready'; }
  /** @internal */
  _clearQueuedForFreeInternal(): void { this.queuedForFree = false; }
  /** @internal */
  _resetEntryScopeInternal(): void { this.entryScope = new DisposableScope(); }
  /** @internal */
  _attachDetachedChild(node: Node): void {
    if (node.parent) throw new Error(`Node '${node.name}' already has a parent`);
    if (node === this || node.isAncestorOf(this)) throw new Error('Cannot create a node ancestry cycle');
    if (this.children.some((child) => child.name === node.name)) throw new Error(`Sibling name '${node.name}' already exists`);
    node.parent = this;
    this.children.push(node);
  }
  /** @internal */
  _detachImmediate(node: Node): void {
    const index = this.children.indexOf(node);
    if (index < 0) throw new Error(`Node '${node.name}' is not a child of '${this.name}'`);
    this.children.splice(index, 1);
    node.parent = undefined;
  }
  /** @internal */
  _reorderChildInternal(node: Node, index: number): void {
    const current = this.children.indexOf(node);
    if (current < 0) throw new Error(`Node '${node.name}' is not a child of '${this.name}'`);
    this.children.splice(current, 1);
    this.children.splice(Math.max(0, Math.min(index, this.children.length)), 0, node);
  }
  /** @internal */
  _isAncestorOf(candidate: Node): boolean { return this.isAncestorOf(candidate); }
  /** @internal */
  _isSignalActive(): boolean { return this.lifecycle === 'ready' && !this.queuedForFree && this.tree !== undefined; }
  /** @internal */
  _hasSignalHandler(id: string): boolean { return this.signalHandlers.has(id); }
  /** @internal */
  _invokeSignalHandler(id: string, payload: unknown): void { this.signalHandlers.get(id)?.(payload); }
  /** @internal */
  _ownSignalDisconnect(disconnect: () => void): void { this.signalDisconnects.add(disconnect); }
  /** @internal */
  _disconnectSignalsInternal(): void { for (const disconnect of this.signalDisconnects) disconnect(); this.signalDisconnects.clear(); }
  /** @internal */
  _getReferencesInternal(): readonly NodeReference[] { return [...this.references.values()]; }
  /** @internal */
  _disposeEntryInternal(onError: (error: unknown) => void): void { this.entryScope.disposeSafely(onError); }
  /** @internal */
  _freeDetachedSubtree(onError: (error: unknown) => void): void {
    for (const child of [...this.children].reverse()) child._freeDetachedSubtree(onError);
    this._disposeEntryInternal(onError);
    this.lifetimeScope.disposeSafely(onError);
    this._disconnectSignalsInternal();
    this.children = [];
    if (this.parent) this.parent._detachImmediate(this);
    this.tree = undefined;
    this.mutationOwner = undefined;
    this.queuedForFree = false;
    this.lifecycle = 'freed';
  }

  private assertMutable(): void {
    if (this.lifecycle === 'freed') throw new Error(`Node '${this.name}' has been freed`);
    if (this.queuedForFree) throw new Error(`Node '${this.name}' is queued for free`);
  }

  private isAncestorOf(candidate: Node): boolean {
    let current = candidate.parent;
    while (current) { if (current === this) return true; current = current.parent; }
    return false;
  }
}
