import type { DescriptorRegistry } from '../../content/scenes/propertyDescriptors';
import { createGameDescriptorRegistry } from '../../features/scripts/registrations';
import type { SceneNodeDocument } from '../../content/scenes/types';
import { SceneStudioConflictError, SceneStudioRepository, type SceneStudioContentSummary } from '../../infrastructure/scenes/editor/SceneStudioRepository';
import { handleStudioHistoryShortcut } from '../StudioHistoryShortcut';
import { PropertyEditorRegistry } from './PropertyEditorRegistry';
import { sceneCommands } from './SceneCommand';
import { sceneCreationEntries } from './SceneCreationDialog';
import { SceneDocumentState } from './SceneDocumentState';
import { renderSceneInspector, sceneInspectorModel } from './SceneInspector';
import { formatSceneStudioRoute, parseSceneStudioRoute } from './SceneStudioRoute';
import { renderSceneTreePanel, sceneTreeRows, type SceneTreeRow } from './SceneTreePanel';
import { SceneViewportState } from './SceneViewport';

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character] ?? character);
}

export class SceneStudioController {
  private readonly abort = new AbortController();
  private readonly propertyEditors = new PropertyEditorRegistry();
  private readonly viewport = new SceneViewportState();
  private catalog: readonly SceneStudioContentSummary[] = [];
  private state?: SceneDocumentState;
  private relativePath?: string;
  private selectedKey?: string;
  private rows: readonly SceneTreeRow[] = [];
  private message = 'Loading authored content…';
  private creationSearch?: string;

  constructor(
    private readonly container: HTMLElement,
    private readonly repository: SceneStudioRepository = new SceneStudioRepository(),
    private readonly registry: DescriptorRegistry = createGameDescriptorRegistry(),
  ) {}

  async start(): Promise<void> {
    this.bind();
    this.render();
    try {
      this.catalog = await this.repository.list();
      const requested = parseSceneStudioRoute(window.location.search).scene;
      if (requested) await this.open(requested);
      else { this.message = this.catalog.length > 0 ? 'Choose a scene from the expedition index.' : 'No authored scenes yet. Conversion outputs will appear here.'; this.render(); }
    } catch (error) { this.fail(error); }
  }

  destroy(): void { this.abort.abort(); this.container.replaceChildren(); }

  private bind(): void {
    this.container.addEventListener('click', (event) => { void this.handleClick(event); }, { signal: this.abort.signal });
    this.container.addEventListener('change', (event) => this.handleChange(event), { signal: this.abort.signal });
    this.container.addEventListener('input', (event) => {
      if (!(event.target instanceof HTMLInputElement) || event.target.dataset.creationSearch === undefined) return;
      this.creationSearch = event.target.value;
      this.render();
    }, { signal: this.abort.signal });
    this.container.addEventListener('keydown', (event) => {
      if (!(event.target instanceof HTMLElement) || event.target.getAttribute('role') !== 'treeitem' || !['ArrowDown', 'ArrowUp'].includes(event.key)) return;
      const rows = [...this.container.querySelectorAll<HTMLElement>('[role="treeitem"]')];
      const current = rows.indexOf(event.target);
      const next = rows[current + (event.key === 'ArrowDown' ? 1 : -1)];
      if (!next) return;
      event.preventDefault();
      next.focus();
      next.click();
    }, { signal: this.abort.signal });
    window.addEventListener('keydown', (event) => {
      if (this.state && handleStudioHistoryShortcut(event, () => this.undo(), () => this.redo())) this.render();
    }, { signal: this.abort.signal });
  }

  private async open(sceneId: string): Promise<void> {
    const record = await this.repository.load('scene', sceneId);
    if (record.kind !== 'scene' || !('sceneId' in record.document)) throw new Error(`'${sceneId}' is not a scene document`);
    this.state = new SceneDocumentState(record.document, { registry: this.registry }, record.hash);
    this.relativePath = record.relativePath;
    this.selectedKey = `:${record.document.rootNodeId}`;
    this.message = record.repairMode ? `Repair mode · ${record.issues.length} issue${record.issues.length === 1 ? '' : 's'}` : 'Document matches runtime contracts';
    window.history.replaceState(null, '', formatSceneStudioRoute({ active: true, scene: record.document.sceneId }, window.location.search));
    this.render();
  }

  private async save(): Promise<void> {
    if (!this.state || !this.relativePath) return;
    try {
      const [result] = await this.repository.save([{ kind: 'scene', id: this.state.sceneId, relativePath: this.relativePath, document: this.state.document, expectedHash: this.state.diskHash ?? null }]);
      this.state.markSaved(result.hash);
      this.message = 'Committed · disk and editor are synchronized';
    } catch (error) {
      this.message = error instanceof SceneStudioConflictError ? 'Save conflict · reload or preserve your draft before retrying' : error instanceof Error ? error.message : String(error);
    }
    this.render();
  }

