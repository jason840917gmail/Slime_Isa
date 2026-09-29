import type { AuthoredNodeId, InstanceId, SceneId } from '../../content/scenes/identifiers';
import type { SceneDocument, SceneInstanceDocument, SceneNodeDocument } from '../../content/scenes/types';

export type SceneTreeRow =
  | { readonly kind: 'node'; readonly key: string; readonly depth: number; readonly name: string; readonly type: string; readonly nodeId: AuthoredNodeId; readonly readOnly: boolean; readonly sourceSceneId: SceneId; readonly instancePath: readonly InstanceId[] }
  | { readonly kind: 'instance'; readonly key: string; readonly depth: number; readonly name: string; readonly instanceId: InstanceId; readonly sceneId: SceneId; readonly parentNodeId: AuthoredNodeId; readonly readOnly: false; readonly instancePath?: readonly InstanceId[]; readonly expandable?: boolean; readonly expanded?: boolean };

export type SceneDocumentResolver = (sceneId: SceneId) => SceneDocument | undefined;

type Child = { readonly order: number; readonly kind: 'node'; readonly node: SceneNodeDocument } | { readonly order: number; readonly kind: 'instance'; readonly instance: SceneInstanceDocument };

function children(document: SceneDocument, parentId: AuthoredNodeId): readonly Child[] {
  return [
    ...document.nodes.filter((node) => node.parentId === parentId).map((node) => ({ kind: 'node' as const, node, order: node.order })),
    ...document.instances.filter((instance) => instance.parentNodeId === parentId).map((instance) => ({ kind: 'instance' as const, instance, order: instance.order })),
  ].sort((left, right) => left.order - right.order || (left.kind === 'node' ? left.node.name : left.instance.name).localeCompare(right.kind === 'node' ? right.node.name : right.instance.name));
}

/**
 * Flattens the authored tree. Instances whose source scene resolves are
 * expandable; `isExpanded` receives the instance row key and decides whether
 * its read-only descendants are listed (all expanded by default).
 */
export function sceneTreeRows(document: SceneDocument, resolve: SceneDocumentResolver = () => undefined, isExpanded: (instanceRowKey: string) => boolean = () => true): readonly SceneTreeRow[] {
  const rows: SceneTreeRow[] = [];
  const renderNode = (owner: SceneDocument, node: SceneNodeDocument, depth: number, instancePath: readonly InstanceId[], readOnly: boolean, sceneStack: readonly SceneId[]): void => {
    rows.push({ kind: 'node', key: `${instancePath.join('/')}:${node.id}`, depth, name: node.name, type: node.type, nodeId: node.id, readOnly, sourceSceneId: owner.sceneId, instancePath });
    for (const child of children(owner, node.id)) {
      if (child.kind === 'node') renderNode(owner, child.node, depth + 1, instancePath, readOnly, sceneStack);
      else {
        const instance = child.instance;
        const key = `${instancePath.join('/')}:instance:${instance.instanceId}`;
        const source = resolve(instance.sceneId);
        const expandable = Boolean(source && !sceneStack.includes(source.sceneId));
        const expanded = expandable && isExpanded(key);
        rows.push({ kind: 'instance', key, depth: depth + 1, name: instance.name, instanceId: instance.instanceId, sceneId: instance.sceneId, parentNodeId: instance.parentNodeId, readOnly: false, instancePath, expandable, expanded });
        if (!source || !expanded) continue;
        const root = source.nodes.find((candidate) => candidate.id === source.rootNodeId);
        if (root) renderNode(source, root, depth + 2, [...instancePath, instance.instanceId], true, [...sceneStack, source.sceneId]);
      }
    }
  };
  const root = document.nodes.find((node) => node.id === document.rootNodeId);
  if (root) renderNode(document, root, 0, [], false, [document.sceneId]);
  return rows;
}

/** An authored tree entry that can be dragged: a node of this scene or one of its own instances. */
export type SceneTreeEntry = { readonly kind: 'node'; readonly nodeId: AuthoredNodeId } | { readonly kind: 'instance'; readonly instanceId: InstanceId };

/** Where a drop lands relative to the row under the cursor. */
export type SceneTreeDropZone = 'before' | 'inside' | 'after';

/** Rows the user may drag: authored non-root nodes and this scene's own instances. */
export function sceneTreeRowMovable(row: SceneTreeRow, rootNodeId: AuthoredNodeId): boolean {
  if (row.kind === 'instance') return (row.instancePath ?? []).length === 0;
  return !row.readOnly && row.nodeId !== rootNodeId;
}

/** The authored entry a row stands for, when it belongs to this scene. */
export function sceneTreeEntry(row: SceneTreeRow): SceneTreeEntry | undefined {
  if (row.kind === 'instance') return (row.instancePath ?? []).length === 0 ? { kind: 'instance', instanceId: row.instanceId } : undefined;
  return row.readOnly ? undefined : { kind: 'node', nodeId: row.nodeId };
}

