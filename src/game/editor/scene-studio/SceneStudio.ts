import type { DescriptorRegistry } from '../../content/scenes/propertyDescriptors';
import { createGameDescriptorRegistry } from '../../features/scripts/registrations';
import type { TileDataResourceDocument, TileSetResourceDocument } from '../../content/scenes/resources/types';
import type { AuthoredNodeId } from '../../content/scenes/identifiers';
import type { SceneNodeDocument } from '../../content/scenes/types';
import { SceneStudioConflictError, SceneStudioRepository, type SceneStudioContentSummary, type SceneStudioDocument } from '../../infrastructure/scenes/editor/SceneStudioRepository';
import { handleStudioHistoryShortcut } from '../StudioHistoryShortcut';
import { PropertyEditorRegistry } from './PropertyEditorRegistry';
import { sceneCommands } from './SceneCommand';
import { sceneCreationEntries } from './SceneCreationDialog';
import { SceneDocumentState } from './SceneDocumentState';
import { renderSceneInspector, sceneInspectorModel } from './SceneInspector';
import { formatSceneStudioRoute, parseSceneStudioRoute } from './SceneStudioRoute';
import { renderSceneTreePanel, sceneTreeRows, type SceneTreeRow } from './SceneTreePanel';
import { SceneViewportState } from './SceneViewport';
import { createTileLayerDraft, TileMapContext, tileDataResourceId, type TilePaintTool } from './contexts/TileMapContext';

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character] ?? character);
}

interface LoadedTileContext {
  readonly context: TileMapContext;
  readonly relativePath: string;
  tileSetDocument: TileSetResourceDocument;
  hash?: string;
}

function isTileDataDocument(document: SceneStudioDocument): document is TileDataResourceDocument {
  return 'kind' in document && document.kind === 'tile-data';
}