  private undo(): boolean { const changed = this.state?.undo() ?? false; if (changed) this.message = 'Undid command'; return changed; }
  private redo(): boolean { const changed = this.state?.redo() ?? false; if (changed) this.message = 'Redid command'; return changed; }

  private async handleClick(event: Event): Promise<void> {
    const target = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-scene-id],[data-scene-tree-key],[data-action],[data-scene-add],[data-create-type],[data-create-script-id],[data-open-source],[data-node-id]') : null;
    if (!target) return;
    if (target.dataset.sceneId) { await this.open(target.dataset.sceneId); return; }
    if (target.dataset.sceneTreeKey) {
      const row = this.rows.find((candidate) => candidate.key === target.dataset.sceneTreeKey);
      if (row) {
        this.selectedKey = row.key;
        if (row.kind === 'node' && !row.readOnly) { this.state?.select({ kind: 'node', nodeId: row.nodeId }); this.viewport.select(row.nodeId); }
        else if (row.kind === 'instance') this.state?.select({ kind: 'instance', instanceId: row.instanceId });
        this.render();
      }
      return;
    }
    if (target.dataset.nodeId) {
      const row = this.rows.find((candidate) => candidate.kind === 'node' && !candidate.readOnly && candidate.nodeId === target.dataset.nodeId);
      if (row?.kind === 'node') { this.selectedKey = row.key; this.state?.select({ kind: 'node', nodeId: row.nodeId }); this.viewport.select(row.nodeId); this.render(); }
      return;
    }
    if (target.hasAttribute('data-scene-add')) { this.creationSearch = ''; this.render(); return; }
    if ((target.dataset.createType || target.dataset.createScriptId) && this.state) {
      const parentId = this.state.selection.kind === 'node' ? this.state.selection.nodeId : this.state.document.rootNodeId;
      const scriptId = target.dataset.createScriptId;
      const type = scriptId ? 'ScriptNode' : target.dataset.createType ?? 'Node';
      let suffix = 1;
      let id = type.toLowerCase();
      while (this.state.document.nodes.some((node) => node.id === id)) id = `${type.toLowerCase()}-${suffix++}`;
      const order = this.state.document.nodes.filter((node) => node.parentId === parentId).length + this.state.document.instances.filter((instance) => instance.parentNodeId === parentId).length;
      const name = scriptId ? this.registry.scripts.get(scriptId)?.displayName ?? scriptId : type;
      this.state.execute(sceneCommands.addNode({ id, name, type, ...(scriptId ? { scriptId } : {}), parentId, order, properties: {} } as SceneNodeDocument));
      this.creationSearch = undefined;
      this.selectedKey = `:${id}`;
      this.render();
      return;
    }
    if (target.dataset.openSource) { this.container.dispatchEvent(new CustomEvent('scene-studio-open-source', { bubbles: true, detail: { path: target.dataset.openSource } })); return; }
    if (target.dataset.action === 'save') await this.save();
    else if (target.dataset.action === 'undo') { this.undo(); this.render(); }
    else if (target.dataset.action === 'redo') { this.redo(); this.render(); }
    else if (target.dataset.action === 'close-create') { this.creationSearch = undefined; this.render(); }
  }

  private handleChange(event: Event): void {
    if (!this.state || (!(event.target instanceof HTMLInputElement) && !(event.target instanceof HTMLSelectElement) && !(event.target instanceof HTMLTextAreaElement))) return;
    if (event.target.dataset.creationSearch !== undefined) return;
    const property = event.target.dataset.property;
    const selection = this.state.selection;
    if (!property || selection.kind !== 'node') return;
    const node = this.state.document.nodes.find((candidate) => candidate.id === selection.nodeId);
    const descriptor = node ? [...sceneInspectorModel(node, this.registry).groups.values()].flat().find((candidate) => candidate.descriptor.key === property)?.descriptor : undefined;
    if (!descriptor) return;
    try {
      const raw = descriptor.inspector === 'checkbox' && event.target instanceof HTMLInputElement ? event.target.checked : event.target.value;
      this.state.execute(sceneCommands.setProperty(selection.nodeId, property, this.propertyEditors.get(descriptor.inspector).parse(raw, descriptor)));
      this.message = `Changed ${descriptor.label}`;
    } catch (error) { this.message = error instanceof Error ? error.message : String(error); }
    this.render();
  }

  private render(): void {
    const focused = document.activeElement instanceof HTMLElement
      ? (document.activeElement.dataset.sceneTreeKey ? `[data-scene-tree-key="${CSS.escape(document.activeElement.dataset.sceneTreeKey)}"]`
        : document.activeElement.dataset.property ? `[data-property="${CSS.escape(document.activeElement.dataset.property)}"]`
          : document.activeElement.dataset.action ? `[data-action="${CSS.escape(document.activeElement.dataset.action)}"]` : undefined)
      : undefined;
    const scenes = this.catalog.filter((item) => item.kind === 'scene');
    const resources = this.catalog.filter((item) => item.kind === 'resource');
    const state = this.state;
    this.rows = state ? sceneTreeRows(state.document) : [];
    const selectedRow = this.rows.find((row) => row.key === this.selectedKey);
    const selectedNode = state && selectedRow?.kind === 'node' && !selectedRow.readOnly ? state.document.nodes.find((node) => node.id === selectedRow.nodeId) : undefined;
    const inspector = selectedNode ? renderSceneInspector(sceneInspectorModel(selectedNode, this.registry)) : '<aside class="scene-inspector scene-empty"><span>INSPECTOR</span><p>Select a local node to inspect its authored properties.</p></aside>';
    const viewportNodes = state ? this.viewport.nodes(state.document.nodes) : [];
    this.container.innerHTML = `<main class="scene-studio" data-scene-studio><header class="scene-topbar"><div><span>FIELD CARTOGRAPHER / UNIVERSAL GRAPH</span><h1>Scene Studio</h1></div><div class="scene-command-bar"><button type="button" data-action="undo" ${!state?.canUndo ? 'disabled' : ''}>Undo</button><button type="button" data-action="redo" ${!state?.canRedo ? 'disabled' : ''}>Redo</button><button type="button" class="scene-save" data-action="save" ${!state?.dirty ? 'disabled' : ''}>${state?.dirty ? 'Save changes' : 'Saved'}</button></div></header><aside class="scene-explorer" aria-label="Project explorer"><label><span>EXPEDITION INDEX</span><input type="search" placeholder="Filter scenes and resources" aria-label="Filter scenes and resources" /></label><nav aria-label="Scenes"><h2>Scenes <em>${scenes.length}</em></h2>${scenes.map((item) => `<button type="button" data-scene-id="${escapeHtml(item.id)}" class="${item.id === state?.sceneId ? 'is-current' : ''}"><span>◫</span><strong>${escapeHtml(item.id)}</strong></button>`).join('') || '<p>No scene documents</p>'}<h2>Resources <em>${resources.length}</em></h2>${resources.map((item) => `<div class="scene-resource-row"><span>◈</span>${escapeHtml(item.id)}<small>${escapeHtml(item.relativePath)}</small></div>`).join('') || '<p>No external resources</p>'}</nav></aside><section class="scene-workbench">${state ? renderSceneTreePanel(this.rows, this.selectedKey) : '<section class="scene-tree-panel scene-empty"><p>Open a scene to reveal its graph.</p></section>'}<section class="scene-viewport" aria-label="2D viewport"><div class="scene-grid" style="--scene-zoom:${this.viewport.zoom}">${viewportNodes.map((node) => `<button type="button" class="scene-viewport-node${node.selected ? ' is-selected' : ''}" style="--x:${node.position[0]};--y:${node.position[1]}" data-node-id="${escapeHtml(node.id)}" aria-label="Select ${escapeHtml(node.name)}"><span>${escapeHtml(node.name)}</span></button>`).join('')}<div class="scene-origin">0,0</div></div><footer><span>ZOOM ${(this.viewport.zoom * 100).toFixed(0)}%</span><span>${selectedNode ? escapeHtml(selectedNode.type) : 'NO SELECTION'}</span></footer></section>${inspector}</section><footer class="scene-status" role="status"><span class="${state?.repairMode ? 'is-warning' : ''}">${escapeHtml(this.message)}</span><span>${state ? `${state.document.nodes.length} NODES · ${state.document.instances.length} INSTANCES${state.dirty ? ' · UNSAVED' : ''}` : 'AUTHORING SYSTEM READY'}</span></footer>${this.creationSearch !== undefined ? this.renderCreationDialog() : ''}</main>`;
    if (focused) this.container.querySelector<HTMLElement>(focused)?.focus();
  }

  private renderCreationDialog(): string {
    const entries = sceneCreationEntries(this.registry, this.creationSearch);
    return `<div class="scene-dialog-backdrop"><section role="dialog" aria-modal="true" aria-labelledby="scene-create-title" class="scene-create-dialog"><header><div><span>REGISTRY</span><h2 id="scene-create-title">Add a universal node</h2></div><button type="button" data-action="close-create" aria-label="Close creation dialog">×</button></header><label><span>Search registered types</span><input autofocus type="search" data-creation-search value="${escapeHtml(this.creationSearch)}" /></label><div role="listbox">${entries.map((entry) => `<button type="button" role="option" ${entry.kind === 'script' ? `data-create-script-id="${escapeHtml(entry.id)}"` : `data-create-type="${escapeHtml(entry.id)}"`}><span>${entry.kind === 'script' ? 'S' : 'N'}</span><strong>${escapeHtml(entry.label)}</strong><small>${escapeHtml(entry.description)}</small></button>`).join('')}</div></section></div>`;
  }

  private fail(error: unknown): void { this.message = error instanceof Error ? error.message : String(error); this.render(); }
}

export function mountSceneStudio(container: HTMLElement): void { void new SceneStudioController(container).start(); }