/** `before`/`after` in the outer quarters of a row, `inside` in the middle (only nodes accept children). */
export function sceneTreeDropZone(offsetY: number, height: number, target: SceneTreeEntry): SceneTreeDropZone {
  const ratio = height > 0 ? offsetY / height : 0.5;
  if (target.kind === 'instance') return ratio < 0.5 ? 'before' : 'after';
  return ratio < 0.25 ? 'before' : ratio > 0.75 ? 'after' : 'inside';
}

function entryKey(entry: SceneTreeEntry): string {
  return entry.kind === 'node' ? `node:${entry.nodeId}` : `instance:${entry.instanceId}`;
}

/**
 * Parent and sibling position for dropping `dragged` on `target`, in the
 * `order` convention of `reparentNode`/`moveInstance` (index among the new
 * parent's other children). Undefined when the drop is not allowed: onto
 * itself, into its own subtree, beside the root, or inside an instance.
 */
export function planSceneTreeDrop(
  document: SceneDocument,
  dragged: SceneTreeEntry,
  target: SceneTreeEntry,
  zone: SceneTreeDropZone,
): { readonly parentId: AuthoredNodeId; readonly order: number } | undefined {
  if (entryKey(dragged) === entryKey(target)) return undefined;
  if (dragged.kind === 'node' && dragged.nodeId === document.rootNodeId) return undefined;
  const parentOf = (entry: SceneTreeEntry): AuthoredNodeId | null | undefined => entry.kind === 'node'
    ? document.nodes.find((node) => node.id === entry.nodeId)?.parentId
    : document.instances.find((instance) => instance.instanceId === entry.instanceId)?.parentNodeId;
  if (parentOf(dragged) === undefined) return undefined;
  let parentId: AuthoredNodeId;
  if (zone === 'inside') {
    if (target.kind !== 'node' || !document.nodes.some((node) => node.id === target.nodeId)) return undefined;
    parentId = target.nodeId;
  } else {
    const parent = parentOf(target);
    if (!parent) return undefined; // the root has no siblings; missing targets are rejected too
    parentId = parent;
  }
  if (dragged.kind === 'node') {
    // a node cannot move beneath itself
    for (let current: AuthoredNodeId | null | undefined = parentId; current; current = document.nodes.find((node) => node.id === current)?.parentId) {
      if (current === dragged.nodeId) return undefined;
    }
  }
  const draggedKey = entryKey(dragged);
  const siblings = [
    ...document.nodes.filter((node) => node.parentId === parentId).map((node) => ({ key: `node:${node.id}`, order: node.order })),
    ...document.instances.filter((instance) => instance.parentNodeId === parentId).map((instance) => ({ key: `instance:${instance.instanceId}`, order: instance.order })),
  ].filter((entry) => entry.key !== draggedKey).sort((left, right) => left.order - right.order || left.key.localeCompare(right.key));
  if (zone === 'inside') return { parentId, order: siblings.length };
  const index = siblings.findIndex((entry) => entry.key === entryKey(target));
  if (index < 0) return undefined;
  return { parentId, order: zone === 'before' ? index : index + 1 };
}

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character] ?? character);
}

export function renderSceneTreePanel(rows: readonly SceneTreeRow[], selectedKey?: string, rootNodeId?: AuthoredNodeId): string {
  return `<section class="scene-tree-panel" aria-label="Scene tree"><header><span>COMPOSITION</span><button type="button" data-scene-add aria-label="Add node">＋</button></header><div role="tree">${rows.map((row) => `<button type="button" role="treeitem" aria-level="${row.depth + 1}"${row.kind === 'instance' && row.expandable ? ` aria-expanded="${Boolean(row.expanded)}"` : ''} aria-selected="${row.key === selectedKey}" class="scene-tree-row${row.key === selectedKey ? ' is-selected' : ''}${row.readOnly ? ' is-readonly' : ''}" style="--scene-depth:${row.depth}"${rootNodeId !== undefined && sceneTreeRowMovable(row, rootNodeId) ? ' draggable="true"' : ''} data-scene-tree-key="${escapeHtml(row.key)}">${row.kind === 'instance' && row.expandable ? `<span class="scene-tree-toggle" data-tree-toggle="${escapeHtml(row.key)}" aria-hidden="true" title="${row.expanded ? 'Collapse' : 'Expand'} instance">${row.expanded ? '▾' : '▸'}</span>` : `<span aria-hidden="true">${row.kind === 'instance' ? '◇' : row.readOnly ? '·' : '◆'}</span>`}<strong>${escapeHtml(row.name)}</strong><small>${escapeHtml(row.kind === 'instance' ? row.sceneId : row.type)}</small></button>`).join('')}</div></section>`;
}