function isTileSetDocument(document: SceneStudioDocument): document is TileSetResourceDocument {
  return 'kind' in document && document.kind === 'tile-set';
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
  private readonly tileContexts = new Map<AuthoredNodeId, LoadedTileContext>();
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
    await this.loadTileContexts(record.document);
    this.selectedKey = `:${record.document.rootNodeId}`;
    this.message = record.repairMode ? `Repair mode · ${record.issues.length} issue${record.issues.length === 1 ? '' : 's'}` : 'Document matches runtime contracts';
    window.history.replaceState(null, '', formatSceneStudioRoute({ active: true, scene: record.document.sceneId }, window.location.search));
    this.render();
  }

  private async save(): Promise<void> {
    if (!this.state || !this.relativePath) return;
    try {
      const writes = [
        ...(this.state.dirty ? [{ kind: 'scene' as const, id: this.state.sceneId, relativePath: this.relativePath, document: this.state.document, expectedHash: this.state.diskHash ?? null }] : []),
        ...[...this.tileContexts.entries()]
          .filter(([nodeId, entry]) => this.state?.document.nodes.some((node) => node.id === nodeId) && (entry.context.dirty || entry.hash === undefined))
          .map(([, entry]) => ({
          kind: 'resource' as const,
          id: entry.context.document.resourceId,
          relativePath: entry.relativePath,
          document: entry.context.document,
          expectedHash: entry.hash ?? null,
        })),
      ];
      if (writes.length === 0) return;
      const results = await this.repository.save(writes);
      for (const result of results) {
        if (result.kind === 'scene') this.state.markSaved(result.hash);
        else {
          const entry = [...this.tileContexts.values()].find((candidate) => candidate.context.document.resourceId === result.id);
          if (entry) { entry.hash = result.hash; entry.context.markSaved(); }
        }
      }
      this.message = 'Committed · disk and editor are synchronized';
    } catch (error) {
      this.message = error instanceof SceneStudioConflictError ? 'Save conflict · reload or preserve your draft before retrying' : error instanceof Error ? error.message : String(error);
    }
    this.render();
  }

  private undo(): boolean {
    const tile = this.selectedTileContext();
    const changed = tile?.context.canUndo ? tile.context.undo() : this.state?.undo() ?? false;
    if (changed) this.message = 'Undid command';
    return changed;
  }

  private redo(): boolean {
    const tile = this.selectedTileContext();
    const changed = tile?.context.canRedo ? tile.context.redo() : this.state?.redo() ?? false;
    if (changed) this.message = 'Redid command';
    return changed;
  }

  private async handleClick(event: Event): Promise<void> {
    const target = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-scene-id],[data-scene-tree-key],[data-action],[data-scene-add],[data-create-type],[data-create-script-id],[data-open-source],[data-node-id],[data-tile-cell],[data-tile-id],[data-tile-tool]') : null;
    if (!target) return;
    const tile = this.selectedTileContext();
    if (target.hasAttribute('data-tile-cell') && tile) {
      try {
        tile.context.paint({ x: Number(target.dataset.x), y: Number(target.dataset.y) });
        this.message = `${tile.context.tool === 'erase' ? 'Erased' : 'Painted'} tile ${target.dataset.x},${target.dataset.y}`;
      } catch (error) { this.message = error instanceof Error ? error.message : String(error); }
      this.render();
      return;
    }
    if (target.dataset.tileId && tile) {
      try { tile.context.selectTile(target.dataset.tileId); this.message = `Brush · ${target.dataset.tileId}`; }
      catch (error) { this.message = error instanceof Error ? error.message : String(error); }
      this.render();
      return;
    }
    if (target.dataset.tileTool && tile) {
      tile.context.selectTool(target.dataset.tileTool as TilePaintTool);
      this.message = `Tile tool · ${target.dataset.tileTool}`;
      this.render();
      return;
    }
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
    else if (target.dataset.action === 'toggle-tile-collision' && tile) { tile.context.toggleCollision(); this.render(); }
    else if (target.dataset.action === 'toggle-effective-region' && tile) { tile.context.toggleEffectiveRegion(); this.render(); }
    else if (target.dataset.action === 'tile-pan-left' && tile) { tile.context.panBy(-8, 0); this.render(); }
    else if (target.dataset.action === 'tile-pan-right' && tile) { tile.context.panBy(8, 0); this.render(); }
    else if (target.dataset.action === 'tile-pan-up' && tile) { tile.context.panBy(0, -6); this.render(); }
    else if (target.dataset.action === 'tile-pan-down' && tile) { tile.context.panBy(0, 6); this.render(); }
    else if (target.dataset.action === 'tile-zoom-in' && tile) { tile.context.setZoom(tile.context.zoom + 0.25); this.render(); }
    else if (target.dataset.action === 'tile-zoom-out' && tile) { tile.context.setZoom(tile.context.zoom - 0.25); this.render(); }
    else if (target.dataset.action === 'tile-layer-up' && tile) { this.reorderSelectedTileLayer(-1); }
    else if (target.dataset.action === 'tile-layer-down' && tile) { this.reorderSelectedTileLayer(1); }
    else if (target.dataset.action === 'add-tile-layer' && tile) { this.addTileLayer(tile); }
    else if (target.dataset.action === 'close-create') { this.creationSearch = undefined; this.render(); }
  }

  private handleChange(event: Event): void {
    if (!this.state || (!(event.target instanceof HTMLInputElement) && !(event.target instanceof HTMLSelectElement) && !(event.target instanceof HTMLTextAreaElement))) return;
    if (event.target.dataset.creationSearch !== undefined) return;
    const tile = this.selectedTileContext();
    if (event.target.dataset.tileBrushSize !== undefined && tile) {
      try { tile.context.setBrushSize(Number(event.target.value)); this.message = `Brush footprint · ${event.target.value}×${event.target.value}`; }
      catch (error) { this.message = error instanceof Error ? error.message : String(error); }
      this.render();
      return;
    }
    if (event.target.dataset.tileSet !== undefined && tile) {
      void this.changeTileSet(tile, event.target.value);
      return;
    }
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

  private async loadTileContexts(document: { readonly nodes: readonly SceneNodeDocument[] }): Promise<void> {
    this.tileContexts.clear();
    for (const node of document.nodes) {
      if (node.type !== 'TileMapLayer2D') continue;
      const dataId = tileDataResourceId(node);
      if (!dataId) throw new Error(`Tile layer '${node.id}' requires an external tileData resource`);
      const dataRecord = await this.repository.load('resource', dataId);
      if (dataRecord.kind !== 'resource' || !isTileDataDocument(dataRecord.document)) {
        throw new Error(`Tile layer '${node.id}' requires tile-data resource '${dataId}'`);
      }
      const tileSetRecord = await this.repository.load('resource', dataRecord.document.tileSet);
      if (tileSetRecord.kind !== 'resource' || !isTileSetDocument(tileSetRecord.document)) {
        throw new Error(`Tile data '${dataId}' requires tile-set resource '${dataRecord.document.tileSet}'`);
      }
      this.tileContexts.set(node.id, {
        context: new TileMapContext(dataRecord.document, tileSetRecord.document),
        relativePath: dataRecord.relativePath,
        tileSetDocument: tileSetRecord.document,
        hash: dataRecord.hash,
      });
    }
  }

  private selectedTileContext(): LoadedTileContext | undefined {
    const selection = this.state?.selection;
    return selection?.kind === 'node' ? this.tileContexts.get(selection.nodeId) : undefined;
  }

  private async changeTileSet(entry: LoadedTileContext, tileSetId: string): Promise<void> {
    try {
      const record = await this.repository.load('resource', tileSetId);
      if (record.kind !== 'resource' || !isTileSetDocument(record.document)) throw new Error(`'${tileSetId}' is not a tile-set resource`);
      entry.context.selectTileSet(record.document);
      entry.tileSetDocument = record.document;
      this.message = `Tile set · ${tileSetId}`;
    } catch (error) { this.message = error instanceof Error ? error.message : String(error); }
    this.render();
  }

  private reorderSelectedTileLayer(offset: number): void {
    const selection = this.state?.selection;
    if (!this.state || selection?.kind !== 'node') return;
    const node = this.state.document.nodes.find((candidate) => candidate.id === selection.nodeId);
    if (!node?.parentId) return;
    this.state.execute(sceneCommands.reorderNode(node.id, node.order + offset));
    this.message = `Moved ${node.name} ${offset < 0 ? 'up' : 'down'}`;
    this.render();
  }

  private addTileLayer(source: LoadedTileContext): void {
    if (!this.state) return;
    const document = this.state.document;
    const selection = this.state.selection;
    if (selection.kind !== 'node') return;
    const sourceNode = document.nodes.find((node) => node.id === selection.nodeId);
    if (!sourceNode?.parentId) return;
    let sequence = 1;
    let nodeId = `layer-overlay-${sequence}`;
    while (document.nodes.some((node) => node.id === nodeId)) nodeId = `layer-overlay-${++sequence}`;
    const tileSize = typeof sourceNode.properties.tileSize === 'number' ? sourceNode.properties.tileSize : 64;
    const seed = typeof sourceNode.properties.seed === 'number' ? sourceNode.properties.seed : 1;
    const draft = createTileLayerDraft({
      sceneId: document.sceneId,
      nodeId,
      name: `overlay-${sequence}`,
      parentId: sourceNode.parentId,
      order: sourceNode.order + 1,
      columns: source.context.document.columns,
      rows: source.context.document.rows,
      tileSize,
      tileSet: source.context.document.tileSet,
      seed,
    });
    this.state.execute(sceneCommands.addNode(draft.node));
    this.tileContexts.set(draft.node.id, {
      context: new TileMapContext(draft.data, source.tileSetDocument),
      relativePath: draft.relativePath,
      tileSetDocument: source.tileSetDocument,
    });
    if (!this.catalog.some((item) => item.kind === 'resource' && item.id === draft.data.resourceId)) {
      this.catalog = [...this.catalog, { kind: 'resource' as const, id: draft.data.resourceId, relativePath: draft.relativePath }]
        .sort((left, right) => left.relativePath.localeCompare(right.relativePath));
    }
    this.selectedKey = `:${draft.node.id}`;
    this.state.select({ kind: 'node', nodeId: draft.node.id });
    this.message = `Added tile layer ${draft.node.name}`;
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
    const tile = selectedNode ? this.tileContexts.get(selectedNode.id) : undefined;
    const baseInspector = selectedNode ? renderSceneInspector(sceneInspectorModel(selectedNode, this.registry)) : '<aside class="scene-inspector scene-empty"><span>INSPECTOR</span><p>Select a local node to inspect its authored properties.</p></aside>';
    const inspector = tile && selectedNode
      ? baseInspector.replace('</aside>', `${renderTileMapTools(tile.context, this.tileSetSummaries())}</aside>`)
      : baseInspector;
    const viewportNodes = state ? this.viewport.nodes(state.document.nodes) : [];
    const activeTileIds = new Set(state?.document.nodes.filter((node) => node.type === 'TileMapLayer2D').map((node) => node.id) ?? []);
    const dirty = Boolean(state?.dirty || [...this.tileContexts.entries()].some(([nodeId, entry]) => activeTileIds.has(nodeId) && (entry.context.dirty || entry.hash === undefined)));
    const canUndo = Boolean(tile?.context.canUndo || state?.canUndo);
    const canRedo = Boolean(tile?.context.canRedo || state?.canRedo);
    const hasUiLayout = viewportNodes.some((node) => node.kind === 'ui');
    const viewport = tile && selectedNode
      ? renderTileMapViewport(tile.context, selectedNode)
      : hasUiLayout
        ? renderUiLayoutViewport(viewportNodes.filter((node) => node.kind === 'ui'), selectedNode)
        : `<section class="scene-viewport" aria-label="2D viewport"><div class="scene-grid" style="--scene-zoom:${this.viewport.zoom}">${viewportNodes.map((node) => `<button type="button" class="scene-viewport-node${node.selected ? ' is-selected' : ''}" style="--x:${node.position[0]};--y:${node.position[1]}" data-node-id="${escapeHtml(node.id)}" aria-label="Select ${escapeHtml(node.name)}"><span>${escapeHtml(node.name)}</span></button>`).join('')}<div class="scene-origin">0,0</div></div><footer><span>ZOOM ${(this.viewport.zoom * 100).toFixed(0)}%</span><span>${selectedNode ? escapeHtml(selectedNode.type) : 'NO SELECTION'}</span></footer></section>`;
    this.container.innerHTML = `<main class="scene-studio" data-scene-studio><header class="scene-topbar"><div><span>FIELD CARTOGRAPHER / UNIVERSAL GRAPH</span><h1>Scene Studio</h1></div><div class="scene-command-bar"><button type="button" data-action="undo" ${!canUndo ? 'disabled' : ''}>Undo</button><button type="button" data-action="redo" ${!canRedo ? 'disabled' : ''}>Redo</button><button type="button" class="scene-save" data-action="save" ${!dirty ? 'disabled' : ''}>${dirty ? 'Save changes' : 'Saved'}</button></div></header><aside class="scene-explorer" aria-label="Project explorer"><label><span>EXPEDITION INDEX</span><input type="search" placeholder="Filter scenes and resources" aria-label="Filter scenes and resources" /></label><nav aria-label="Scenes"><h2>Scenes <em>${scenes.length}</em></h2>${scenes.map((item) => `<button type="button" data-scene-id="${escapeHtml(item.id)}" class="${item.id === state?.sceneId ? 'is-current' : ''}"><span>◫</span><strong>${escapeHtml(item.id)}</strong></button>`).join('') || '<p>No scene documents</p>'}<h2>Resources <em>${resources.length}</em></h2>${resources.map((item) => `<div class="scene-resource-row"><span>◈</span>${escapeHtml(item.id)}<small>${escapeHtml(item.relativePath)}</small></div>`).join('') || '<p>No external resources</p>'}</nav></aside><section class="scene-workbench">${state ? renderSceneTreePanel(this.rows, this.selectedKey) : '<section class="scene-tree-panel scene-empty"><p>Open a scene to reveal its graph.</p></section>'}${viewport}${inspector}</section><footer class="scene-status" role="status"><span class="${state?.repairMode ? 'is-warning' : ''}">${escapeHtml(this.message)}</span><span>${state ? `${state.document.nodes.length} NODES · ${state.document.instances.length} INSTANCES${dirty ? ' · UNSAVED' : ''}` : 'AUTHORING SYSTEM READY'}</span></footer>${this.creationSearch !== undefined ? this.renderCreationDialog() : ''}</main>`;
    if (focused) this.container.querySelector<HTMLElement>(focused)?.focus();
  }

  private renderCreationDialog(): string {
    const entries = sceneCreationEntries(this.registry, this.creationSearch);
    return `<div class="scene-dialog-backdrop"><section role="dialog" aria-modal="true" aria-labelledby="scene-create-title" class="scene-create-dialog"><header><div><span>REGISTRY</span><h2 id="scene-create-title">Add a universal node</h2></div><button type="button" data-action="close-create" aria-label="Close creation dialog">×</button></header><label><span>Search registered types</span><input autofocus type="search" data-creation-search value="${escapeHtml(this.creationSearch)}" /></label><div role="listbox">${entries.map((entry) => `<button type="button" role="option" ${entry.kind === 'script' ? `data-create-script-id="${escapeHtml(entry.id)}"` : `data-create-type="${escapeHtml(entry.id)}"`}><span>${entry.kind === 'script' ? 'S' : 'N'}</span><strong>${escapeHtml(entry.label)}</strong><small>${escapeHtml(entry.description)}</small></button>`).join('')}</div></section></div>`;
  }

  private fail(error: unknown): void { this.message = error instanceof Error ? error.message : String(error); this.render(); }

  private tileSetSummaries(): readonly SceneStudioContentSummary[] {
    return this.catalog.filter((item) => item.kind === 'resource' && item.relativePath.endsWith('.tile-set.resource.json'));
  }
}

function renderUiLayoutViewport(nodes: readonly ReturnType<SceneViewportState['nodes']>[number][], selectedNode?: SceneNodeDocument): string {
  const controls = nodes.map((node) => {
    const width = node.size?.[0] ?? 0;
    const height = node.size?.[1] ?? 0;
    return `<button type="button" class="scene-ui-layout-node${node.selected ? ' is-selected' : ''}" style="--ui-x:${node.position[0]};--ui-y:${node.position[1]};--ui-w:${width};--ui-h:${height}" data-node-id="${escapeHtml(node.id)}" aria-label="Select ${escapeHtml(node.name)}"><span>${escapeHtml(node.name)}</span><small>${escapeHtml(node.type)}</small></button>`;
  }).join('');
  return `<section class="scene-viewport scene-ui-viewport" aria-label="UI layout viewport"><div class="scene-ui-canvas">${controls}</div><footer><span>LAYOUT 1280 × 720</span><span>${selectedNode ? escapeHtml(selectedNode.type) : 'UI CONTEXT'}</span></footer></section>`;
}

function renderTileMapTools(context: TileMapContext, tileSets: readonly SceneStudioContentSummary[]): string {
  const region = context.effectiveRegion;
  const tileSetOptions = tileSets.map((item) => `<option value="${escapeHtml(item.id)}" ${item.id === context.tileSet.resourceId ? 'selected' : ''}>${escapeHtml(item.id)}</option>`).join('');
  return `<section class="scene-tile-tools" aria-label="Tile map tools"><header><span>TILE MAP CONTEXT</span><strong>${context.document.columns} × ${context.document.rows}</strong></header><div class="scene-tile-tool-row" role="toolbar" aria-label="Tile paint tools">${(['brush', 'erase', 'fill'] as const).map((tool) => `<button type="button" data-tile-tool="${tool}" aria-pressed="${context.tool === tool}">${tool}</button>`).join('')}</div><label class="scene-tile-field"><span>Brush footprint</span><select data-tile-brush-size><option value="1" ${context.brushSize === 1 ? 'selected' : ''}>1 × 1</option><option value="3" ${context.brushSize === 3 ? 'selected' : ''}>3 × 3</option><option value="5" ${context.brushSize === 5 ? 'selected' : ''}>5 × 5</option></select></label><label class="scene-tile-field"><span>Tile set</span><select data-tile-set>${tileSetOptions}</select></label><div class="scene-tile-palette" aria-label="Tile palette">${Object.entries(context.tileSet.tiles).map(([tileId, tile]) => `<button type="button" data-tile-id="${escapeHtml(tileId)}" class="${context.selectedTile === tileId ? 'is-selected' : ''}"><strong>${escapeHtml(tileId)}</strong><small>${tile.physics ? 'solid' : 'walkable'}</small></button>`).join('')}</div><div class="scene-tile-toggle-row"><button type="button" data-action="toggle-tile-collision" aria-pressed="${context.showCollision}">Collision</button><button type="button" data-action="toggle-effective-region" aria-pressed="${context.showEffectiveRegion}">Effective region</button></div><div class="scene-tile-layer-row"><button type="button" data-action="tile-layer-up">Layer ↑</button><button type="button" data-action="tile-layer-down">Layer ↓</button><button type="button" data-action="add-tile-layer">+ Layer</button></div><p>${region ? `Effective cells ${region.minX},${region.minY} → ${region.maxX},${region.maxY}` : 'Layer is empty'} · snap grid follows authored tile size.</p></section>`;
}

function renderTileMapViewport(context: TileMapContext, node: SceneNodeDocument): string {
  const document = context.document;
  const visibleColumns = Math.min(24, document.columns);
  const visibleRows = Math.min(18, document.rows);
  const startX = Math.min(context.pan.x, Math.max(0, document.columns - visibleColumns));
  const startY = Math.min(context.pan.y, Math.max(0, document.rows - visibleRows));
  const cells = new Map(context.cells.map((cell) => [`${cell.x},${cell.y}`, cell.tileId]));
  const region = context.effectiveRegion;
  const buttons: string[] = [];
  for (let y = startY; y < startY + visibleRows; y += 1) {
    for (let x = startX; x < startX + visibleColumns; x += 1) {
      const tileId = cells.get(`${x},${y}`);
      const collision = context.showCollision && context.isCollisionCell({ x, y });
      const effective = context.showEffectiveRegion && region && x >= region.minX && x <= region.maxX && y >= region.minY && y <= region.maxY;
      buttons.push(`<button type="button" data-tile-cell data-x="${x}" data-y="${y}" class="scene-tile-cell${tileId ? ' is-painted' : ''}${collision ? ' is-collision' : ''}${effective ? ' is-effective' : ''}" aria-label="Cell ${x},${y}${tileId ? ` ${escapeHtml(tileId)}` : ' empty'}"><span>${tileId ? escapeHtml(tileId.slice(0, 2).toUpperCase()) : ''}</span></button>`);
    }
  }
  const tileSize = typeof node.properties.tileSize === 'number' ? node.properties.tileSize : 64;
  return `<section class="scene-viewport scene-tile-viewport" aria-label="Tile map viewport"><header class="scene-tile-viewport-nav"><div><button type="button" data-action="tile-pan-left" aria-label="Pan left">←</button><button type="button" data-action="tile-pan-up" aria-label="Pan up">↑</button><button type="button" data-action="tile-pan-down" aria-label="Pan down">↓</button><button type="button" data-action="tile-pan-right" aria-label="Pan right">→</button></div><div><button type="button" data-action="tile-zoom-out" aria-label="Zoom out">−</button><button type="button" data-action="tile-zoom-in" aria-label="Zoom in">+</button></div></header><div class="scene-tile-canvas" style="--tile-columns:${visibleColumns};--tile-zoom:${context.zoom}">${buttons.join('')}</div><footer><span>CELLS ${startX},${startY} → ${startX + visibleColumns - 1},${startY + visibleRows - 1}</span><span>SNAP ${tileSize}px · ZOOM ${(context.zoom * 100).toFixed(0)}%</span></footer></section>`;
}

export function mountSceneStudio(container: HTMLElement): void { void new SceneStudioController(container).start(); }
