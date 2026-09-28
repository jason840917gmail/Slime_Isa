import { sceneDocuments, sceneResourceDocuments } from 'virtual-scene-content';

import { propertiesForNode, type DescriptorRegistry } from '../../content/scenes/propertyDescriptors';
import { createGameDescriptorRegistry } from '../../features/scripts/registrations';
import type {
  AnimationLibraryResourceDocument,
  CollisionShapeResourceDocument,
  CollisionShapeValue,
  TileDataResourceDocument,
  TileSetResourceDocument,
} from '../../content/scenes/resources/types';
import { authoredNodeId, instanceId as toInstanceId, persistenceKey as toPersistenceKey, resourceId as toResourceId, runtimeNodeId, sceneId as toSceneId, type AuthoredNodeId, type InstanceId, type ResourceId, type SceneId } from '../../content/scenes/identifiers';
import type { JsonValue, SceneDocument, SceneNodeDocument, SceneOverrideDocument, SceneResourceDocument } from '../../content/scenes/types';
import { ASSET_MANIFEST } from '../../infrastructure/assets/manifest';
import { SceneStudioConflictError, SceneStudioRepository, type SceneStudioContentSummary, type SceneStudioDocument } from '../../infrastructure/scenes/editor/SceneStudioRepository';
import { handleStudioHistoryShortcut } from '../StudioHistoryShortcut';
import { animationTargets } from './animation/AnimationTargets';
import { AnimationTimelinePanel, type AnimationEditorContext, type AnimationLibraryChange } from './animation/AnimationTimelinePanel';
import { readAnimationValue, type AnimationValueKind } from './animation/AnimationValueFields';
import { attackPlanOwner, type AttackPlans } from './animation/WeaponAttackLanes';
import { PropertyEditorRegistry } from './PropertyEditorRegistry';
import { resourceConsumers } from './ResourceBrowser';
import { SceneClipboard } from './SceneClipboard';
import { sceneCommands, sceneMutationCommand } from './SceneCommand';
import { sceneCreationEntries } from './SceneCreationDialog';
import { buildExplorerTree, explorerFolderKeysFor, renderExplorerTree, SCENE_DRAG_TYPE } from './ExplorerTree';
import { SceneDocumentState } from './SceneDocumentState';
import { ResourceDocumentState } from './ResourceDocumentState';
import { renderSceneInspector, sceneInspectorModel, type InspectorProperty, type SceneInspectorModel } from './SceneInspector';
import { applyJsonFormEdit, jsonFormFor, renderJsonForm, validateJsonForm, type FormOption, type FormOptions, type JsonFormContext, type JsonFormEdit, type JsonPath } from './JsonPropertyForms';
import { getBaseItemDefinitions, getKnownItemIds } from '../../content/items/ItemCatalog';
import { getNpcDefinition } from '../../content/npcs/NpcCatalog';
import { getObjectArchetype, getObjectArchetypeIds, isObjectArchetypeId } from '../../content/objects/ObjectCatalog';
import { getEffectDefinitions } from '../../content/effects/EffectCatalog';
import { getProjectileDefinitions } from '../../content/projectiles/ProjectileCatalog';
import { RESOURCE_TAGS } from '../../content/ResourceTags';
import { SceneLiveViewport, type LiveViewportBoundsGuide, type LiveViewportMarker, type LiveViewportModel, type LiveViewportShape } from './SceneLiveViewport';
import { resolveSourceBoundsFromWorld, resolveWorldOcclusionRectangle, type SourceOcclusionBounds } from '../../presentation/WorldOcclusion';
import type { SpriteBoundsGeometry } from '../../infrastructure/phaser-nodes/Sprite2DNode';
import { ScenePreview } from './ScenePreview';
import { formatSceneStudioRoute, parseSceneStudioRoute } from './SceneStudioRoute';
import { renderSceneTreePanel, sceneTreeRows, type SceneTreeRow } from './SceneTreePanel';
import {
  composeSceneNodes,
  composedBounds,
  localPositionFor,
  SceneViewportState,
  unionRects,
  type ComposedSceneNode,
  type ViewportCamera,
  type WorldRect,
} from './SceneViewport';
import { collisionShapeGuide, editCollisionShape } from './ShapeEditor';
import { transformNodeCommand, validateViewportTransform } from './ViewportSelection';
import { bossCampShapeRoles, bossCampSummary, bossSceneIdOf, bossSceneInfo, bossSpawnPoint, isBossCampScript, owningBossCamp, type BossSceneInfo } from './BossCampStudio';
import { ENEMY_TYPE_IDS } from '../../enemies/library/EnemyTypes';
import { convertShapeKind, editAreaSettings, spawnSettings, isWorldAreaScript, owningWorldArea, referencedNodeKey, WORLD_AREA_TEMPLATES, worldAreaShapeKeys, worldAreaShapeRoles, worldAreaSummary, worldAreaTemplateCommand, type WorldAreaTemplateKind } from './WorldAreaStudio';
import { createTileLayerDraft, TileMapContext, tileDataResourceId, type TilePaintTool } from './contexts/TileMapContext';
import type { StudioPreviewState, StudioScenePreview } from './preview/StudioScenePreview';

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character] ?? character);
}

interface LoadedTileContext {
  readonly context: TileMapContext;
  /** Standalone tile-data file; undefined when the layer's data is embedded in the scene. */
  readonly relativePath?: string;
  tileSetDocument: TileSetResourceDocument;
  hash?: string;
}

/** Unsaved paint strokes, or a standalone tile-data file that was never written. */
function tileContextUnsaved(entry: LoadedTileContext): boolean {
  return entry.context.dirty || (entry.relativePath !== undefined && entry.hash === undefined);
}

/** The scene document with its embedded tile layers replaced by their live paint state. */
function withEmbeddedTileData(document: SceneDocument, tiles: readonly TileDataResourceDocument[]): SceneDocument {
  if (tiles.length === 0) return document;
  const byId = new Map(tiles.map((tile) => [tile.resourceId, tile]));
  return { ...document, subresources: (document.subresources ?? []).map((resource) => byId.get(resource.resourceId) ?? resource) };
}

interface LoadedShapeResource {
  readonly state: ResourceDocumentState;
  readonly relativePath: string;
}

/**
 * One open document tab, like Godot's scene tabs. The controller's live fields
 * mirror the active tab; `stashActiveTab` writes them back before switching.
 */
interface StudioTab {
  readonly key: string;
  readonly kind: 'scene' | 'resource';
  readonly id: string;
  state: SceneDocumentState | undefined;
  resourceState: ResourceDocumentState | undefined;
  relativePath: string | undefined;
  resourceRelativePath: string | undefined;
  selectedKey: string | undefined;
  expanded: Set<string>;
  tileContexts: Map<AuthoredNodeId, LoadedTileContext>;
  shapeResources: Map<ResourceId, LoadedShapeResource>;
  lastShapeEdit: ResourceId | undefined;
  animationPlayerKey: string | undefined;
  animationClosedAt: string | undefined;
  camera: ViewportCamera | undefined;
  message: string;
}

function tabDirty(tab: StudioTab): boolean {
  const layers = new Set(tab.state?.document.nodes.filter((node) => node.type === 'TileMapLayer2D').map((node) => node.id) ?? []);
  return Boolean(tab.state?.dirty || (tab.state && tab.state.diskHash === undefined) || tab.resourceState?.dirty
    || [...tab.shapeResources.values()].some((entry) => entry.state.dirty)
    || [...tab.tileContexts.entries()].some(([nodeId, entry]) => layers.has(nodeId) && tileContextUnsaved(entry)));
}

/** Tab label: the file name without its document suffix, as Godot shows `name.tscn`. */
function tabLabel(tab: StudioTab): string {
  const path = tab.relativePath ?? tab.resourceRelativePath;
  return path ? path.slice(path.lastIndexOf('/') + 1).replace(/\.(?:scene|resource)\.json$/, '') : tab.id;
}

/** State of the open "New scene" / "New folder" dialog (Godot's FileSystem dock actions). */
interface FileDialogState {
  readonly mode: 'scene' | 'folder';
  /** Folder the new item goes in; '' is the content root. */
  parent: string;
  name: string;
  /** Scene ID; follows the name until the author edits it. */
  sceneId: string;
  sceneIdEdited: boolean;
  rootType: string;
  error?: string;
}

const FILE_NAME_PATTERN = /^[a-z0-9]+(?:[._-][a-z0-9]+)*$/;
/** Root types offered first in the New scene dialog, as Godot's "Create Root Node" does. */
const COMMON_ROOT_TYPES = ['Node2D', 'CharacterBody2D', 'StaticBody2D', 'Area2D', 'Control', 'Node'];

/** `object.chest-wooden` style ID: the prefix sibling scenes share, else the singular folder name. */
function suggestedSceneId(parent: string, name: string, catalog: readonly SceneStudioContentSummary[]): string {
  const siblings = catalog.filter((item) => item.kind === 'scene' && item.relativePath.slice(0, Math.max(0, item.relativePath.lastIndexOf('/'))) === parent);
  const prefixes = new Set(siblings.map((item) => item.id.includes('.') ? item.id.slice(0, item.id.indexOf('.')) : ''));
  const shared = prefixes.size === 1 ? [...prefixes][0] : undefined;
  const top = parent.split('/')[0] ?? '';
  const prefix = shared ?? (top.endsWith('s') ? top.slice(0, -1) : top);
  return prefix && name ? `${prefix}.${name}` : name;
}

/** PascalCase node name for a new scene's root, e.g. `chest-wooden` -> `ChestWooden`. */
function rootNodeName(name: string): string {
  return name.split(/[._-]/).filter(Boolean).map((part) => part[0].toUpperCase() + part.slice(1)).join('') || 'Root';
}

/** True when `document` is `target` or instances it at any depth (instancing it would recurse). */
function sceneContains(document: SceneDocument, target: SceneId, resolve: (sceneId: SceneId) => SceneDocument | undefined, visited = new Set<SceneId>()): boolean {
  if (document.sceneId === target) return true;
  if (visited.has(document.sceneId)) return false;
  visited.add(document.sceneId);
  return document.instances.some((instance) => {
    if (instance.sceneId === target) return true;
    const source = resolve(instance.sceneId);
    return source ? sceneContains(source, target, resolve, visited) : false;
  });
}

/** What the inspector edits: a local node, or an instanced node through overrides. */
interface InspectorTarget {
  readonly node: SceneNodeDocument;
  readonly composed?: ComposedSceneNode;
  readonly mode: 'local' | 'override' | 'read-only';
  readonly instanceId?: InstanceId;
  readonly sourceInstancePath?: readonly InstanceId[];
}

const PREVIEW_SCENE_ID = toSceneId('studio.resource-preview');
const PREVIEW_DEBOUNCE_MS = 120;

function isTileDataDocument(document: SceneStudioDocument): document is TileDataResourceDocument {
  return 'kind' in document && document.kind === 'tile-data';
}

function isTileSetDocument(document: SceneStudioDocument): document is TileSetResourceDocument {
  return 'kind' in document && document.kind === 'tile-set';
}

/** Script references that point at areas which deal damage; their shapes show in the warning colour. */
const ATTACK_AREA_REFERENCES = ['attackArea', 'contactAttack', 'landingZone'] as const;

function referencedResourceId(value: JsonValue | undefined): ResourceId | undefined {
  if (value === null || value === undefined || Array.isArray(value) || typeof value !== 'object') return undefined;
  const id = (value as Readonly<Record<string, JsonValue>>).resourceId;
  return typeof id === 'string' ? toResourceId(id) : undefined;
}

function isEditableTarget(element: EventTarget | null): boolean {
  return element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement || element instanceof HTMLSelectElement;
}

export class SceneStudioController {
  private readonly abort = new AbortController();
  private readonly propertyEditors = new PropertyEditorRegistry();
  private readonly viewport = new SceneViewportState();
  private readonly clipboard = new SceneClipboard();
  private readonly library = new Map<SceneId, SceneDocument>();
  private readonly externalResources = new Map<ResourceId, SceneResourceDocument>();
  private expanded = new Set<string>();
  private readonly tabs: StudioTab[] = [];
  private activeTabKey?: string;
  /** Bumped whenever a library scene changes so compositions that instance it refresh. */
  private libraryRevision = 0;
  private catalog: readonly SceneStudioContentSummary[] = [];
  /** Every folder under the content root, including empty ones. */
  private folders: readonly string[] = [];
  private fileDialog?: FileDialogState;
  /** JSON properties unlocked with "Edit JSON", keyed by node key and property: the draft text and its last error. */
  private readonly jsonDrafts = new Map<string, { draft: string; error?: string }>();
  private state?: SceneDocumentState;
  private resourceState?: ResourceDocumentState;
  private resourceRelativePath?: string;
  private relativePath?: string;
  private selectedKey?: string;
  private rows: readonly SceneTreeRow[] = [];
  private tileContexts = new Map<AuthoredNodeId, LoadedTileContext>();
  private shapeResources = new Map<ResourceId, LoadedShapeResource>();
  private lastShapeEdit?: ResourceId;
  private message = 'Loading authored content…';
  private creationSearch?: string;
  /** Search text of the open "Instance child scene" dialog; undefined while closed. */
  private instanceSearch?: string;
  private explorerFilter = '';
  /** Explorer folder keys the author expanded; everything else starts collapsed. */
  private readonly explorerOpen = new Set<string>();
  /** Folder the author last opened or closed; default parent for new scenes and folders. */
  private explorerFolder?: string;
  private composedCache?: { readonly signature: string; readonly nodes: readonly ComposedSceneNode[]; readonly byKey: ReadonlyMap<string, ComposedSceneNode> };
  private posedCache?: { readonly signature: string; readonly nodes: readonly ComposedSceneNode[]; readonly byKey: ReadonlyMap<string, ComposedSceneNode> };
  private liveViewport?: SceneLiveViewport;
  private preview?: StudioScenePreview;
  private previewSession?: ScenePreview;
  private previewSignature?: string;
  private previewTimer?: ReturnType<typeof setTimeout>;
  private framedFor?: string;
  private readonly animationPanel: AnimationTimelinePanel;
  /** The AnimationPlayer pinned in the dock; it stays while other nodes are selected, like Godot. */
  private animationPlayerKey?: string;
  /** Selection at which the dock was closed; it reopens when a player is selected again. */
  private animationClosedAt?: string;
  private animationBinding?: { readonly playerNodeId: AuthoredNodeId; readonly libraryId: ResourceId; readonly ownerNodeId?: AuthoredNodeId; readonly attackAreaKey?: string; readonly runtimeId: string; readonly sourceSceneId: SceneId };

  constructor(
    private readonly container: HTMLElement,
    private readonly repository: SceneStudioRepository = new SceneStudioRepository(),
    private readonly registry: DescriptorRegistry = createGameDescriptorRegistry(),
  ) {
    for (const document of sceneDocuments) this.library.set(document.sceneId, document);
    for (const resource of sceneResourceDocuments) this.externalResources.set(resource.resourceId, resource);
    this.animationPanel = new AnimationTimelinePanel({
      commit: (label, change) => this.commitAnimation(label, change),
      notify: (message) => { this.message = message; this.render(); },
      pose: (clip, frame) => Boolean(this.animationBinding && this.preview?.poseAnimation(this.animationBinding.runtimeId, clip, frame)),
      play: (clip, frame) => Boolean(this.animationBinding && this.preview?.playAnimationFrom(this.animationBinding.runtimeId, clip, frame)),
      pause: () => this.preview?.pauseAnimation(),
      stop: () => this.preview?.stopAnimation(),
      previewState: () => this.preview?.animationState,
      onionSkin: (frames) => { if (frames.length > 0) this.preview?.showOnionSkin(frames); else this.preview?.clearOnionSkin(); },
      spriteFrames: (texture) => this.spriteFrames(texture),
      openScene: (sceneId) => { void this.open(sceneId).catch((error: unknown) => this.fail(error)); },
      selectNode: (nodeKey) => this.selectFromViewport(nodeKey),
      playheadChanged: () => { this.liveViewport?.update(this.viewportModel()); this.refreshKeyframeSection(); },
      close: () => { this.animationClosedAt = this.selectedKey; this.animationPlayerKey = undefined; this.render(); },
    });
  }

  async start(): Promise<void> {
    this.bind();
    await this.createViewport();
    this.render();
    try {
      const index = await this.repository.index();
      this.catalog = index.items;
      this.folders = index.folders;
      const route = parseSceneStudioRoute(window.location.search);
      if (route.resource) await this.openResource(route.resource);
      else if (route.scene) await this.open(route.scene);
      else { this.message = this.catalog.length > 0 ? 'Choose a scene from the expedition index.' : 'No authored scenes yet. Conversion outputs will appear here.'; this.render(); }
    } catch (error) { this.fail(error); }
  }

  destroy(): void {
    this.abort.abort();
    if (this.previewTimer) clearTimeout(this.previewTimer);
    this.previewSession?.close();
    this.animationPanel.destroy();
    this.preview?.destroy();
    this.liveViewport?.destroy();
    this.container.replaceChildren();
  }

  /** Diagnostic surface for browser tests and the dev console. */
  get diagnostics(): { readonly preview?: StudioPreviewState; readonly camera?: ViewportCamera; readonly markers: number; readonly pickables: number; readonly renderedNodes: number } {
    const model = this.viewportModel();
    return { ...(this.preview ? { preview: this.preview.state } : {}), ...(this.liveViewport ? { camera: this.liveViewport.camera } : {}), markers: model.markers.length, pickables: model.pickables.length, renderedNodes: this.preview?.nodeBounds().size ?? 0 };
  }

  private async createViewport(): Promise<void> {
    try {
      const { StudioScenePreview } = await import('./preview/StudioScenePreview');
      this.preview = new StudioScenePreview({
        registry: this.registry,
        content: {
          scenes: () => [...this.library.values()],
          resources: () => [...this.externalResources.values()],
        },
        onChange: (state) => this.previewChanged(state),
      });
      this.previewSession = new ScenePreview(this.preview);
    } catch (error) {
      console.error('[SceneStudio] embedded preview unavailable', error);
      this.message = `Preview unavailable · ${error instanceof Error ? error.message : String(error)}`;
    }
    this.liveViewport = new SceneLiveViewport(this.preview?.element, {
      select: (key) => this.selectFromViewport(key),
      moveMarker: (key, global) => this.moveFromViewport(key, global),
      rotateMarker: (key, rotation) => this.rotateFromViewport(key, rotation),
      paintCell: (cell) => this.paintFromViewport(cell),
      editShape: (key, value) => { void this.editShapeFromViewport(key, value); },
      editBounds: (key, property, change) => this.editBoundsFromViewport(key, property, change),
      cameraChanged: (camera) => this.preview?.setCamera(camera),
      dropScene: (sceneId, global) => { void this.instantiateScene(sceneId, { global }); },
    });
  }

  private bind(): void {
    const signal = this.abort.signal;
    this.container.addEventListener('click', (event) => { void this.handleClick(event); }, { signal });
    this.container.addEventListener('change', (event) => this.handleChange(event), { signal });
    this.container.addEventListener('input', (event) => {
      if (event.target instanceof HTMLElement && event.target.dataset.fileField !== undefined) { this.updateFileDialogField(event.target); return; }
      if (event.target instanceof HTMLTextAreaElement && event.target.dataset.jsonSource) {
        const entry = this.jsonDrafts.get(this.jsonDraftKey(event.target.dataset.jsonSource));
        if (entry) entry.draft = event.target.value;
        return;
      }
      if (!(event.target instanceof HTMLInputElement)) return;
      if (event.target.dataset.explorerFilter !== undefined) { this.explorerFilter = event.target.value; this.applyExplorerFilter(); return; }
      if (event.target.dataset.instanceSearch !== undefined) { this.instanceSearch = event.target.value; this.render(); return; }
      if (event.target.dataset.creationSearch === undefined) return;
      this.creationSearch = event.target.value;
      this.render();
    }, { signal });
    this.container.addEventListener('submit', (event) => {
      if (!(event.target instanceof HTMLFormElement) || event.target.dataset.fileDialog === undefined) return;
      event.preventDefault();
      void this.submitFileDialog();
    }, { signal });
    this.bindSceneDrag(signal);
    this.container.addEventListener('auxclick', (event) => {
      const tab = event.button === 1 && event.target instanceof Element ? event.target.closest<HTMLElement>('[data-tab-key]') : null;
      if (tab?.dataset.tabKey) { event.preventDefault(); this.closeTab(tab.dataset.tabKey); }
    }, { signal });
    this.container.addEventListener('dblclick', (event) => {
      // Double-clicking an instance opens its source scene in a tab, like Godot's "Open in Editor".
      const key = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-scene-tree-key]')?.dataset.sceneTreeKey : undefined;
      const row = key ? this.rows.find((candidate) => candidate.key === key) : undefined;
      if (row?.kind === 'instance') void this.open(row.sceneId).catch((error: unknown) => this.fail(error));
    }, { signal });
    this.container.addEventListener('keydown', (event) => {
      if (!(event.target instanceof HTMLElement) || event.target.getAttribute('role') !== 'treeitem') return;
      if (['ArrowRight', 'ArrowLeft'].includes(event.key)) {
        const key = event.target.dataset.sceneTreeKey;
        const row = this.rows.find((candidate) => candidate.key === key);
        if (row?.kind === 'instance' && row.expandable && (event.key === 'ArrowRight') !== Boolean(row.expanded)) {
          event.preventDefault();
          this.toggleExpanded(row.key);
        }
        return;
      }
      if (!['ArrowDown', 'ArrowUp'].includes(event.key)) return;
      const rows = [...this.container.querySelectorAll<HTMLElement>('[role="treeitem"]')];
      const current = rows.indexOf(event.target);
      const next = rows[current + (event.key === 'ArrowDown' ? 1 : -1)];
      if (!next) return;
      event.preventDefault();
      next.focus();
      next.click();
    }, { signal });
    window.addEventListener('keydown', (event) => {
      if ((this.state || this.resourceState) && handleStudioHistoryShortcut(event, () => this.undo(), () => this.redo())) { this.render(); return; }
      if (event.key === 'Escape' && (this.creationSearch !== undefined || this.instanceSearch !== undefined || this.fileDialog)) { this.creationSearch = undefined; this.instanceSearch = undefined; this.fileDialog = undefined; this.render(); return; }
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's' && !this.fileDialog && (this.state || this.resourceState)) { event.preventDefault(); void this.save(); return; }
      if (!this.state || isEditableTarget(event.target) || this.creationSearch !== undefined || this.instanceSearch !== undefined || this.fileDialog) return;
      // The animation dock handles its own clipboard and delete keys for keys and events.
      if (event.target instanceof Node && this.animationPanel.element.contains(event.target)) return;
      const inStudio = event.target instanceof Node && (this.container.contains(event.target) || event.target === document.body);
      if (!inStudio) return;
      const modifier = event.ctrlKey || event.metaKey;
      if (modifier && event.shiftKey && event.key.toLowerCase() === 'a') { event.preventDefault(); this.instanceSearch = ''; this.render(); }
      else if (modifier && event.key.toLowerCase() === 'c') { if (this.copySelection()) event.preventDefault(); }
      else if (modifier && event.key.toLowerCase() === 'v') { if (this.pasteClipboard()) event.preventDefault(); }
      else if (modifier && event.key.toLowerCase() === 'd') { event.preventDefault(); if (this.copySelection()) this.pasteClipboard(); }
      else if (event.key === 'Delete') { if (this.deleteSelection()) event.preventDefault(); }
    }, { signal });
  }

  /** Explorer scene rows drag into the scene tree (as children of the row under the cursor) or the viewport. */
  private bindSceneDrag(signal: AbortSignal): void {
    const clearTargets = (): void => { for (const element of this.container.querySelectorAll('.is-drop-target')) element.classList.remove('is-drop-target'); };
    const treePanel = (event: DragEvent): Element | null => event.target instanceof Element ? event.target.closest('.scene-tree-panel') : null;
    this.container.addEventListener('dragstart', (event) => {
      const item = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-scene-id][draggable="true"]') : null;
      if (!item?.dataset.sceneId || !event.dataTransfer) return;
      event.dataTransfer.setData(SCENE_DRAG_TYPE, item.dataset.sceneId);
      event.dataTransfer.setData('text/plain', item.dataset.sceneId);
      event.dataTransfer.effectAllowed = 'copy';
    }, { signal });
    this.container.addEventListener('dragover', (event) => {
      if (!this.state || !event.dataTransfer?.types.includes(SCENE_DRAG_TYPE) || !treePanel(event)) return;
      event.preventDefault();
      event.dataTransfer.dropEffect = 'copy';
      const row = event.target instanceof Element ? event.target.closest('[data-scene-tree-key]') ?? treePanel(event) : null;
      if (row && !row.classList.contains('is-drop-target')) { clearTargets(); row.classList.add('is-drop-target'); }
    }, { signal });
    this.container.addEventListener('drop', (event) => {
      const sceneId = event.dataTransfer?.getData(SCENE_DRAG_TYPE);
      clearTargets();
      if (!sceneId || !treePanel(event)) return;
      event.preventDefault();
      void this.instantiateScene(sceneId, { parentId: this.treeDropParent(event.target instanceof Element ? event.target : null) });
    }, { signal });
    this.container.addEventListener('dragend', clearTargets, { signal });
  }

  // -------------------------------------------------------------------------
  // Documents
  // -------------------------------------------------------------------------

  private async open(sceneId: string): Promise<void> {
    if (this.tabs.some((tab) => tab.key === `scene:${sceneId}`)) { this.activateTab(`scene:${sceneId}`); return; }
    const record = await this.repository.load('scene', sceneId);
    if (record.kind !== 'scene' || !('sceneId' in record.document)) throw new Error(`'${sceneId}' is not a scene document`);
    this.beginTab('scene', record.document.sceneId);
    this.state = new SceneDocumentState(record.document, { registry: this.registry }, record.hash);
    this.setLibraryScene(record.document);
    this.relativePath = record.relativePath;
    this.revealInExplorer(record.relativePath);
    await this.loadTileContexts(record.document);
    this.selectedKey = `:${record.document.rootNodeId}`;
    this.message = record.repairMode ? `Repair mode · ${record.issues.length} issue${record.issues.length === 1 ? '' : 's'}` : 'Document matches runtime contracts';
    window.history.replaceState(null, '', formatSceneStudioRoute({ active: true, scene: record.document.sceneId }, window.location.search));
    this.frameInitial(`scene:${record.document.sceneId}`);
    this.render();
  }

  private async openResource(id: string): Promise<void> {
    if (this.tabs.some((tab) => tab.key === `resource:${id}`)) { this.activateTab(`resource:${id}`); return; }
    const record = await this.repository.load('resource', id);
    if (record.kind !== 'resource' || !('resourceId' in record.document)) throw new Error(`'${id}' is not a resource document`);
    this.beginTab('resource', record.document.resourceId);
    this.resourceState = new ResourceDocumentState(record.document, record.hash);
    this.resourceRelativePath = record.relativePath;
    this.revealInExplorer(record.relativePath);
    this.message = record.repairMode ? `Repair mode · ${record.issues.length} issue${record.issues.length === 1 ? '' : 's'}` : 'Resource matches runtime contracts';
    window.history.replaceState(null, '', formatSceneStudioRoute({ active: true, resource: record.document.resourceId }, window.location.search));
    this.frameInitial(`resource:${record.document.resourceId}`);
    this.render();
  }

  // -------------------------------------------------------------------------
  // Tabs
  // -------------------------------------------------------------------------

  private activeTab(): StudioTab | undefined {
    return this.tabs.find((tab) => tab.key === this.activeTabKey);
  }

  /** Writes the live editing fields back into the active tab. */
  private stashActiveTab(): void {
    const tab = this.activeTab();
    if (!tab) return;
    tab.state = this.state;
    tab.resourceState = this.resourceState;
    tab.relativePath = this.relativePath;
    tab.resourceRelativePath = this.resourceRelativePath;
    tab.selectedKey = this.selectedKey;
    tab.expanded = this.expanded;
    tab.tileContexts = this.tileContexts;
    tab.shapeResources = this.shapeResources;
    tab.lastShapeEdit = this.lastShapeEdit;
    tab.animationPlayerKey = this.animationPlayerKey;
    tab.animationClosedAt = this.animationClosedAt;
    tab.camera = this.liveViewport?.camera;
    tab.message = this.message;
  }

  /** Makes `tab` (or an empty workspace) live, without rendering. */
  private restoreTab(tab: StudioTab | undefined): void {
    this.activeTabKey = tab?.key;
    this.state = tab?.state;
    this.resourceState = tab?.resourceState;
    this.relativePath = tab?.relativePath;
    this.resourceRelativePath = tab?.resourceRelativePath;
    this.selectedKey = tab?.selectedKey;
    this.expanded = tab?.expanded ?? new Set();
    this.tileContexts = tab?.tileContexts ?? new Map();
    this.shapeResources = tab?.shapeResources ?? new Map();
    this.lastShapeEdit = tab?.lastShapeEdit;
    this.animationPlayerKey = tab?.animationPlayerKey;
    this.animationClosedAt = tab?.animationClosedAt;
    this.message = tab?.message ?? 'No open documents · choose a scene from the expedition index.';
    this.composedCache = undefined;
    this.posedCache = undefined;
    this.preview?.stopAnimation();
    const route = !tab ? { active: true } : tab.kind === 'scene' ? { active: true, scene: toSceneId(tab.id) } : { active: true, resource: toResourceId(tab.id) };
    window.history.replaceState(null, '', formatSceneStudioRoute(route, window.location.search));
    const path = tab?.relativePath ?? tab?.resourceRelativePath;
    if (path) this.revealInExplorer(path);
    if (tab?.camera && this.liveViewport) { this.pendingFrame = undefined; this.liveViewport.setCamera(tab.camera); }
    else if (tab) this.frameInitial(tab.key);
  }

  /** Opens a fresh tab after the active one and makes it live; the caller loads its document. */
  private beginTab(kind: StudioTab['kind'], id: string): void {
    this.stashActiveTab();
    const tab: StudioTab = {
      key: `${kind}:${id}`, kind, id,
      state: undefined, resourceState: undefined, relativePath: undefined, resourceRelativePath: undefined, selectedKey: undefined,
      expanded: new Set(), tileContexts: new Map(), shapeResources: new Map(),
      lastShapeEdit: undefined, animationPlayerKey: undefined, animationClosedAt: undefined, camera: undefined, message: '',
    };
    const activeIndex = this.tabs.findIndex((candidate) => candidate.key === this.activeTabKey);
    this.tabs.splice(activeIndex < 0 ? this.tabs.length : activeIndex + 1, 0, tab);
    this.restoreTab(tab);
  }

  private activateTab(key: string): void {
    const tab = this.tabs.find((candidate) => candidate.key === key);
    if (!tab) return;
    if (key !== this.activeTabKey) {
      this.stashActiveTab();
      this.restoreTab(tab);
    }
    this.render();
  }

  private closeTab(key: string): void {
    const index = this.tabs.findIndex((candidate) => candidate.key === key);
    if (index < 0) return;
    this.stashActiveTab();
    const tab = this.tabs[index];
    if (tabDirty(tab) && !window.confirm(`${tabLabel(tab)} has unsaved changes. Close it and discard them?`)) return;
    this.tabs.splice(index, 1);
    if (key === this.activeTabKey) this.restoreTab(this.tabs[index] ?? this.tabs[index - 1]);
    this.render();
  }

  private renderTabs(): string {
    if (this.tabs.length === 0) return '';
    return `<nav class="scene-tabs" role="tablist" aria-label="Open documents">${this.tabs.map((tab) => {
      const active = tab.key === this.activeTabKey;
      const dirty = tabDirty(tab);
      const title = `${tab.id}\n${tab.relativePath ?? tab.resourceRelativePath ?? ''}`;
      return `<div class="scene-tab${active ? ' is-active' : ''}${dirty ? ' is-dirty' : ''}" data-tab-key="${escapeHtml(tab.key)}"><button type="button" role="tab" aria-selected="${active}" data-tab-activate="${escapeHtml(tab.key)}" title="${escapeHtml(title)}"><span aria-hidden="true">${tab.kind === 'scene' ? '◫' : '◈'}</span>${escapeHtml(tabLabel(tab))}${dirty ? '<em aria-label="unsaved">(*)</em>' : ''}</button><button type="button" class="scene-tab-close" data-tab-close="${escapeHtml(tab.key)}" aria-label="Close ${escapeHtml(tabLabel(tab))}" title="Close (middle-click)">×</button></div>`;
    }).join('')}</nav>`;
  }

  private setLibraryScene(document: SceneDocument): void {
    this.library.set(document.sceneId, document);
    this.libraryRevision += 1;
  }

  private frameInitial(identity: string): void {
    this.framedFor = undefined;
    this.pendingFrame = identity;
    this.framedAtInteraction = this.liveViewport?.userCameraInteractions ?? 0;
  }

  private framedAtInteraction = 0;

  private pendingFrame?: string;

  private async save(): Promise<void> {
    if ((!this.state || !this.relativePath) && (!this.resourceState || !this.resourceRelativePath)) return;
    try {
      // Embedded tile layers save inside the scene file, like Godot's TileMapLayer cells.
      const embeddedTiles = this.activeTileContexts().filter((entry) => entry.relativePath === undefined);
      const sceneDirty = Boolean(this.state?.dirty || (this.state && this.state.diskHash === undefined) || embeddedTiles.some(tileContextUnsaved));
      const writes = [
        ...(this.state && sceneDirty && this.relativePath ? [{ kind: 'scene' as const, id: this.state.sceneId, relativePath: this.relativePath, document: this.sceneDocumentWithTileEdits()!, expectedHash: this.state.diskHash ?? null }] : []),
        ...this.activeTileContexts()
          .filter((entry) => entry.relativePath !== undefined && tileContextUnsaved(entry))
          .map((entry) => ({
          kind: 'resource' as const,
          id: entry.context.document.resourceId,
          relativePath: entry.relativePath!,
          document: entry.context.document,
          expectedHash: entry.hash ?? null,
        })),
        ...[...this.shapeResources.values()].filter((entry) => entry.state.dirty).map((entry) => ({
          kind: 'resource' as const,
          id: entry.state.document.resourceId,
          relativePath: entry.relativePath,
          document: entry.state.document,
          expectedHash: entry.state.diskHash ?? null,
        })),
        ...(this.resourceState?.dirty && this.resourceRelativePath ? [{
          kind: 'resource' as const,
          id: this.resourceState.document.resourceId,
          relativePath: this.resourceRelativePath,
          document: this.resourceState.document,
          expectedHash: this.resourceState.diskHash ?? null,
        }] : []),
      ];
      if (writes.length === 0) return;
      const results = await this.repository.save(writes);
      for (const result of results) {
        if (result.kind === 'scene') {
          this.state?.markSaved(result.hash);
          // Other tabs instancing this scene pick up the saved version, like Godot.
          if (this.state) this.setLibraryScene(this.sceneDocumentWithTileEdits() ?? this.state.document);
          for (const entry of embeddedTiles) entry.context.markSaved();
        } else {
          if (this.resourceState?.document.resourceId === result.id) this.resourceState.markSaved(result.hash);
          const entry = [...this.tileContexts.values()].find((candidate) => candidate.context.document.resourceId === result.id);
          if (entry) { entry.hash = result.hash; entry.context.markSaved(); }
          this.shapeResources.get(toResourceId(result.id))?.state.markSaved(result.hash);
        }
      }
      // Files written for the first time (new scenes) join the explorer.
      const added = results.filter((result) => !this.catalog.some((item) => item.kind === result.kind && item.id === result.id));
      if (added.length > 0) {
        this.catalog = [...this.catalog, ...added.map(({ kind, id, relativePath }) => ({ kind, id, relativePath }))];
        for (const result of added) this.revealInExplorer(result.relativePath);
      }
      const createdScene = added.find((result) => result.kind === 'scene');
      this.message = createdScene ? `Created ${createdScene.relativePath}` : 'Committed · disk and editor are synchronized';
    } catch (error) {
      this.message = error instanceof SceneStudioConflictError ? 'Save conflict · reload or preserve your draft before retrying' : error instanceof Error ? error.message : String(error);
    }
    this.render();
  }

  private undo(): boolean {
    const tile = this.selectedTileContext();
    const shape = this.lastShapeEdit ? this.shapeResources.get(this.lastShapeEdit) : undefined;
    const changed = this.resourceState?.undo()
      ?? (shape?.state.canUndo ? shape.state.undo() : tile?.context.canUndo ? tile.context.undo() : this.state?.undo() ?? false);
    if (changed) this.message = 'Undid command';
    return changed;
  }

  private redo(): boolean {
    const tile = this.selectedTileContext();
    const shape = this.lastShapeEdit ? this.shapeResources.get(this.lastShapeEdit) : undefined;
    const changed = this.resourceState?.redo()
      ?? (shape?.state.canRedo ? shape.state.redo() : tile?.context.canRedo ? tile.context.redo() : this.state?.redo() ?? false);
    if (changed) this.message = 'Redid command';
    return changed;
  }

  // -------------------------------------------------------------------------
  // Composition helpers
  // -------------------------------------------------------------------------

  private resolveScene = (sceneId: SceneId): SceneDocument | undefined => this.library.get(sceneId);

  private isTransformType = (type: string): boolean => (propertiesForNode(type, undefined, this.registry) ?? []).some((descriptor) => descriptor.key === 'position');

  private composed(): { readonly nodes: readonly ComposedSceneNode[]; readonly byKey: ReadonlyMap<string, ComposedSceneNode> } {
    const state = this.state;
    if (!state) return { nodes: [], byKey: new Map() };
    const signature = `${state.sceneId}:${state.revision}:${this.libraryRevision}`;
    if (this.composedCache?.signature === signature) return this.composedCache;
    const nodes = composeSceneNodes(state.document, this.resolveScene, this.isTransformType);
    this.composedCache = { signature, nodes, byKey: new Map(nodes.map((node) => [node.key, node])) };
    return this.composedCache;
  }

  /**
   * The composition the viewport shows: while the animation dock is open, local
   * nodes take their animated values at the playhead, so markers, handles and
   * hitboxes sit where the posed preview draws them.
   */
  private viewComposed(): { readonly nodes: readonly ComposedSceneNode[]; readonly byKey: ReadonlyMap<string, ComposedSceneNode> } {
    const state = this.state;
    const overrides = this.animationPanel.visible ? this.animationPanel.poseOverrides() : undefined;
    if (!state || !overrides || overrides.size === 0) return this.composed();
    const signature = `${state.sceneId}:${state.revision}:${this.libraryRevision}:${JSON.stringify([...overrides])}`;
    if (this.posedCache?.signature === signature) return this.posedCache;
    const posed: SceneDocument = { ...state.document, nodes: state.document.nodes.map((node) => {
      const values = overrides.get(`:${node.id}`);
      return values ? { ...node, properties: { ...node.properties, ...values } } : node;
    }) };
    const nodes = composeSceneNodes(posed, this.resolveScene, this.isTransformType);
    this.posedCache = { signature, nodes, byKey: new Map(nodes.map((node) => [node.key, node])) };
    return this.posedCache;
  }

  private instanceRootKey(row: Extract<SceneTreeRow, { kind: 'instance' }>): string | undefined {
    const source = this.library.get(row.sceneId);
    return source ? `${[...(row.instancePath ?? []), row.instanceId].join('/')}:${source.rootNodeId}` : undefined;
  }

  /** Composed key of the selection (instance rows map to their instanced root node). */
  private selectedComposedKey(): string | undefined {
    const row = this.rows.find((candidate) => candidate.key === this.selectedKey);
    if (!row) return undefined;
    return row.kind === 'instance' ? this.instanceRootKey(row) : row.key;
  }

  private subtreeKeys(rootKey: string | undefined): ReadonlySet<string> {
    const keys = new Set<string>();
    if (!rootKey) return keys;
    keys.add(rootKey);
    for (const node of this.composed().nodes) if (node.parentKey && keys.has(node.parentKey)) keys.add(node.key);
    return keys;
  }

  private findResource(resourceId: ResourceId, sourceSceneId?: SceneId): SceneResourceDocument | undefined {
    const current = this.state?.document;
    const local = [current, sourceSceneId ? this.library.get(sourceSceneId) : undefined]
      .flatMap((document) => document?.subresources ?? [])
      .find((resource) => resource.resourceId === resourceId);
    // Live tile contexts win over the scene's embedded copy, which only updates on save.
    return this.shapeResources.get(resourceId)?.state.document
      ?? [...this.tileContexts.values()].find((entry) => entry.context.document.resourceId === resourceId)?.context.document
      ?? local
      ?? this.externalResources.get(resourceId);
  }

  /** Tile contexts for layers that still exist in the open scene. */
  private activeTileContexts(): LoadedTileContext[] {
    const nodes = new Set(this.state?.document.nodes.map((node) => node.id) ?? []);
    return [...this.tileContexts.entries()].filter(([nodeId]) => nodes.has(nodeId)).map(([, entry]) => entry);
  }

  /** The open scene as it would be saved, including unsaved paint on embedded tile layers. */
  private sceneDocumentWithTileEdits(): SceneDocument | undefined {
    if (!this.state) return undefined;
    const embedded = this.activeTileContexts().filter((entry) => entry.relativePath === undefined).map((entry) => entry.context.document);
    return withEmbeddedTileData(this.state.document, embedded);
  }

  // -------------------------------------------------------------------------
  // Viewport
  // -------------------------------------------------------------------------

  private previewChanged(state: StudioPreviewState): void {
    if (state.status === 'ready' && this.pendingFrame && this.liveViewport) {
      this.pendingFrame = undefined;
      this.liveViewport.update(this.viewportModel());
      // Refine the initial framing with rendered bounds unless the user already moved the camera.
      if (this.liveViewport.userCameraInteractions === this.framedAtInteraction) this.liveViewport.frameAll();
    }
    this.liveViewport?.update(this.viewportModel());
    // Every draft edit re-mounts the preview; restore the timeline's pose or playback.
    if (state.status === 'ready') this.animationPanel.previewRemounted();
  }

  private schedulePreview(): void {
    const preview = this.previewSession;
    if (!preview || !this.preview) return;
    const request = this.previewRequest();
    const signature = request?.signature;
    if (signature === this.previewSignature) return;
    this.previewSignature = signature;
    if (this.previewTimer) clearTimeout(this.previewTimer);
    if (!request) { preview.close(); return; }
    const immediate = request.immediate;
    const run = (): void => {
      this.previewTimer = undefined;
      this.preview?.setResourceOverrides(request.resources());
      this.preview?.setBossGhosts(this.resourceState ? [] : this.bossGhostRequests());
      preview.open(request.document());
    };
    if (immediate) run();
    else this.previewTimer = setTimeout(run, PREVIEW_DEBOUNCE_MS);
  }

  private previewRequest(): { readonly signature: string; readonly immediate: boolean; document(): SceneDocument; resources(): readonly SceneResourceDocument[] } | undefined {
    const state = this.state;
    if (state) {
      const tiles = [...this.tileContexts.values()].map((entry) => `${entry.context.document.resourceId}@${entry.context.revision}`).join(',');
      const shapes = [...this.shapeResources.values()].map((entry) => JSON.stringify(entry.state.document)).join(',');
      const signature = `scene:${state.sceneId}:${state.revision}:${this.libraryRevision}:${tiles}:${shapes.length}:${hashString(shapes)}`;
      const immediate = !this.previewSignature?.startsWith(`scene:${state.sceneId}:`);
      return {
        signature, immediate,
        document: () => this.sceneDocumentWithTileEdits() ?? state.document,
        resources: () => [
          ...[...this.tileContexts.values()].flatMap((entry) => [entry.context.document, entry.tileSetDocument]),
          ...[...this.shapeResources.values()].map((entry) => entry.state.document),
        ],
      };
    }
    const resource = this.resourceState?.document;
    if (!resource) return undefined;
    const synthetic = resourcePreviewScene(resource);
    if (!synthetic) return undefined;
    const signature = `resource:${resource.resourceId}:${hashString(JSON.stringify(resource))}`;
    return { signature, immediate: !this.previewSignature?.startsWith(`resource:${resource.resourceId}:`), document: () => synthetic.document, resources: () => [resource, ...synthetic.resources] };
  }

  private viewportModel(): LiveViewportModel {
    const previewState = this.preview?.state;
    const status = !this.preview ? 'Embedded preview unavailable · overlay only'
      : previewState?.status === 'error' ? `Preview error · ${previewState.error ?? 'unknown'}`
        : previewState?.status === 'loading' || previewState?.status === 'booting' ? 'Rendering with the game runtime…'
          : previewState?.error ? `Runtime diagnostics · ${previewState.error}` : undefined;
    const statusTone = previewState?.status === 'error' ? 'error' as const : 'info' as const;
    const previewBounds = previewState?.status === 'ready' ? previewState.contentBounds : undefined;
    const resource = this.resourceState?.document;
    if (resource) return this.resourceViewportModel(resource, status, statusTone, previewBounds);
    const state = this.state;
    if (!state) return { ariaLabel: '2D viewport', footer: 'NO DOCUMENT', markers: [], shapes: [], pickables: [], ...(status ? { status, statusTone } : {}) };
    const { nodes, byKey } = this.viewComposed();
    const selectedComposed = this.selectedComposedKey();
    const selectedSubtree = this.subtreeKeys(selectedComposed);
    const selectedRow = this.rows.find((row) => row.key === this.selectedKey);
    const visibleRowKeys = new Set(this.rows.map((row) => row.key));
    const topInstanceKey = (node: ComposedSceneNode): string => `:instance:${node.instancePath[0]}`;
    const pickKey = (node: ComposedSceneNode): string => {
      if (!node.readOnly) return node.key;
      if (visibleRowKeys.has(node.key)) return node.key;
      return topInstanceKey(node);
    };
    const markers: LiveViewportMarker[] = [];
    const uiNodes = this.viewport.nodes(state.document.nodes).filter((node) => node.kind === 'ui');
    const isUiScene = uiNodes.length > 0 && !nodes.some((node) => node.global && !node.readOnly && node.key !== `:${state.document.rootNodeId}`);
    for (const node of uiNodes) {
      const key = `:${node.id}`;
      markers.push({ key, label: node.name, type: node.type, kind: 'ui', position: node.position, rect: { x: node.position[0], y: node.position[1], width: node.size?.[0] ?? 0, height: node.size?.[1] ?? 0 }, selected: key === selectedComposed, movable: false });
    }
    for (const node of nodes) {
      if (!node.global) continue;
      const selected = node.key === selectedComposed;
      if (!node.readOnly) {
        markers.push({ key: node.key, label: node.name, type: node.type, kind: 'node', position: node.global.position, selected, movable: true, rotation: node.global.rotation, rotatable: node.key !== `:${state.document.rootNodeId}` });
      } else if (node.instancePath.length === 1 && node.parentKey && byKey.get(node.parentKey)?.readOnly === false) {
        const instance = state.document.instances.find((candidate) => candidate.instanceId === node.instancePath[0]);
        markers.push({ key: topInstanceKey(node), label: instance?.name ?? node.name, type: instance?.sceneId ?? node.type, kind: 'instance', position: node.global.position, selected: selected || selectedRow?.key === topInstanceKey(node), movable: true });
      } else if (selected || visibleRowKeys.has(node.key)) {
        markers.push({ key: node.key, label: node.name, type: node.type, kind: 'node', position: node.global.position, selected, movable: false });
      }
    }
    // Where each boss camp's boss will appear (the preview also draws a translucent copy of it).
    for (const camp of nodes.filter(isBossCampScript)) {
      const spawn = bossSpawnPoint(camp, byKey);
      const boss = this.bossInfo(camp);
      if (spawn) markers.push({ key: camp.key, label: `Boss · ${boss?.name ?? 'not set'}`, type: boss?.sceneId ?? 'boss', kind: 'boss', position: spawn, selected: false, movable: false });
    }
    const bounds = this.preview?.nodeBounds() ?? new Map<string, WorldRect>();
    const runtimeKey = new Map(nodes.map((node) => [runtimeIdFor(node), node]));
    const pickables: { key: string; rect: WorldRect }[] = [];
    const selectionRects: WorldRect[] = [];
    for (const [runtimeId, rect] of bounds) {
      const node = runtimeKey.get(runtimeId);
      if (!node) continue;
      pickables.push({ key: pickKey(node), rect });
      if (selectedSubtree.has(node.key)) selectionRects.push(rect);
    }
    const selectionPoints = nodes.filter((node) => selectedSubtree.has(node.key) && node.global).map((node) => ({ x: node.global!.position[0], y: node.global!.position[1], width: 0, height: 0 }));
    const uiSelection = uiNodes.find((node) => `:${node.id}` === selectedComposed);
    const selectionRect = selectedComposed === `:${state.document.rootNodeId}` ? undefined : unionRects(selectionRects);
    const selectedShapes = this.selectedShapes(nodes, selectedSubtree);
    const shapes = [...selectedShapes, ...this.animationHitboxShapes(nodes)];
    // Framing a selection includes its collision shapes, so large world areas fit on screen.
    const shapeRects = selectedShapes.map((shape): WorldRect => {
      const extent = shapeExtent(shape.value) * Math.max(Math.abs(shape.transform.scale[0]), Math.abs(shape.transform.scale[1]));
      return { x: shape.transform.position[0] - extent, y: shape.transform.position[1] - extent, width: extent * 2, height: extent * 2 };
    });
    const boundsGuides = this.boundsGuides(nodes, selectedSubtree);
    const tile = this.selectedTileContext();
    const tileNode = tile && selectedComposed ? byKey.get(selectedComposed) : undefined;
    const tileSize = tileNode && typeof tileNode.properties.tileSize === 'number' ? tileNode.properties.tileSize : 64;
    const uiContent = unionRects(uiNodes.filter((node) => (node.size?.[0] ?? 0) > 0 && (node.size?.[1] ?? 0) > 0).map((node) => ({ x: node.position[0], y: node.position[1], width: node.size![0], height: node.size![1] })));
    const contentBounds = isUiScene
      ? uiContent ?? { x: 0, y: 0, width: 1280, height: 720 }
      : unionRects([previewBounds, composedBounds(nodes), tile && tileNode?.global ? { x: tileNode.global.position[0], y: tileNode.global.position[1], width: tile.context.document.columns * tileSize, height: tile.context.document.rows * tileSize } : undefined].filter((rect): rect is WorldRect => rect !== undefined));
    const selectionBounds = uiSelection
      ? { x: uiSelection.position[0], y: uiSelection.position[1], width: uiSelection.size?.[0] ?? 0, height: uiSelection.size?.[1] ?? 0 }
      : tile && tileNode?.global ? { x: tileNode.global.position[0], y: tileNode.global.position[1], width: tile.context.document.columns * tileSize, height: tile.context.document.rows * tileSize }
        : unionRects([...selectionRects, ...selectionPoints, ...shapeRects]);
    const selectedType = selectedRow?.kind === 'instance' ? `INSTANCE ${selectedRow.sceneId}` : selectedRow?.kind === 'node' ? selectedRow.type : 'NO SELECTION';
    return {
      ariaLabel: tile ? 'Tile map viewport' : isUiScene ? 'UI layout viewport' : '2D viewport',
      footer: tile ? `SNAP ${tileSize}px · ${tile.context.tool.toUpperCase()} · ${tile.context.selectedTile}` : `${String(selectedType).toUpperCase()} · ${nodes.length} NODES COMPOSED`,
      ...(status ? { status, statusTone } : {}),
      markers,
      ...(selectionRect ? { selectionRect } : {}),
      shapes,
      boundsGuides,
      ...(tile && tileNode?.global ? { tile: { context: tile.context, origin: tileNode.global.position, tileSize } } : {}),
      pickables,
      ...(contentBounds ? { contentBounds } : {}),
      ...(selectionBounds ? { selectionBounds } : {}),
      ...(isUiScene ? { screenRect: { x: 0, y: 0, width: 1280, height: 720 } } : {}),
    };
  }

  private resourceViewportModel(resource: SceneResourceDocument, status: string | undefined, statusTone: 'info' | 'error', previewBounds: WorldRect | undefined): LiveViewportModel {
    const markers: LiveViewportMarker[] = [];
    const shapes: LiveViewportShape[] = [];
    let contentBounds = previewBounds;
    if (resource.kind === 'tile-set') {
      Object.keys(resource.tiles).forEach((tileId, index) => markers.push({ key: `tile:${tileId}`, label: tileId, type: 'tile', kind: 'node', position: [index * 128 + 32, -12], selected: false, movable: false }));
      contentBounds = unionRects([previewBounds, { x: 0, y: -40, width: Math.max(1, Object.keys(resource.tiles).length * 128 - 64), height: 104 }].filter((rect): rect is WorldRect => rect !== undefined));
    } else if (resource.kind === 'collision-shape') {
      shapes.push({ key: `resource:${resource.resourceId}`, transform: { position: [0, 0], rotation: 0, scale: [1, 1] }, value: resource.value, editable: true });
      const extent = shapeExtent(resource.value);
      contentBounds = { x: -extent, y: -extent, width: extent * 2, height: extent * 2 };
    }
    const noPreview = !resourcePreviewScene(resource);
    return {
      ariaLabel: 'Resource preview',
      footer: `${resource.kind.toUpperCase()} · ${resource.resourceId}`,
      ...(noPreview && resource.kind !== 'collision-shape' ? { status: resource.kind === 'animation-library' ? `${Object.keys(resource.animations).length} clips · play them on a scene that owns an AnimationPlayer` : `${resource.kind} resources have no visual preview`, statusTone: 'info' as const } : status ? { status, statusTone } : {}),
      markers,
      shapes,
      pickables: [],
      ...(contentBounds ? { contentBounds, selectionBounds: contentBounds } : {}),
    };
  }

  private selectedShapes(nodes: readonly ComposedSceneNode[], subtree: ReadonlySet<string>): LiveViewportShape[] {
    const output: LiveViewportShape[] = [];
    const rootKey = this.state ? `:${this.state.document.rootNodeId}` : undefined;
    // The scene root selects everything; drawing every area/body shape there is noise.
    if (subtree.size === 0 || subtree.has(rootKey ?? '')) return output;
    // Selecting a world-area script also shows (and lets you drag) the shapes it references.
    const included = new Set(subtree);
    for (const node of nodes) if (subtree.has(node.key) && isWorldAreaScript(node)) for (const key of worldAreaShapeKeys(node)) included.add(key);
    const roles = new Map<string, NonNullable<LiveViewportShape['tone']>>([...worldAreaShapeRoles(nodes), ...bossCampShapeRoles(nodes)]);
    // Selecting a character script shows the attack areas it references (contact hop, landing zone…).
    for (const script of nodes) {
      if (!subtree.has(script.key) || !script.scriptId) continue;
      for (const property of ATTACK_AREA_REFERENCES) {
        const areaKey = referencedNodeKey(script, property);
        for (const node of nodes) if (areaKey && node.parentKey === areaKey && node.type === 'CollisionShape2D') { included.add(node.key); roles.set(node.key, 'attack'); }
      }
    }
    for (const node of nodes) {
      if (!included.has(node.key) || node.type !== 'CollisionShape2D' || !node.global) continue;
      if (output.length >= 64) break;
      const shape = this.collisionShapeOf(node);
      if (!shape) continue;
      const role = roles.get(node.key);
      output.push({ key: node.key, transform: node.global, value: shape.value, editable: shape.editable, ...(role ? { tone: role } : {}) });
    }
    return output;
  }

  /** The collision-shape resource a CollisionShape2D uses, and whether this scene may edit it. */
  private collisionShapeOf(node: ComposedSceneNode): { readonly value: CollisionShapeValue; readonly editable: boolean } | undefined {
    const resourceId = referencedResourceId(node.properties.shape);
    const resource = resourceId ? this.findResource(resourceId, node.sourceSceneId) : undefined;
    if (!resource || resource.kind !== 'collision-shape') return undefined;
    const isLocalSubresource = (this.state?.document.subresources ?? []).some((candidate) => candidate.resourceId === resourceId);
    const isExternal = this.externalResources.has(resource.resourceId) || this.shapeResources.has(resource.resourceId);
    return { value: resource.value, editable: isLocalSubresource || isExternal };
  }

  private selectFromViewport(key: string): void {
    let row = this.rows.find((candidate) => candidate.key === key);
    if (!row) {
      const node = this.composed().byKey.get(key);
      if (node?.readOnly) row = this.rows.find((candidate) => candidate.key === `:instance:${node.instancePath[0]}`);
    }
    if (!row) return;
    this.selectRow(row);
    this.render();
    this.container.querySelector<HTMLElement>(`[data-scene-tree-key="${CSS.escape(row.key)}"]`)?.scrollIntoView({ block: 'nearest' });
  }

  private selectRow(row: SceneTreeRow): void {
    this.selectedKey = row.key;
    if (row.kind === 'node' && !row.readOnly) { this.state?.select({ kind: 'node', nodeId: row.nodeId }); this.viewport.select(row.nodeId); }
    else if (row.kind === 'instance' && (row.instancePath ?? []).length === 0) this.state?.select({ kind: 'instance', instanceId: row.instanceId });
  }

  private moveFromViewport(key: string, global: readonly [number, number]): void {
    const state = this.state;
    if (!state) return;
    try {
      const instanceMatch = /^:instance:(.+)$/.exec(key);
      if (instanceMatch) {
        const instance = state.document.instances.find((candidate) => candidate.instanceId === instanceMatch[1]);
        const source = instance ? this.library.get(instance.sceneId) : undefined;
        const root = source ? this.composed().byKey.get(`${instance!.instanceId}:${source.rootNodeId}`) : undefined;
        if (!instance || !source || !root) return;
        const local = localPositionFor(root.parentGlobal, global);
        state.execute(sceneCommands.setOverride(instance.instanceId, { sourceInstancePath: [], sourceNodeId: source.rootNodeId, property: 'position', value: [round2(local[0]), round2(local[1])] }));
        this.preview?.patchPosition(runtimeIdFor(root), [round2(local[0]), round2(local[1])]);
        this.message = `Moved ${instance.name} to ${Math.round(global[0])}, ${Math.round(global[1])}`;
      } else {
        const node = this.viewComposed().byKey.get(key);
        if (!node || node.readOnly) return;
        const local = localPositionFor(node.parentGlobal, global);
        const position: [number, number] = [round2(local[0]), round2(local[1])];
        if (this.animationPanel.autoKeys(key)) {
          if (this.animationPanel.keyNodeProperty(key, 'position', position)) this.message = `Keyed ${node.name} position ${position.join(', ')}`;
          this.render();
          return;
        }
        const authored = state.document.nodes.find((candidate) => candidate.id === node.nodeId);
        const rotation = typeof authored?.properties.rotation === 'number' ? authored.properties.rotation : 0;
        const scale = Array.isArray(authored?.properties.scale) ? authored.properties.scale as [number, number] : [1, 1] as [number, number];
        const issues = validateViewportTransform(node.type, { position, rotation, scale });
        if (issues.length > 0) throw new Error(issues.join('; '));
        state.execute(authored && ('rotation' in authored.properties || 'scale' in authored.properties)
          ? transformNodeCommand(node.nodeId, node.type, { position, rotation, scale })
          : sceneCommands.setProperty(node.nodeId, 'position', position));
        this.preview?.patchPosition(runtimeIdFor(node), position);
        this.message = `Moved ${node.name} to ${position.join(', ')}`;
      }
    } catch (error) { this.message = error instanceof Error ? error.message : String(error); }
    this.render();
  }

  private rotateFromViewport(key: string, globalRotation: number): void {
    const state = this.state;
    const node = this.viewComposed().byKey.get(key);
    if (!state || !node || node.readOnly) return;
    let rotation = globalRotation - (node.parentGlobal?.rotation ?? 0);
    rotation = Math.round(Math.atan2(Math.sin(rotation), Math.cos(rotation)) * 10000) / 10000;
    const degrees = Math.round(rotation * 1800 / Math.PI) / 10;
    try {
      if (this.animationPanel.autoKeys(key)) {
        if (this.animationPanel.keyNodeProperty(key, 'rotation', rotation)) this.message = `Keyed ${node.name} rotation ${degrees}°`;
      } else {
        const authored = state.document.nodes.find((candidate) => candidate.id === node.nodeId);
        const position = Array.isArray(authored?.properties.position) ? authored.properties.position as [number, number] : [0, 0] as [number, number];
        const scale = Array.isArray(authored?.properties.scale) ? authored.properties.scale as [number, number] : [1, 1] as [number, number];
        const issues = validateViewportTransform(node.type, { position, rotation, scale });
        if (issues.length > 0) throw new Error(issues.join('; '));
        state.execute(transformNodeCommand(node.nodeId, node.type, { position, rotation, scale }));
        this.message = `Rotated ${node.name} to ${degrees}°`;
      }
    } catch (error) { this.message = error instanceof Error ? error.message : String(error); }
    this.render();
  }

  private paintFromViewport(cell: { readonly x: number; readonly y: number }): void {
    const tile = this.selectedTileContext();
    if (!tile) return;
    try {
      tile.context.paint(cell);
      this.lastShapeEdit = undefined;
      this.message = `${tile.context.tool === 'erase' ? 'Erased' : 'Painted'} tile ${cell.x},${cell.y}`;
    } catch (error) { this.message = error instanceof Error ? error.message : String(error); }
    this.render();
  }

  private async editShapeFromViewport(key: string, value: CollisionShapeValue): Promise<void> {
    try {
      if (key.startsWith('resource:') && this.resourceState?.document.kind === 'collision-shape') {
        const next = editCollisionShape(this.resourceState.document, value);
        this.resourceState.setField('value', next.value as unknown as JsonValue);
        this.message = `Resized ${this.resourceState.document.resourceId}`;
        this.render();
        return;
      }
      const node = this.composed().byKey.get(key);
      const resourceId = node ? referencedResourceId(node.properties.shape) : undefined;
      if (!node || !resourceId || !this.state) return;
      const local = (this.state.document.subresources ?? []).find((candidate) => candidate.resourceId === resourceId);
      if (local?.kind === 'collision-shape') {
        this.state.execute(sceneCommands.upsertResource(editCollisionShape(local, value)));
        this.lastShapeEdit = undefined;
      } else {
        let entry = this.shapeResources.get(resourceId);
        if (!entry) {
          const record = await this.repository.load('resource', resourceId);
          if (record.kind !== 'resource' || !('kind' in record.document) || record.document.kind !== 'collision-shape') throw new Error(`'${resourceId}' is not an external collision-shape resource`);
          entry = { state: new ResourceDocumentState(record.document, record.hash), relativePath: record.relativePath };
          this.shapeResources.set(resourceId, entry);
        }
        const current = entry.state.document as CollisionShapeResourceDocument;
        const guide = collisionShapeGuide(current.value, value);
        if (!guide.differs) return;
        entry.state.setField('value', editCollisionShape(current, value).value as unknown as JsonValue);
        this.lastShapeEdit = resourceId;
      }
      this.message = `Resized collision shape ${resourceId}`;
    } catch (error) { this.message = error instanceof Error ? error.message : String(error); }
    this.render();
  }

  // -------------------------------------------------------------------------
  // Events
  // -------------------------------------------------------------------------

  private async handleClick(event: Event): Promise<void> {
    const folderAction = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-explorer-new-scene],[data-explorer-new-folder]') : null;
    if (folderAction) {
      const newScene = folderAction.dataset.explorerNewScene;
      this.openFileDialog(newScene !== undefined ? 'scene' : 'folder', newScene ?? folderAction.dataset.explorerNewFolder ?? '');
      return;
    }
    const folderToggle = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-explorer-folder-toggle]') : null;
    if (folderToggle?.dataset.explorerFolderToggle !== undefined) { this.explorerFolder = folderToggle.dataset.explorerFolderToggle; this.toggleExplorerFolder(folderToggle); return; }
    const toggle = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-tree-toggle]') : null;
    if (toggle?.dataset.treeToggle) { event.stopPropagation(); this.toggleExpanded(toggle.dataset.treeToggle); return; }
    if (event.target instanceof Node && this.animationPanel.element.contains(event.target)) return;
    const jsonButton = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-json-add],[data-json-remove],[data-json-unlock],[data-json-apply],[data-json-cancel]') : null;
    if (jsonButton) { this.handleJsonButton(jsonButton); return; }
    const tabControl = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-tab-close],[data-tab-activate]') : null;
    if (tabControl?.dataset.tabClose) { this.closeTab(tabControl.dataset.tabClose); return; }
    if (tabControl?.dataset.tabActivate) { this.activateTab(tabControl.dataset.tabActivate); return; }
    const instanceOption = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-instance-scene]') : null;
    if (instanceOption?.dataset.instanceScene) { await this.instantiateScene(instanceOption.dataset.instanceScene); return; }
    const keyToggle = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-key-toggle]') : null;
    const keyRow = keyToggle?.closest<HTMLElement>('[data-key-property]');
    if (keyRow?.dataset.keyNode && keyRow.dataset.keyProperty) { this.animationPanel.toggleNodeKey(keyRow.dataset.keyNode, keyRow.dataset.keyProperty); return; }
    const target = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-scene-id],[data-resource-id],[data-scene-tree-key],[data-action],[data-scene-add],[data-create-type],[data-create-script-id],[data-create-template],[data-area-enemy-add],[data-area-enemy-remove],[data-open-source],[data-tile-id],[data-tile-tool]') : null;
    if (!target) return;
    const tile = this.selectedTileContext();
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
    if (target.dataset.sceneId) { await this.open(target.dataset.sceneId).catch((error: unknown) => this.fail(error)); return; }
    if (target.dataset.resourceId) { await this.openResource(target.dataset.resourceId).catch((error: unknown) => this.fail(error)); return; }
    if (target.dataset.sceneTreeKey) {
      const row = this.rows.find((candidate) => candidate.key === target.dataset.sceneTreeKey);
      if (row) { this.selectRow(row); this.render(); }
      return;
    }
    if (target.hasAttribute('data-scene-add')) { this.creationSearch = ''; this.render(); return; }
    if (target.dataset.areaEnemyAdd) { this.editAreaSettings(target.dataset.areaEnemyAdd, { kind: 'enemy-add', type: this.enemyTypeIds()[0] ?? '' }); return; }
    if (target.dataset.areaEnemyRemove !== undefined) {
      const scriptKey = target.closest<HTMLElement>('[data-area-settings]')?.dataset.areaSettings;
      if (scriptKey) this.editAreaSettings(scriptKey, { kind: 'enemy-remove', index: Number(target.dataset.areaEnemyRemove) });
      return;
    }
    if (target.dataset.createTemplate && this.state) { this.addWorldArea(target.dataset.createTemplate as WorldAreaTemplateKind); return; }
    if ((target.dataset.createType || target.dataset.createScriptId) && this.state) {
      const parentId = this.state.selection.kind === 'node' ? this.state.selection.nodeId : this.state.document.rootNodeId;
      const scriptId = target.dataset.createScriptId;
      const type = scriptId ? 'ScriptNode' : target.dataset.createType ?? 'Node';
      const id = this.uniqueNodeId(type.toLowerCase());
      const order = this.state.document.nodes.filter((node) => node.parentId === parentId).length + this.state.document.instances.filter((instance) => instance.parentNodeId === parentId).length;
      const name = scriptId ? this.registry.scripts.get(scriptId)?.displayName ?? scriptId : type;
      this.state.execute(sceneCommands.addNode({ id, name, type, ...(scriptId ? { scriptId } : {}), parentId, order, properties: {} } as SceneNodeDocument));
      this.creationSearch = undefined;
      this.selectedKey = `:${id}`;
      this.render();
      return;
    }
    if (target.dataset.openSource) { this.container.dispatchEvent(new CustomEvent('scene-studio-open-source', { bubbles: true, detail: { path: target.dataset.openSource } })); return; }
    const action = target.dataset.action;
    if (action === 'save') await this.save();
    else if (action === 'undo') { this.undo(); this.render(); }
    else if (action === 'redo') { this.redo(); this.render(); }
    else if (action === 'copy-node') { this.copySelection(); this.render(); }
    else if (action === 'paste-node') { this.pasteClipboard(); }
    else if (action === 'delete-node') { this.deleteSelection(); }
    else if (action === 'toggle-tile-collision' && tile) { tile.context.toggleCollision(); this.render(); }
    else if (action === 'toggle-effective-region' && tile) { tile.context.toggleEffectiveRegion(); this.render(); }
    else if (action === 'tile-layer-up' && tile) { this.reorderSelectedTileLayer(-1); }
    else if (action === 'tile-layer-down' && tile) { this.reorderSelectedTileLayer(1); }
    else if (action === 'add-tile-layer' && tile) { this.addTileLayer(tile); }
    else if (action === 'close-create') { this.creationSearch = undefined; this.render(); }
    else if (action === 'instance-scene' && this.state) { this.instanceSearch = ''; this.render(); }
    else if (action === 'close-instance') { this.instanceSearch = undefined; this.render(); }
    else if (action === 'new-scene') this.openFileDialog('scene', this.defaultNewParent());
    else if (action === 'new-folder') this.openFileDialog('folder', this.defaultNewParent());
    else if (action === 'close-file-dialog') { this.fileDialog = undefined; this.render(); }
  }

  private toggleExpanded(key: string): void {
    if (this.expanded.has(key)) this.expanded.delete(key);
    else this.expanded.add(key);
    this.render();
    this.container.querySelector<HTMLElement>(`[data-scene-tree-key="${CSS.escape(key)}"]`)?.focus();
  }

  private handleChange(event: Event): void {
    if (!(event.target instanceof HTMLInputElement) && !(event.target instanceof HTMLSelectElement) && !(event.target instanceof HTMLTextAreaElement)) return;
    if (event.target.dataset.creationSearch !== undefined || event.target.dataset.explorerFilter !== undefined || event.target.dataset.instanceSearch !== undefined) return;
    if (event.target.dataset.fileField !== undefined) { this.updateFileDialogField(event.target); return; }
    const keyRow = event.target.closest<HTMLElement>('[data-key-property]');
    if (keyRow?.dataset.keyNode && keyRow.dataset.keyProperty) {
      try { this.animationPanel.keyNodeProperty(keyRow.dataset.keyNode, keyRow.dataset.keyProperty, readAnimationValue(keyRow, keyRow.dataset.kind as AnimationValueKind)); }
      catch (error) { this.message = error instanceof Error ? error.message : String(error); this.render(); }
      return;
    }
    if (this.resourceState && event.target.dataset.resourceField) {
      const field = event.target.dataset.resourceField;
      const current = (this.resourceState.document as unknown as Record<string, JsonValue>)[field];
      try {
        const value: JsonValue = typeof current === 'boolean' && event.target instanceof HTMLInputElement
          ? event.target.checked
          : typeof current === 'string' ? event.target.value
            : JSON.parse(event.target.value) as JsonValue;
        this.resourceState.setField(field, value);
        this.message = `Changed ${field}`;
      } catch (error) { this.message = error instanceof Error ? error.message : String(error); }
      this.render();
      return;
    }
    if (!this.state) return;
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
    const jsonForm = event.target.closest<HTMLElement>('[data-json-form]');
    if (jsonForm?.dataset.jsonForm) { this.handleJsonFormChange(jsonForm.dataset.jsonForm, event.target); return; }
    const areaSettings = event.target.closest<HTMLElement>('[data-area-settings]');
    if (areaSettings?.dataset.areaSettings) {
      const input = event.target;
      if (input.dataset.areaEnemyField) {
        this.editAreaSettings(areaSettings.dataset.areaSettings, { kind: 'enemy-field', index: Number(input.dataset.index), field: input.dataset.areaEnemyField as 'type' | 'weight' | 'maxAlive', value: input.value });
      } else if (input.dataset.areaSetting) {
        this.editAreaSettings(areaSettings.dataset.areaSettings, { kind: 'setting', key: input.dataset.areaSetting as 'intervalMs' | 'maxPopulation' | 'npcInstanceId', value: input.value });
      }
      return;
    }
    const shapeSection = event.target.closest<HTMLElement>('[data-shape-section]');
    if (shapeSection) { void this.editShapeFromInspector(shapeSection, event.target); return; }
    const property = event.target.dataset.property;
    const target = this.inspectorTarget();
    if (!property || !target || target.mode === 'read-only') return;
    const descriptor = [...sceneInspectorModel(target.node, this.registry).groups.values()].flat().find((candidate) => candidate.descriptor.key === property)?.descriptor;
    if (!descriptor) return;
    try {
      const raw = descriptor.inspector === 'source-rect' ? this.sourceRectRaw(event.target, target)
        : descriptor.inspector === 'checkbox' && event.target instanceof HTMLInputElement ? event.target.checked : event.target.value;
      const value = this.propertyEditors.get(descriptor.inspector).parse(raw, descriptor);
      if (target.mode === 'local') this.state.execute(sceneCommands.setProperty(target.node.id, property, value));
      else {
        if (!descriptor.overridable) throw new Error(`${descriptor.label} cannot be overridden on instances`);
        this.state.execute(sceneCommands.setOverride(target.instanceId!, { sourceInstancePath: [...(target.sourceInstancePath ?? [])], sourceNodeId: target.node.id, property, value }));
      }
      this.message = `Changed ${descriptor.label}${target.mode === 'override' ? ' (instance override)' : ''}`;
    } catch (error) { this.message = error instanceof Error ? error.message : String(error); }
    this.render();
  }

  // -------------------------------------------------------------------------
  // Scene instancing (Godot's "Instance Child Scene" and explorer drag-and-drop)
  // -------------------------------------------------------------------------

  /** Where a new instance goes: under the selected local node, beside a selected instance, else under the root. */
  private instanceParentId(): AuthoredNodeId | undefined {
    const state = this.state;
    if (!state) return undefined;
    const row = this.rows.find((candidate) => candidate.key === this.selectedKey);
    if (row?.kind === 'node' && !row.readOnly) return row.nodeId;
    if (row?.kind === 'instance' && (row.instancePath ?? []).length === 0) return row.parentNodeId;
    return state.document.rootNodeId;
  }

  /** Tree drop target: a local node row adopts the instance, an instance row gets a sibling. */
  private treeDropParent(element: Element | null): AuthoredNodeId | undefined {
    const key = element?.closest<HTMLElement>('[data-scene-tree-key]')?.dataset.sceneTreeKey;
    const row = key ? this.rows.find((candidate) => candidate.key === key) : undefined;
    if (row?.kind === 'node' && !row.readOnly) return row.nodeId;
    if (row?.kind === 'instance' && (row.instancePath ?? []).length === 0) return row.parentNodeId;
    return this.state?.document.rootNodeId;
  }

  private async instantiateScene(id: string, placement: { readonly parentId?: AuthoredNodeId; readonly global?: readonly [number, number] } = {}): Promise<void> {
    try {
      const state = this.state;
      if (!state) throw new Error('Open a scene before instancing another scene into it');
      const sourceId = toSceneId(id);
      let source = this.library.get(sourceId);
      if (!source) {
        const record = await this.repository.load('scene', sourceId);
        if (record.kind !== 'scene' || !('sceneId' in record.document)) throw new Error(`'${sourceId}' is not a scene document`);
        source = record.document;
        this.setLibraryScene(source);
      }
      if (sceneContains(source, state.sceneId, this.resolveScene)) {
        throw new Error(sourceId === state.sceneId ? 'A scene cannot be instanced into itself' : `Cannot instance ${sourceId}: it already contains ${state.sceneId}`);
      }
      const document = state.document;
      const parentId = placement.parentId ?? this.instanceParentId() ?? document.rootNodeId;
      const root = source.nodes.find((node) => node.id === source.rootNodeId);
      const baseName = root?.name ?? sourceId;
      const siblingNames = new Set([
        ...document.nodes.filter((node) => node.parentId === parentId).map((node) => node.name),
        ...document.instances.filter((instance) => instance.parentNodeId === parentId).map((instance) => instance.name),
      ]);
      let name = baseName;
      for (let suffix = 2; siblingNames.has(name); suffix += 1) name = `${baseName}${suffix}`;
      const newId = toInstanceId(uniqueId(sourceId.replace(/\./g, '-'), new Set(document.instances.map((instance) => instance.instanceId))));
      const overrides: SceneOverrideDocument[] = [];
      if (placement.global && root && this.isTransformType(root.type)) {
        const parent = this.composed().byKey.get(`:${parentId}`);
        const local = localPositionFor(parent?.global, placement.global);
        overrides.push({ sourceInstancePath: [], sourceNodeId: source.rootNodeId, property: 'position', value: [Math.round(local[0]), Math.round(local[1])] });
      }
      // Follow the document's convention: world scenes key every placed instance for save data.
      const keyed = document.instances.some((instance) => instance.persistenceKey !== undefined);
      const order = document.nodes.filter((node) => node.parentId === parentId).length + document.instances.filter((instance) => instance.parentNodeId === parentId).length;
      state.execute(sceneCommands.addInstance({
        instanceId: newId, name, sceneId: sourceId, parentNodeId: parentId, order,
        ...(keyed ? { persistenceKey: toPersistenceKey(`${state.sceneId}.${newId}`) } : {}),
        overrides,
      }));
      this.selectedKey = `:instance:${newId}`;
      this.instanceSearch = undefined;
      this.message = `Instanced ${sourceId} as ${name}${placement.global ? ` at ${Math.round(placement.global[0])}, ${Math.round(placement.global[1])}` : ''}`;
    } catch (error) { this.message = error instanceof Error ? error.message : String(error); }
    this.render();
  }

  private renderInstanceDialog(): string {
    const query = (this.instanceSearch ?? '').trim().toLowerCase();
    const current = this.state?.sceneId;
    const scenes = this.catalog
      .filter((item) => item.kind === 'scene' && item.id !== current && (!query || `${item.id} ${item.relativePath}`.toLowerCase().includes(query)))
      .slice(0, 200);
    return `<div class="scene-dialog-backdrop"><section role="dialog" aria-modal="true" aria-labelledby="scene-instance-title" class="scene-create-dialog"><header><div><span>PROJECT SCENES</span><h2 id="scene-instance-title">Instance child scene</h2></div><button type="button" data-action="close-instance" aria-label="Close instance dialog">×</button></header><label><span>Search scenes</span><input autofocus type="search" data-instance-search value="${escapeHtml(this.instanceSearch)}" /></label><div role="listbox">${scenes.map((item) => `<button type="button" role="option" data-instance-scene="${escapeHtml(item.id)}"><span>◫</span><strong>${escapeHtml(item.id)}</strong><small>${escapeHtml(item.relativePath)}</small></button>`).join('') || '<p>No matching scenes</p>'}</div></section></div>`;
  }

  // -------------------------------------------------------------------------
  // Occlusion / depth bounds and depth anchors
  // -------------------------------------------------------------------------

  /** Rendered frame geometry of a composed sprite node, from the live preview. */
  private spriteGeometry(node: ComposedSceneNode | undefined): SpriteBoundsGeometry | undefined {
    return node ? this.preview?.spriteGeometry().get(runtimeIdFor(node)) : undefined;
  }

  /** The inspector's rect control as a JSON value; switching it on starts from the sprite's frame. */
  private sourceRectRaw(input: HTMLElement, target: InspectorTarget): string {
    const group = input.closest<HTMLElement>('[data-rect-property]');
    if (!group) throw new Error('Rectangle control is missing its fields');
    if (input.dataset.rectField === 'enabled') {
      if (!(input instanceof HTMLInputElement) || !input.checked) return '{}';
      const frame = this.spriteGeometry(target.composed)?.sourceFrame ?? { width: 64, height: 64 };
      const width = Math.max(1, Math.round(frame.width));
      const height = Math.max(1, Math.round(frame.height));
      // Depth bounds start as the bottom quarter (a footprint); occlusion covers the whole frame.
      const footprint = group.dataset.rectProperty === 'depthBounds' ? Math.max(1, Math.round(height / 4)) : height;
      return JSON.stringify({ offsetX: 0, offsetY: height - footprint, width, height: footprint });
    }
    const values: Record<string, number> = {};
    for (const field of group.querySelectorAll<HTMLInputElement>('[data-rect-field]:not([data-rect-field="enabled"])')) values[field.dataset.rectField!] = Number(field.value);
    return JSON.stringify(values);
  }

  /** Writes a property on a composed node: directly when local, as an instance override otherwise. */
  private writeComposedProperty(node: ComposedSceneNode, property: string, value: JsonValue): void {
    const state = this.state;
    if (!state) return;
    if (!node.readOnly) { state.execute(sceneCommands.setProperty(node.nodeId, property, value)); return; }
    const [top, ...rest] = node.instancePath;
    if (!top || !state.document.instances.some((instance) => instance.instanceId === top)) throw new Error(`${node.name} cannot be edited from this scene`);
    state.execute(sceneCommands.setOverride(top, { sourceInstancePath: rest, sourceNodeId: node.nodeId, property, value }));
  }

  /**
   * Guides for the selected subtree: occlusion and depth bounds of sprites and
   * depth anchors of Node2Ds. Selecting a scene root shows its own nodes only,
   * so a world root does not draw every placed object.
   */
  private boundsGuides(nodes: readonly ComposedSceneNode[], subtree: ReadonlySet<string>): LiveViewportBoundsGuide[] {
    const state = this.state;
    if (!state) return [];
    const rootSelected = subtree.has(`:${state.document.rootNodeId}`);
    const guides: LiveViewportBoundsGuide[] = [];
    for (const node of nodes) {
      if (!subtree.has(node.key) || (rootSelected && node.readOnly) || guides.length >= 96) continue;
      const editable = !node.readOnly || state.document.instances.some((instance) => instance.instanceId === node.instancePath[0]);
      const anchor = node.properties.depthAnchor;
      if (Array.isArray(anchor) && anchor.length === 2 && node.global) {
        const local: readonly [number, number] = [Number(anchor[0]), Number(anchor[1])];
        guides.push({ key: node.key, property: 'depthAnchor', kind: 'anchor', point: localToGlobalPoint(node.global, local), editable });
      }
      if (node.type !== 'Sprite2D') continue;
      const geometry = this.spriteGeometry(node);
      if (!geometry) continue;
      for (const [property, kind, sprite] of [['occlusionBounds', 'occlusion', geometry.occlusionSprite], ['depthBounds', 'depth', geometry.depthSprite]] as const) {
        const bounds = sourceRectValue(node.properties[property]);
        if (bounds) guides.push({ key: node.key, property, kind, rect: resolveWorldOcclusionRectangle(sprite, geometry.sourceFrame, bounds), editable });
      }
    }
    return guides;
  }

  private editBoundsFromViewport(key: string, property: string, change: { readonly rect?: WorldRect; readonly point?: readonly [number, number] }): void {
    try {
      const node = this.composed().byKey.get(key);
      if (!node) return;
      if (property === 'depthAnchor' && change.point && node.global) {
        const local = localPositionFor(node.global, change.point);
        const value: [number, number] = [Math.round(local[0]), Math.round(local[1])];
        this.writeComposedProperty(node, 'depthAnchor', value);
        this.message = `Moved ${node.name} depth anchor to ${value.join(', ')}`;
      } else if ((property === 'occlusionBounds' || property === 'depthBounds') && change.rect) {
        const geometry = this.spriteGeometry(node);
        if (!geometry) throw new Error(`${node.name} is not rendered yet`);
        const bounds = resolveSourceBoundsFromWorld(property === 'depthBounds' ? geometry.depthSprite : geometry.occlusionSprite, geometry.sourceFrame, change.rect);
        this.writeComposedProperty(node, property, { ...bounds });
        this.message = `${property === 'depthBounds' ? 'Depth' : 'Occlusion'} bounds of ${node.name} · ${bounds.offsetX}, ${bounds.offsetY} · ${bounds.width}×${bounds.height}px`;
      }
    } catch (error) { this.message = error instanceof Error ? error.message : String(error); }
    this.render();
  }

  // -------------------------------------------------------------------------
  // Clipboard (SceneClipboard) and deletion
  // -------------------------------------------------------------------------

  private copySelection(): boolean {
    const selection = this.state?.selection;
    if (!this.state || selection?.kind !== 'node') return false;
    if (selection.nodeId === this.state.document.rootNodeId) { this.message = 'The scene root cannot be copied'; return false; }
    this.clipboard.copy(this.state.document, selection.nodeId);
    this.message = `Copied ${selection.nodeId}`;
    return true;
  }

  private pasteClipboard(): boolean {
    if (!this.state || !this.clipboard.hasContent) return false;
    const selection = this.state.selection;
    const parentId = selection.kind === 'node' ? selection.nodeId : this.state.document.rootNodeId;
    const taken = new Set(this.state.document.nodes.map((node) => node.id));
    try {
      let pastedRoot: AuthoredNodeId | undefined;
      this.state.execute(this.clipboard.paste(parentId, (source) => {
        const id = uniqueId(`${source}-copy`, taken);
        taken.add(id);
        pastedRoot ??= id;
        return id;
      }));
      if (pastedRoot) { this.selectedKey = `:${pastedRoot}`; this.state.select({ kind: 'node', nodeId: pastedRoot }); }
      this.message = `Pasted into ${parentId}`;
    } catch (error) { this.message = error instanceof Error ? error.message : String(error); }
    this.render();
    return true;
  }

  private deleteSelection(): boolean {
    const state = this.state;
    const selection = state?.selection;
    if (!state || !selection) return false;
    try {
      if (selection.kind === 'instance') state.execute(sceneCommands.removeInstance(selection.instanceId));
      else if (selection.kind === 'node') {
        if (selection.nodeId === state.document.rootNodeId) { this.message = 'The scene root cannot be deleted'; this.render(); return false; }
        const result = state.requestDeleteNode(selection.nodeId, { kind: 'remove-optional' });
        if (result.kind === 'requires-repair') { this.message = `Delete blocked · ${result.references.length} required reference${result.references.length === 1 ? '' : 's'} target this node`; this.render(); return true; }
      } else return false;
      this.selectedKey = `:${state.document.rootNodeId}`;
      state.select({ kind: 'node', nodeId: state.document.rootNodeId });
      this.message = 'Deleted selection';
    } catch (error) { this.message = error instanceof Error ? error.message : String(error); }
    this.render();
    return true;
  }

  /** Adds a ready-to-edit world area at the centre of the viewport. */
  private addWorldArea(kind: WorldAreaTemplateKind): void {
    const state = this.state;
    if (!state) return;
    const parentId = state.selection.kind === 'node' ? state.selection.nodeId : state.document.rootNodeId;
    const parent = this.composed().byKey.get(`:${parentId}`);
    const camera = this.liveViewport?.camera;
    const local = camera ? localPositionFor(parent?.global ?? parent?.parentGlobal, [camera.centerX, camera.centerY]) : [0, 0] as const;
    try {
      const { command, areaNodeId, areaId } = worldAreaTemplateCommand(state.document, kind, parentId, local);
      state.execute(command);
      this.creationSearch = undefined;
      this.selectedKey = `:${areaNodeId}`;
      this.expanded.add(`:${areaNodeId}`);
      this.message = `Added ${areaId} · drag its shapes in the viewport`;
    } catch (error) { this.message = error instanceof Error ? error.message : String(error); }
    this.render();
  }

  private uniqueNodeId(base: string): AuthoredNodeId {
    return uniqueId(base, new Set(this.state?.document.nodes.map((node) => node.id) ?? []));
  }

  // -------------------------------------------------------------------------
  // Tile contexts
  // -------------------------------------------------------------------------

  private async loadTileContexts(document: Pick<SceneDocument, 'nodes' | 'subresources'>): Promise<void> {
    this.tileContexts.clear();
    const local = (resourceId: string): SceneResourceDocument | undefined => document.subresources?.find((resource) => resource.resourceId === resourceId);
    for (const node of document.nodes) {
      if (node.type !== 'TileMapLayer2D') continue;
      const dataId = tileDataResourceId(node);
      if (!dataId) throw new Error(`Tile layer '${node.id}' requires a tileData resource`);
      // Tile data normally lives in the scene; standalone tile-data files are still supported.
      const embedded = local(dataId);
      let data: TileDataResourceDocument;
      let file: { readonly relativePath: string; readonly hash: string } | undefined;
      if (embedded) {
        if (embedded.kind !== 'tile-data') throw new Error(`Tile layer '${node.id}' requires tile-data resource '${dataId}'`);
        data = embedded;
      } else {
        const dataRecord = await this.repository.load('resource', dataId);
        if (dataRecord.kind !== 'resource' || !isTileDataDocument(dataRecord.document)) {
          throw new Error(`Tile layer '${node.id}' requires tile-data resource '${dataId}'`);
        }
        data = dataRecord.document;
        file = { relativePath: dataRecord.relativePath, hash: dataRecord.hash };
      }
      const localTileSet = local(data.tileSet);
      let tileSet: TileSetResourceDocument;
      if (localTileSet) {
        if (localTileSet.kind !== 'tile-set') throw new Error(`Tile data '${dataId}' requires tile-set resource '${data.tileSet}'`);
        tileSet = localTileSet;
      } else {
        const tileSetRecord = await this.repository.load('resource', data.tileSet);
        if (tileSetRecord.kind !== 'resource' || !isTileSetDocument(tileSetRecord.document)) {
          throw new Error(`Tile data '${dataId}' requires tile-set resource '${data.tileSet}'`);
        }
        tileSet = tileSetRecord.document;
      }
      this.tileContexts.set(node.id, {
        context: new TileMapContext(data, tileSet),
        ...(file ? { relativePath: file.relativePath, hash: file.hash } : {}),
        tileSetDocument: tileSet,
      });
    }
  }

  private selectedTileContext(): LoadedTileContext | undefined {
    const selection = this.state?.selection;
    const row = this.rows.find((candidate) => candidate.key === this.selectedKey);
    if (row && (row.kind !== 'node' || row.readOnly)) return undefined;
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
    // The new layer's cells are embedded in the scene, like the existing map layers.
    this.state.execute(sceneCommands.upsertResource(draft.data));
    this.state.execute(sceneCommands.addNode(draft.node));
    this.tileContexts.set(draft.node.id, {
      context: new TileMapContext(draft.data, source.tileSetDocument),
      tileSetDocument: source.tileSetDocument,
    });
    this.selectedKey = `:${draft.node.id}`;
    this.state.select({ kind: 'node', nodeId: draft.node.id });
    this.message = `Added tile layer ${draft.node.name}`;
    this.render();
  }

  // -------------------------------------------------------------------------
  // Inspector
  // -------------------------------------------------------------------------

  private inspectorTarget(): InspectorTarget | undefined {
    const state = this.state;
    const row = this.rows.find((candidate) => candidate.key === this.selectedKey);
    if (!state || !row) return undefined;
    if (row.kind === 'node' && !row.readOnly) {
      const node = state.document.nodes.find((candidate) => candidate.id === row.nodeId);
      return node ? { node, mode: 'local', ...(this.composed().byKey.get(row.key) ? { composed: this.composed().byKey.get(row.key)! } : {}) } : undefined;
    }
    const composedKey = row.kind === 'instance' ? this.instanceRootKey(row) : row.key;
    const composed = composedKey ? this.composed().byKey.get(composedKey) : undefined;
    if (!composed) return undefined;
    const source = this.library.get(composed.sourceSceneId)?.nodes.find((candidate) => candidate.id === composed.nodeId);
    if (!source) return undefined;
    const node: SceneNodeDocument = { ...source, properties: composed.properties as SceneNodeDocument['properties'] };
    const [top, ...rest] = composed.instancePath;
    const editable = state.document.instances.some((instance) => instance.instanceId === top);
    return { node, composed, mode: editable ? 'override' : 'read-only', ...(top ? { instanceId: top } : {}), sourceInstancePath: rest };
  }

  private renderInspector(): string {
    const resource = this.resourceState;
    if (resource) return renderResourceInspector(resource.document, this.resourceUsage(resource.document.resourceId));
    const target = this.inspectorTarget();
    if (!target) return '<aside class="scene-inspector scene-empty"><span>INSPECTOR</span><p>Select a node or instance to inspect its authored properties.</p></aside>';
    const instance = target.mode === 'override' && (target.sourceInstancePath ?? []).length === 0
      ? this.state?.document.instances.find((candidate) => candidate.instanceId === target.instanceId)
      : undefined;
    const model = sceneInspectorModel(target.node, this.registry, instance);
    let html = renderSceneInspector(model, {
      jsonControl: (property) => this.renderJsonControl(model, property, target.mode === 'read-only'),
      selectOptions: (source) => this.jsonFormContext().options(source, {}),
    });
    const row = this.rows.find((candidate) => candidate.key === this.selectedKey);
    if (target.mode !== 'local') {
      const instanceRow = row?.kind === 'instance' ? row : undefined;
      const card = `<section class="scene-instance-card"><span>${target.mode === 'override' ? 'INSTANCED · EDITS BECOME OVERRIDES' : 'NESTED INSTANCE · READ ONLY'}</span><strong>${escapeHtml(target.composed?.sourceSceneId)}</strong>${instanceRow ? `<button type="button" data-scene-id="${escapeHtml(instanceRow.sceneId)}">Open ${escapeHtml(instanceRow.sceneId)}</button>` : `<button type="button" data-scene-id="${escapeHtml(target.composed?.sourceSceneId)}">Open source scene</button>`}</section>`;
      html = html.replace('</header>', `</header>${card}`);
      if (target.mode === 'read-only') html = html.replace('<aside class="scene-inspector"', '<aside class="scene-inspector is-readonly"').replace(/<(input|select|textarea) /g, '<$1 disabled ');
    }
    const tile = this.selectedTileContext();
    const extras = [
      target.composed ? this.renderBossCampSection(target.composed) : '',
      target.composed ? this.renderWorldAreaSection(target.composed) : '',
      target.composed && target.node.type === 'CollisionShape2D' ? this.renderShapeSection(target.composed, target.mode === 'read-only') : '',
      target.composed ? this.animationPanel.renderNodeKeyframes(target.composed.key) : '',
      tile ? renderTileMapTools(tile.context, this.tileSetSummaries()) : '',
      this.renderNodeResources(target),
    ].join('');
    return html.replace(/<\/aside>$/, `${extras}</aside>`);
  }

  /** Numeric size fields for a CollisionShape2D, mirroring its viewport handles. */
  private renderShapeSection(node: ComposedSceneNode, readOnly: boolean): string {
    const shape = this.collisionShapeOf(node);
    if (!shape) return '';
    const editable = shape.editable && !readOnly;
    const disabled = editable ? '' : ' disabled';
    const value = shape.value;
    const field = (name: string, label: string, amount: number): string => `<label><small>${label}</small><input type="number" min="1" step="1" data-shape-field="${name}" value="${escapeHtml(Math.round(amount * 100) / 100)}"${disabled} /></label>`;
    const fields = value.shape === 'rectangle' ? field('width', 'Width', value.width) + field('height', 'Height', value.height)
      : value.shape === 'circle' ? field('radius', 'Radius', value.radius)
        : value.shape === 'ellipse' ? field('radiusX', 'Radius X', value.radiusX) + field('radiusY', 'Radius Y', value.radiusY)
          : '<small>Sector shapes are edited in their resource.</small>';
    const kinds = value.shape === 'sector' ? '' : `<label><small>Kind</small><select data-shape-kind${disabled}>${(['rectangle', 'circle', 'ellipse'] as const).map((kind) => `<option ${kind === value.shape ? 'selected' : ''}>${kind}</option>`).join('')}</select></label>`;
    const note = editable ? 'Or drag its handle in the viewport; move the node to reposition it.' : 'This shape belongs to another scene or resource; open it there to edit.';
    return `<section class="scene-shape-fields" data-shape-section="${escapeHtml(node.key)}" aria-label="Collision shape size"><header><span>SHAPE</span></header><div class="scene-shape-field-row">${kinds}${fields}</div><small>${note}</small></section>`;
  }

  /** Enemy types spawn areas can use: catalogued enemies that have a `character.<type>` scene. */
  private enemyTypeIds(): readonly string[] {
    return ENEMY_TYPE_IDS.filter((id) => this.library.has(toSceneId(`character.${id}`))).sort();
  }

  /** Enemy picker plus spawn timing for an enemy-spawn area; edits write the script's Area Settings. */
  private renderSpawnSettings(script: ComposedSceneNode, enemyTypes: readonly string[]): string {
    const settings = spawnSettings(script);
    const typeOptions = (selected: string): string => [...new Set([...enemyTypes, ...(selected ? [selected] : [])])]
      .map((type) => `<option value="${escapeHtml(type)}" ${type === selected ? 'selected' : ''}>${escapeHtml(type)}${enemyTypes.includes(type) ? '' : ' (unknown)'}</option>`).join('');
    const rows = settings.enemies.map((entry, index) => `<div class="scene-area-enemy-row">`
      + `<select data-area-enemy-field="type" data-index="${index}" aria-label="Enemy type">${typeOptions(entry.type)}</select>`
      + `<label><small>Weight</small><input type="number" min="1" step="1" data-area-enemy-field="weight" data-index="${index}" value="${escapeHtml(entry.weight)}" /></label>`
      + `<label><small>Max alive</small><input type="number" min="1" step="1" placeholder="any" data-area-enemy-field="maxAlive" data-index="${index}" value="${escapeHtml(entry.maxAlive ?? '')}" /></label>`
      + `<button type="button" data-area-enemy-remove="${index}" aria-label="Remove enemy">×</button></div>`).join('');
    return `<div class="scene-area-settings" data-area-settings="${escapeHtml(script.key)}"><small>ENEMIES · picked by weight</small>${rows}`
      + `<button type="button" class="scene-link" data-area-enemy-add="${escapeHtml(script.key)}">+ Add enemy</button>`
      + `<div class="scene-shape-field-row"><label><small>Spawn every (ms)</small><input type="number" min="1" step="100" data-area-setting="intervalMs" value="${escapeHtml(settings.intervalMs)}" /></label>`
      + `<label><small>Max population</small><input type="number" min="1" step="1" data-area-setting="maxPopulation" value="${escapeHtml(settings.maxPopulation)}" /></label></div></div>`;
  }

  /** NPC picker for a wander area: the placed NPC instances in this scene. */
  private renderWanderSettings(script: ComposedSceneNode, nodes: readonly ComposedSceneNode[]): string {
    const data = script.properties.data;
    const npcInstanceId = data && typeof data === 'object' && !Array.isArray(data) ? (data as Readonly<Record<string, JsonValue>>).npcInstanceId : undefined;
    const current = typeof npcInstanceId === 'string' ? npcInstanceId : '';
    const npcs = this.npcOptions(nodes);
    const options = [{ value: '', label: '(choose an NPC)' }, ...npcs, ...(current && !npcs.some((npc) => npc.value === current) ? [{ value: current, label: `${current} (not in this world)` }] : [])]
      .map((option) => `<option value="${escapeHtml(option.value)}" ${option.value === current ? 'selected' : ''}>${escapeHtml(option.label)}</option>`).join('');
    return `<div class="scene-area-settings" data-area-settings="${escapeHtml(script.key)}"><label><small>NPC THAT WANDERS HERE</small><select data-area-setting="npcInstanceId">${options}</select></label></div>`;
  }

  // -------------------------------------------------------------------------
  // Friendly JSON property forms (see JsonPropertyForms.ts)
  // -------------------------------------------------------------------------

  /** NPCs placed in this world, labelled "Lili · level-1-npc-lili". */
  private npcOptions(nodes: readonly ComposedSceneNode[]): readonly FormOption[] {
    const byInstance = new Map<string, string>();
    for (const node of nodes) {
      const instanceId = node.instancePath[0];
      if (node.scriptId !== 'game.npc' || !instanceId || byInstance.has(instanceId)) continue;
      const definitionId = node.properties.npcDefinitionId;
      const root = nodes.find((candidate) => candidate.instancePath.length === 1 && candidate.instancePath[0] === instanceId && !candidate.parentKey?.startsWith(`${instanceId}:`))
        ?? nodes.find((candidate) => candidate.instancePath[0] === instanceId);
      const name = (typeof definitionId === 'string' ? getNpcDefinition(definitionId)?.displayName : undefined) ?? root?.name ?? instanceId;
      byInstance.set(instanceId, `${name} · ${instanceId}`);
    }
    return [...byInstance].map(([value, label]) => ({ value, label })).sort((left, right) => left.label.localeCompare(right.label));
  }

  /** Option lists the forms pick from; `strict` lists are complete, so other values are flagged. */
  private jsonFormContext(): JsonFormContext {
    const ids = (values: Iterable<string>, strict: boolean): FormOptions => ({ options: [...new Set(values)].sort().map((value) => ({ value, label: value })), strict });
    return {
      options: (source, parent) => {
        switch (source) {
          case 'items': {
            const definitions = getBaseItemDefinitions();
            return { options: getKnownItemIds().map((id) => ({ value: id, label: definitions[id] ? `${definitions[id].name} · ${id}` : id })), strict: true };
          }
          case 'npcs': return { options: this.npcOptions(this.composed().nodes), strict: true };
          case 'enemyTypes': return ids(this.enemyTypeIds(), true);
          case 'enemyBehaviors': return ids(['slime-spider'], false);
          case 'resourceTags': return ids(RESOURCE_TAGS, true);
          case 'collectibles': return ids(getObjectArchetypeIds().filter((id) => id.startsWith('collectible.')), true);
          case 'objectVisuals': {
            const objectId = typeof parent.objectId === 'string' ? parent.objectId : '';
            if (!isObjectArchetypeId(objectId)) return ids([], false);
            const visuals = (getObjectArchetype(objectId).variants ?? []).flatMap((variant) => variant.frames.map((frame) => frame.visualId));
            return ids(visuals, visuals.length > 0);
          }
          case 'effects': return ids([...getEffectDefinitions().map((effect) => effect.effectId), ...[...this.library.keys()].filter((id) => id.startsWith('effect.')).map((id) => id.slice('effect.'.length))], false);
          // Hit feedback mounts `effect.<id>` scenes, so only effects with a scene are valid.
          case 'effectScenes': return ids([...this.library.keys()].filter((id) => id.startsWith('effect.')).map((id) => id.slice('effect.'.length)), true);
          case 'projectiles': return ids(getProjectileDefinitions().map((projectile) => projectile.projectileId), false);
          default: return ids([], false);
        }
      },
    };
  }

  private jsonDraftKey(property: string): string {
    const target = this.inspectorTarget();
    return `${target?.composed?.key ?? target?.node.id ?? ''}|${property}`;
  }

  /** Friendly form (when the property has one) above the JSON, which stays read-only until "Edit JSON". */
  private renderJsonControl(model: SceneInspectorModel, property: InspectorProperty, readOnly: boolean): string {
    const key = property.descriptor.key;
    const values = Object.fromEntries([...model.groups.values()].flat().flatMap((entry) => entry.value === undefined ? [] : [[entry.descriptor.key, entry.value]]));
    const form = jsonFormFor(model.node.scriptId, key, values);
    const json = JSON.stringify(property.value ?? null, null, 2);
    const editing = readOnly ? undefined : this.jsonDrafts.get(this.jsonDraftKey(key));
    const formHtml = form ? `<fieldset class="scene-json-form" data-json-form="${escapeHtml(key)}"${editing || readOnly ? ' disabled' : ''}>${renderJsonForm(form, property.value, this.jsonFormContext())}</fieldset>` : '';
    const actions = readOnly ? ''
      : editing ? `<button type="button" class="scene-save" data-json-apply="${escapeHtml(key)}">Apply JSON</button><button type="button" data-json-cancel="${escapeHtml(key)}">Cancel</button>`
        : `<button type="button" data-json-unlock="${escapeHtml(key)}" title="Advanced: edit the raw JSON">Edit JSON</button>`;
    return `${formHtml}<div class="scene-json-source${editing ? ' is-editing' : ''}"><div class="scene-json-source-bar"><small>JSON</small>${actions}</div>`
      + `<textarea data-json-source="${escapeHtml(key)}" spellcheck="false" aria-label="${escapeHtml(property.descriptor.label)} JSON" ${editing ? '' : 'readonly'}>${escapeHtml(editing?.draft ?? json)}</textarea>`
      + (editing?.error ? `<p class="scene-json-error" role="alert">${escapeHtml(editing.error)}</p>` : '') + '</div>';
  }

  /** The inspector's current value of a JSON property, including instance overrides. */
  private jsonPropertyState(property: string): { readonly value: JsonValue | undefined; readonly model: SceneInspectorModel } | undefined {
    const target = this.inspectorTarget();
    if (!target || target.mode === 'read-only') return undefined;
    const instance = target.mode === 'override' && (target.sourceInstancePath ?? []).length === 0
      ? this.state?.document.instances.find((candidate) => candidate.instanceId === target.instanceId)
      : undefined;
    const model = sceneInspectorModel(target.node, this.registry, instance);
    const entry = [...model.groups.values()].flat().find((candidate) => candidate.descriptor.key === property);
    return entry ? { value: entry.value, model } : undefined;
  }

  /** Writes a JSON property on the selected node, as an override on instances. */
  private commitJsonProperty(property: string, value: JsonValue): void {
    const target = this.inspectorTarget();
    if (!this.state || !target || target.mode === 'read-only') throw new Error('This node cannot be edited from this scene');
    const descriptor = [...sceneInspectorModel(target.node, this.registry).groups.values()].flat().find((candidate) => candidate.descriptor.key === property)?.descriptor;
    if (!descriptor) throw new Error(`Unknown property '${property}'`);
    if (target.mode === 'local') this.state.execute(sceneCommands.setProperty(target.node.id, property, value));
    else {
      if (!descriptor.overridable) throw new Error(`${descriptor.label} cannot be overridden on instances`);
      this.state.execute(sceneCommands.setOverride(target.instanceId!, { sourceInstancePath: [...(target.sourceInstancePath ?? [])], sourceNodeId: target.node.id, property, value }));
    }
    this.message = `Changed ${descriptor.label}${target.mode === 'override' ? ' (instance override)' : ''}`;
  }

  private applyJsonEdit(property: string, edit: JsonFormEdit): void {
    try {
      const current = this.jsonPropertyState(property);
      if (!current) return;
      const values = Object.fromEntries([...current.model.groups.values()].flat().flatMap((entry) => entry.value === undefined ? [] : [[entry.descriptor.key, entry.value]]));
      const form = jsonFormFor(current.model.node.scriptId, property, values);
      if (!form) return;
      this.commitJsonProperty(property, applyJsonFormEdit(form, current.value, edit));
    } catch (error) { this.message = error instanceof Error ? error.message : String(error); }
    this.render();
  }

  private handleJsonFormChange(property: string, input: HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement): void {
    const path = (attribute: string | undefined): JsonPath => JSON.parse(attribute ?? '[]') as JsonPath;
    if (input.dataset.jsonPick !== undefined) return;
    if (input.dataset.jsonToggle !== undefined && input instanceof HTMLInputElement) this.applyJsonEdit(property, { kind: 'toggle', on: input.checked });
    else if (input.dataset.jsonRename) this.applyJsonEdit(property, { kind: 'rename', path: path(input.dataset.jsonRename), to: input.value });
    else if (input.dataset.jsonPath) {
      const raw = input instanceof HTMLInputElement && input.type === 'checkbox' ? input.checked : input.value;
      this.applyJsonEdit(property, { kind: 'set', path: path(input.dataset.jsonPath), raw });
    }
  }

  private handleJsonButton(button: HTMLElement): void {
    const { jsonAdd, jsonRemove, jsonUnlock, jsonApply, jsonCancel } = button.dataset;
    const property = button.closest<HTMLElement>('[data-json-form]')?.dataset.jsonForm;
    if (jsonAdd !== undefined && property) {
      const option = button.closest('.scene-json-adder')?.querySelector<HTMLSelectElement>('[data-json-pick]')?.value;
      this.applyJsonEdit(property, { kind: 'add', path: JSON.parse(jsonAdd) as JsonPath, ...(option ? { option } : {}) });
    } else if (jsonRemove !== undefined && property) this.applyJsonEdit(property, { kind: 'remove', path: JSON.parse(jsonRemove) as JsonPath });
    else if (jsonUnlock) {
      const current = this.jsonPropertyState(jsonUnlock);
      if (!current) return;
      this.jsonDrafts.set(this.jsonDraftKey(jsonUnlock), { draft: JSON.stringify(current.value ?? null, null, 2) });
      this.render();
    } else if (jsonCancel) { this.jsonDrafts.delete(this.jsonDraftKey(jsonCancel)); this.render(); }
    else if (jsonApply) this.applyJsonDraft(jsonApply);
  }

  /** Parses and checks hand-edited JSON; only a value the form accepts is saved. */
  private applyJsonDraft(property: string): void {
    const draftKey = this.jsonDraftKey(property);
    const entry = this.jsonDrafts.get(draftKey);
    const current = this.jsonPropertyState(property);
    if (!entry || !current) return;
    try {
      let value: JsonValue;
      try { value = JSON.parse(entry.draft) as JsonValue; } catch (error) {
        throw new Error(`Not valid JSON: ${error instanceof Error ? error.message : String(error)}`);
      }
      const values = Object.fromEntries([...current.model.groups.values()].flat().flatMap((item) => item.value === undefined ? [] : [[item.descriptor.key, item.value]]));
      const form = jsonFormFor(current.model.node.scriptId, property, values);
      const issues = form ? validateJsonForm(form, value, this.jsonFormContext()) : [];
      if (issues.length > 0) throw new Error(issues.join(' · '));
      this.commitJsonProperty(property, value);
      this.jsonDrafts.delete(draftKey);
    } catch (error) {
      entry.error = error instanceof Error ? error.message : String(error);
      this.message = 'JSON not applied · fix the highlighted problem or Cancel';
    }
    this.render();
  }

  /** Applies one Area Settings edit from the inspector editor to the world-area script. */
  private editAreaSettings(scriptKey: string, edit: Parameters<typeof editAreaSettings>[1]): void {
    const script = this.composed().byKey.get(scriptKey);
    if (!script) return;
    try {
      this.writeComposedProperty(script, 'data', editAreaSettings(script.properties.data, edit));
      this.message = `Updated ${String(script.properties.areaId ?? script.name)} settings`;
    } catch (error) { this.message = error instanceof Error ? error.message : String(error); }
    this.render();
  }

  /** The boss a camp spawns, where it appears, and its activation/arena circles. */
  private renderBossCampSection(node: ComposedSceneNode): string {
    const { nodes } = this.composed();
    const camp = owningBossCamp(node, nodes);
    if (!camp) return '';
    const boss = this.bossInfo(camp);
    const summary = bossCampSummary(camp, nodes, (shapeNode) => this.collisionShapeOf(shapeNode), boss);
    const bossId = typeof camp.properties.bossId === 'string' ? camp.properties.bossId : '';
    const encounterSceneId = camp.sourceSceneId !== this.state?.document.sceneId ? camp.sourceSceneId : undefined;
    const bossCard = boss
      ? `<div class="scene-boss-link"><small>SPAWNS BOSS</small><strong>${escapeHtml(boss.name)}</strong><code>${escapeHtml(boss.sceneId)}</code>${bossId ? `<small>bossId · ${escapeHtml(bossId)}</small>` : ''}<button type="button" data-scene-id="${escapeHtml(boss.sceneId)}">Open boss scene</button></div>`
      : '';
    const shapeNote = summary.shapesEditableHere
      ? 'Drag the teal activation and amber arena circles in the viewport.'
      : `The circles belong to the encounter scene; open it to resize them (every placement shares them).`;
    return `<section class="scene-world-area scene-boss-camp" aria-label="Boss encounter"><header><span>BOSS ENCOUNTER</span></header>${bossCard}`
      + summary.lines.map((line) => `<p>${escapeHtml(line)}</p>`).join('')
      + summary.issues.map((issue) => `<p role="alert">${escapeHtml(issue)}</p>`).join('')
      + (summary.issues.length === 0 ? '<p class="is-ok">Valid · the boss will spawn and stay in its arena.</p>' : '')
      + (encounterSceneId ? `<button type="button" class="scene-link" data-scene-id="${escapeHtml(encounterSceneId)}">Open encounter scene ${escapeHtml(encounterSceneId)}</button>` : '')
      + `<small>${shapeNote} Change the boss with the camp script's Boss Scene property.</small></section>`;
  }

  /** Every boss camp's boss scene and spawn point, for the preview's translucent boss copies. */
  private bossGhostRequests(): readonly { readonly sceneId: SceneId; readonly position: readonly [number, number] }[] {
    if (!this.state) return [];
    const { nodes, byKey } = this.composed();
    return nodes.filter(isBossCampScript).flatMap((camp) => {
      const bossSceneId = bossSceneIdOf(camp);
      const spawn = bossSpawnPoint(camp, byKey);
      const sceneId = bossSceneId ? toSceneId(bossSceneId) : undefined;
      return sceneId && spawn && this.library.has(sceneId) && this.bossInfo(camp)?.spawnable ? [{ sceneId, position: spawn }] : [];
    });
  }

  /** Name and spawnability of the boss scene a camp script points to. */
  private bossInfo(camp: ComposedSceneNode): BossSceneInfo | undefined {
    const bossSceneId = bossSceneIdOf(camp);
    if (!bossSceneId) return undefined;
    const bossId = typeof camp.properties.bossId === 'string' ? camp.properties.bossId : bossSceneId;
    return bossSceneInfo(bossSceneId, this.library.get(toSceneId(bossSceneId)), (scriptId) => this.isEnemyScript(scriptId), bossId);
  }

  /** Whether a script is the enemy script or extends it (every boss and enemy behavior does). */
  private isEnemyScript(scriptId: string): boolean {
    for (let current: string | undefined = scriptId, depth = 0; current && depth < 16; depth += 1) {
      if (current === 'game.enemy') return true;
      current = this.registry.scripts.get(current)?.extends;
    }
    return false;
  }

  /** What the game will load for a world area, with the same checks the world loader applies. */
  private renderWorldAreaSection(node: ComposedSceneNode): string {
    const { nodes } = this.composed();
    const script = owningWorldArea(node, nodes);
    if (!script) return '';
    const enemyTypes = this.enemyTypeIds();
    const summary = worldAreaSummary(script, nodes, (shapeNode) => this.collisionShapeOf(shapeNode)?.value, new Set(enemyTypes));
    const legend = summary.kind === 'enemy-spawn'
      ? 'Drag the cyan pursue and amber stay shapes; move the Area2D to move both.'
      : 'Drag the shape in the viewport; move the Area2D to reposition it.';
    const settings = script.key === node.key ? '' : summary.kind === 'enemy-spawn' ? this.renderSpawnSettings(script, enemyTypes)
      : summary.kind === 'npc-wander' ? this.renderWanderSettings(script, nodes) : '';
    return `<section class="scene-world-area" aria-label="World area"><header><span>WORLD AREA · ${escapeHtml(summary.kind.toUpperCase())}</span></header>`
      + settings
      + summary.lines.map((line) => `<p>${escapeHtml(line)}</p>`).join('')
      + summary.issues.map((issue) => `<p role="alert">${escapeHtml(issue)}</p>`).join('')
      + (summary.issues.length === 0 ? '<p class="is-ok">Valid · the game will load this area.</p>' : '<p class="is-bad">The world will not load until this is fixed.</p>')
      + `<small>${legend}</small></section>`;
  }

  private async editShapeFromInspector(section: HTMLElement, input: HTMLElement): Promise<void> {
    const key = section.dataset.shapeSection ?? '';
    const node = this.composed().byKey.get(key);
    const current = node ? this.collisionShapeOf(node)?.value : undefined;
    if (!current) return;
    if (input.dataset.shapeKind !== undefined && input instanceof HTMLSelectElement) {
      await this.editShapeFromViewport(key, convertShapeKind(current, input.value as 'rectangle' | 'circle' | 'ellipse'));
      return;
    }
    const read = (name: string): number => Number(section.querySelector<HTMLInputElement>(`[data-shape-field="${name}"]`)?.value);
    const next: CollisionShapeValue = current.shape === 'rectangle' ? { shape: 'rectangle', width: read('width'), height: read('height') }
      : current.shape === 'circle' ? { shape: 'circle', radius: read('radius') }
        : current.shape === 'ellipse' ? { shape: 'ellipse', radiusX: read('radiusX'), radiusY: read('radiusY') }
          : current;
    await this.editShapeFromViewport(key, next);
  }

  private renderNodeResources(target: InspectorTarget): string {
    const references = Object.entries(target.node.properties).flatMap(([property, value]) => {
      const id = referencedResourceId(value);
      return id ? [{ property, id, external: this.externalResources.has(id) }] : [];
    });
    if (references.length === 0) return '';
    return `<section class="scene-resource-links" aria-label="Referenced resources"><header><span>RESOURCES</span></header>${references.map((reference) => `<div><small>${escapeHtml(reference.property)}</small>${reference.external ? `<button type="button" class="scene-link" data-resource-id="${escapeHtml(reference.id)}">${escapeHtml(reference.id)}</button>` : `<code>${escapeHtml(reference.id)}</code>`}</div>`).join('')}</section>`;
  }

  private resourceUsage(resourceId: string): readonly SceneId[] {
    const id = toResourceId(resourceId);
    const users = new Set<SceneId>();
    for (const document of this.library.values()) {
      if (resourceConsumers(document, id).length > 0) users.add(document.sceneId);
      else if (document.nodes.some((node) => {
        const dataId = node.type === 'TileMapLayer2D' ? referencedResourceId(node.properties.tileData) : undefined;
        const data = dataId ? document.subresources?.find((resource) => resource.resourceId === dataId) ?? this.externalResources.get(toResourceId(dataId)) : undefined;
        return data?.kind === 'tile-data' && data.tileSet === id;
      })) users.add(document.sceneId);
    }
    return [...users].sort();
  }

  // -------------------------------------------------------------------------
  // Animation dock
  // -------------------------------------------------------------------------

  /** The AnimationPlayer the dock edits: the selected one, else the pinned one while it still exists. */
  private animationPlayerNode(): ComposedSceneNode | undefined {
    if (!this.state) return undefined;
    const { nodes, byKey } = this.composed();
    const subtree = this.subtreeKeys(this.selectedComposedKey());
    const rootSelected = subtree.has(`:${this.state.document.rootNodeId}`);
    if (this.animationClosedAt !== undefined && this.animationClosedAt === this.selectedKey) return undefined;
    this.animationClosedAt = undefined;
    const pinned = this.animationPlayerKey ? byKey.get(this.animationPlayerKey) : undefined;
    if (!pinned || !subtree.has(pinned.key)) {
      // Selecting the root picks the scene's own player; instanced players need their instance selected.
      const candidate = nodes.find((node) => node.type === 'AnimationPlayer' && subtree.has(node.key) && (!rootSelected || !node.readOnly));
      if (candidate) return byKey.get(this.animationPlayerKey = candidate.key);
    }
    return pinned?.type === 'AnimationPlayer' ? pinned : undefined;
  }

  private animationContext(): AnimationEditorContext | undefined {
    const state = this.state;
    const player = this.animationPlayerNode();
    this.animationBinding = undefined;
    if (!state || !player) return undefined;
    const libraryId = referencedResourceId(player.properties.library);
    if (!libraryId) return undefined;
    const embedded = player.readOnly ? undefined : (state.document.subresources ?? []).find((resource) => resource.resourceId === libraryId);
    const library = embedded ?? this.findResource(libraryId, player.sourceSceneId);
    if (library?.kind !== 'animation-library') return undefined;
    const { nodes } = this.composed();
    const domain = player.properties.domain === 'physics' ? 'physics' : 'render';
    const owner = player.readOnly ? undefined : attackPlanOwner(state.document.nodes, player.nodeId);
    const attackArea = owner?.properties.attackArea;
    const attackAreaId = attackArea !== null && typeof attackArea === 'object' && !Array.isArray(attackArea) ? (attackArea as Readonly<Record<string, JsonValue>>).nodeId : undefined;
    const attackAreaKey = typeof attackAreaId === 'string' ? `:${attackAreaId}` : undefined;
    this.animationBinding = {
      playerNodeId: player.nodeId,
      libraryId,
      runtimeId: runtimeIdFor(player),
      sourceSceneId: player.sourceSceneId,
      ...(owner ? { ownerNodeId: owner.id } : {}),
      ...(attackAreaKey ? { attackAreaKey } : {}),
    };
    const readOnlyReason = player.readOnly
      ? `Instanced from ${player.sourceSceneId} · open the source scene to edit`
      : !embedded ? `Library ${libraryId} is not embedded in this scene` : undefined;
    return {
      playerKey: player.key,
      playerName: player.name,
      libraryId,
      clips: library.animations as unknown as AnimationEditorContext['clips'],
      domain,
      ...(typeof player.properties.autoplay === 'string' && player.properties.autoplay ? { autoplay: player.properties.autoplay } : {}),
      ...(readOnlyReason ? { readOnlyReason, sourceSceneId: player.sourceSceneId } : {}),
      nodes,
      targets: animationTargets(nodes, player.key, this.registry, domain),
      ...(owner ? { attack: { plans: owner.properties.attackPlans as AttackPlans, shapeNames: nodes.filter((node) => node.type === 'CollisionShape2D' && node.parentKey === attackAreaKey).map((node) => node.name) } } : {}),
      propertyDescriptors: (node) => propertiesForNode(node.type, node.scriptId, this.registry) ?? [],
    };
  }

  /** Re-renders the inspector's keyframe values after the playhead moves, unless the author is typing there. */
  private refreshKeyframeSection(): void {
    const section = this.container.querySelector<HTMLElement>('.scene-keyframes');
    const key = this.selectedComposedKey();
    if (!section || !key || (document.activeElement instanceof Node && section.contains(document.activeElement))) return;
    const html = this.animationPanel.renderNodeKeyframes(key);
    if (html) section.outerHTML = html;
    else section.remove();
  }

  /** Applies one timeline edit as a single undoable scene command (library, attack plans and autoplay together). */
  private commitAnimation(label: string, change: AnimationLibraryChange): boolean {
    const state = this.state;
    const binding = this.animationBinding;
    if (!state || !binding) return false;
    try {
      state.execute(sceneMutationCommand(label, (draft) => {
        const subresources = draft.subresources ?? [];
        if (!subresources.some((resource) => resource.resourceId === binding.libraryId)) throw new Error(`Animation library '${binding.libraryId}' is not embedded in this scene`);
        draft.subresources = subresources.map((resource) => resource.resourceId === binding.libraryId && resource.kind === 'animation-library'
          ? { ...resource, animations: change.clips as unknown as AnimationLibraryResourceDocument['animations'] }
          : resource);
        draft.nodes = draft.nodes.map((node) => {
          if (change.plans && node.id === binding.ownerNodeId) return { ...node, properties: { ...node.properties, attackPlans: change.plans as JsonValue } };
          if (change.autoplay !== undefined && node.id === binding.playerNodeId) {
            const { autoplay: _previous, ...properties } = node.properties;
            return { ...node, properties: change.autoplay === null ? properties : { ...properties, autoplay: change.autoplay } };
          }
          return node;
        });
      }));
      this.message = label;
    } catch (error) {
      this.message = error instanceof Error ? error.message : String(error);
      this.render();
      return false;
    }
    // Deferred so the dock can update its own selection before it receives the new context.
    queueMicrotask(() => this.render());
    return true;
  }

  private spriteFrames(texture: JsonValue | undefined): { readonly count: number; readonly thumbnail: (frame: number) => string | undefined } | undefined {
    const id = referencedResourceId(texture);
    const resource = id ? this.findResource(id, this.animationBinding?.sourceSceneId) : undefined;
    if (resource?.kind !== 'sprite-sheet') return undefined;
    const manifest = (ASSET_MANIFEST.assets as Readonly<Record<string, { readonly source?: { readonly frame?: { readonly count?: number } } } | undefined>>)[resource.assetId];
    const count = resource.frameCount ?? manifest?.source?.frame?.count ?? 0;
    return { count, thumbnail: (frame) => this.preview?.frameThumbnail(resource.assetId, frame) };
  }

  /** Hitbox shapes whose attack window covers the timeline playhead, drawn hot in the viewport. */
  private animationHitboxShapes(nodes: readonly ComposedSceneNode[]): LiveViewportShape[] {
    const areaKey = this.animationBinding?.attackAreaKey;
    const active = this.animationPanel.visible && areaKey ? this.animationPanel.activeHitboxes() : [];
    if (active.length === 0) return [];
    const names = new Set(active.map((hitbox) => `${hitbox.direction}--${hitbox.hitboxId}`));
    return nodes.flatMap((node) => {
      if (node.type !== 'CollisionShape2D' || node.parentKey !== areaKey || !names.has(node.name) || !node.global) return [];
      const resourceId = referencedResourceId(node.properties.shape);
      const resource = resourceId ? this.findResource(resourceId, node.sourceSceneId) : undefined;
      return resource?.kind === 'collision-shape' ? [{ key: `hitbox:${node.key}`, transform: node.global, value: resource.value, editable: false, active: true }] : [];
    });
  }

  // -------------------------------------------------------------------------
  // Rendering
  // -------------------------------------------------------------------------

  private render(): void {
    this.stashActiveTab();
    const active = document.activeElement instanceof HTMLElement ? document.activeElement : undefined;
    const focused = active
      ? (active.dataset.sceneTreeKey ? `[data-scene-tree-key="${CSS.escape(active.dataset.sceneTreeKey)}"]`
        : active.dataset.property ? `[data-property="${CSS.escape(active.dataset.property)}"]${active.dataset.rectField ? `[data-rect-field="${CSS.escape(active.dataset.rectField)}"]` : ''}`
          : active.dataset.resourceField ? `[data-resource-field="${CSS.escape(active.dataset.resourceField)}"]`
            : active.dataset.explorerFilter !== undefined ? '[data-explorer-filter]'
              : active.dataset.action ? `[data-action="${CSS.escape(active.dataset.action)}"]` : undefined)
      : undefined;
    const viewportFocused = active !== undefined && this.liveViewport?.element.contains(active);
    const explorerScroll = this.container.querySelector('.scene-explorer')?.scrollTop ?? 0;
    const treeScroll = this.container.querySelector('.scene-tree-panel')?.scrollTop ?? 0;
    const scenes = this.catalog.filter((item) => item.kind === 'scene');
    const resources = this.catalog.filter((item) => item.kind === 'resource');
    const state = this.state;
    const resource = this.resourceState;
    this.rows = state ? sceneTreeRows(state.document, this.resolveScene, (key) => this.expanded.has(key)) : [];
    const selectedRow = this.rows.find((row) => row.key === this.selectedKey);
    const animationFocus = this.animationPanel.focusSnapshot();
    const animation = this.animationContext();
    this.animationPanel.update(animation);
    const tile = this.selectedTileContext();
    const activeTileIds = new Set(state?.document.nodes.filter((node) => node.type === 'TileMapLayer2D').map((node) => node.id) ?? []);
    const dirty = Boolean(resource?.dirty || state?.dirty || (state && state.diskHash === undefined) || [...this.shapeResources.values()].some((entry) => entry.state.dirty) || [...this.tileContexts.entries()].some(([nodeId, entry]) => activeTileIds.has(nodeId) && tileContextUnsaved(entry)));
    const shape = this.lastShapeEdit ? this.shapeResources.get(this.lastShapeEdit) : undefined;
    const canUndo = Boolean(resource?.canUndo || shape?.state.canUndo || tile?.context.canUndo || state?.canUndo);
    const canRedo = Boolean(resource?.canRedo || shape?.state.canRedo || tile?.context.canRedo || state?.canRedo);
    const explorerTree = renderExplorerTree(buildExplorerTree(this.catalog, this.folders), {
      isOpen: (key) => this.explorerOpen.has(key),
      isCurrent: (item) => item.kind === 'scene' ? item.id === state?.sceneId : item.id === resource?.document.resourceId,
      escape: escapeHtml,
    });
    const canCopy = Boolean(state && selectedRow?.kind === 'node' && !selectedRow.readOnly && selectedRow.nodeId !== state.document.rootNodeId);
    const treePanel = state
      ? renderSceneTreePanel(this.rows, this.selectedKey).replace('<button type="button" data-scene-add', `<span class="scene-tree-actions"><button type="button" data-action="copy-node" ${canCopy ? '' : 'disabled'} aria-label="Copy node" title="Copy (Ctrl+C)">⧉</button><button type="button" data-action="paste-node" ${this.clipboard.hasContent ? '' : 'disabled'} aria-label="Paste node" title="Paste (Ctrl+V)">⎘</button><button type="button" data-action="delete-node" ${canCopy || (selectedRow?.kind === 'instance' && (selectedRow.instancePath ?? []).length === 0) ? '' : 'disabled'} aria-label="Delete selection" title="Delete (Del)">⌫</button><button type="button" data-action="instance-scene" aria-label="Instance child scene" title="Instance child scene (Ctrl+Shift+A) · or drag a scene from the explorer">⛓</button></span><button type="button" data-scene-add`)
      : resource ? `<section class="scene-tree-panel scene-empty"><p>Resource <strong>${escapeHtml(resource.document.resourceId)}</strong> · ${escapeHtml(resource.document.kind)}</p></section>`
        : '<section class="scene-tree-panel scene-empty"><p>Open a scene or resource from the project explorer.</p></section>';
    this.container.innerHTML = `<main class="scene-studio" data-scene-studio><header class="scene-topbar"><div><span>FIELD CARTOGRAPHER / UNIVERSAL GRAPH</span><h1>Scene Studio</h1></div><div class="scene-command-bar"><button type="button" data-action="undo" ${!canUndo ? 'disabled' : ''}>Undo</button><button type="button" data-action="redo" ${!canRedo ? 'disabled' : ''}>Redo</button><button type="button" class="scene-save" data-action="save" ${!dirty ? 'disabled' : ''}>${dirty ? 'Save changes' : 'Saved'}</button></div></header><aside class="scene-explorer" aria-label="Project explorer"><label><span>EXPEDITION INDEX</span><input type="search" data-explorer-filter value="${escapeHtml(this.explorerFilter)}" placeholder="Filter scenes and resources" aria-label="Filter scenes and resources" /></label><nav aria-label="Project files"><div class="scene-explorer-create"><button type="button" data-action="new-scene" title="New scene (in the last folder you opened)">＋ Scene</button><button type="button" data-action="new-folder" title="New folder (in the last folder you opened)">＋ Folder</button></div><h2><span>Project</span><small><em data-explorer-count="scene">${scenes.length}</em> scenes · <em data-explorer-count="resource">${resources.length}</em> resources</small></h2>${explorerTree || '<p>No scene documents or resources</p>'}</nav></aside><section class="scene-main">${this.renderTabs()}<section class="scene-workbench${animation ? ' has-animation-dock' : ''}">${treePanel}<section data-viewport-slot></section>${this.renderInspector()}${animation ? '<section data-animation-slot></section>' : ''}</section></section><footer class="scene-status" role="status"><span class="${state?.repairMode ? 'is-warning' : ''}">${escapeHtml(this.message)}</span><span>${state ? `${state.document.nodes.length} NODES · ${state.document.instances.length} INSTANCES${dirty ? ' · UNSAVED' : ''}` : resource ? `${escapeHtml(resource.document.kind.toUpperCase())} RESOURCE${dirty ? ' · UNSAVED' : ''}` : 'AUTHORING SYSTEM READY'}</span></footer>${this.creationSearch !== undefined ? this.renderCreationDialog() : ''}${this.instanceSearch !== undefined ? this.renderInstanceDialog() : ''}${this.fileDialog ? this.renderFileDialog() : ''}</main>`;
    this.applyExplorerFilter();
    const explorer = this.container.querySelector('.scene-explorer');
    if (explorer) explorer.scrollTop = explorerScroll;
    const tree = this.container.querySelector('.scene-tree-panel');
    if (tree) tree.scrollTop = treeScroll;
    this.liveViewport?.attach(this.container.querySelector('[data-viewport-slot]'));
    this.container.querySelector('[data-animation-slot]')?.replaceWith(this.animationPanel.element);
    this.animationPanel.restoreFocus(animationFocus);
    this.preview?.ensureBooted();
    this.schedulePreview();
    this.liveViewport?.update(this.viewportModel());
    if (this.pendingFrame && this.liveViewport && (!this.preview || this.preview.state.status === 'error' || !this.previewSession)) {
      this.pendingFrame = undefined;
      this.liveViewport.frameAll();
    } else if (this.pendingFrame && this.liveViewport && this.framedFor !== this.pendingFrame) {
      // Frame the composed layout immediately; the runtime bounds refine it once rendered.
      this.framedFor = this.pendingFrame;
      this.liveViewport.frameAll();
    }
    const instanceSearch = this.container.querySelector<HTMLInputElement>('[data-instance-search]');
    const fileName = this.container.querySelector<HTMLInputElement>('[data-file-field="name"]');
    if (fileName) {
      fileName.focus();
      fileName.setSelectionRange(fileName.value.length, fileName.value.length);
    } else if (instanceSearch) {
      instanceSearch.focus();
      instanceSearch.setSelectionRange(instanceSearch.value.length, instanceSearch.value.length);
    } else if (focused) {
      const element = this.container.querySelector<HTMLElement>(focused);
      element?.focus();
      if (element instanceof HTMLInputElement && element.dataset.explorerFilter !== undefined) element.setSelectionRange(element.value.length, element.value.length);
    } else if (viewportFocused) this.container.querySelector<HTMLElement>('.scene-viewport-overlay')?.focus({ preventScroll: true });
  }

  /**
   * Filters without re-rendering so the search box keeps focus. While a filter
   * is active, folders with matches are shown expanded and empty ones hidden;
   * clearing it restores the author's own expanded folders.
   */
  private applyExplorerFilter(): void {
    const filter = this.explorerFilter.trim().toLowerCase();
    const counts = { scene: 0, resource: 0 };
    for (const element of this.container.querySelectorAll<HTMLElement>('[data-explorer-item]')) {
      const visible = !filter || (element.dataset.explorerItem ?? '').includes(filter);
      element.hidden = !visible;
      if (visible) counts[element.dataset.sceneId ? 'scene' : 'resource'] += 1;
    }
    for (const [kind, count] of Object.entries(counts)) {
      const badge = this.container.querySelector(`[data-explorer-count="${kind}"]`);
      if (badge) badge.textContent = String(count);
    }
    for (const folder of this.container.querySelectorAll<HTMLElement>('[data-explorer-folder]')) {
      const matching = filter ? folder.querySelectorAll('[data-explorer-item]:not([hidden])').length : Number(folder.dataset.explorerTotal ?? 0);
      folder.hidden = Boolean(filter) && matching === 0;
      folder.classList.toggle('is-filter-open', Boolean(filter));
      const badge = folder.querySelector(':scope > button [data-explorer-folder-count]');
      if (badge) badge.textContent = String(matching);
    }
  }

  /** Expands every folder containing the document so the open file is visible. */
  private revealInExplorer(relativePath: string): void {
    for (const key of explorerFolderKeysFor(buildExplorerTree(this.catalog, this.folders), relativePath)) this.explorerOpen.add(key);
  }

  /** Folder toggles only change explorer DOM, avoiding a full studio re-render. */
  private toggleExplorerFolder(toggle: HTMLElement): void {
    const key = toggle.dataset.explorerFolderToggle ?? '';
    const open = !this.explorerOpen.has(key);
    if (open) this.explorerOpen.add(key); else this.explorerOpen.delete(key);
    toggle.closest('[data-explorer-folder]')?.classList.toggle('is-open', open);
    toggle.setAttribute('aria-expanded', String(open));
  }

  // -------------------------------------------------------------------------
  // New scene / new folder (Godot's FileSystem dock "New Scene..." and "New Folder...")
  // -------------------------------------------------------------------------

  /** Folder last opened in the explorer, else the active document's folder, else the root. */
  private defaultNewParent(): string {
    if (this.explorerFolder !== undefined && this.folders.includes(this.explorerFolder)) return this.explorerFolder;
    const path = this.relativePath ?? this.resourceRelativePath;
    return path && path.includes('/') ? path.slice(0, path.lastIndexOf('/')) : '';
  }

  private openFileDialog(mode: FileDialogState['mode'], parent: string): void {
    this.fileDialog = { mode, parent, name: '', sceneId: '', sceneIdEdited: false, rootType: COMMON_ROOT_TYPES[0] };
    this.render();
  }

  /** Updates dialog fields in place so typing keeps focus; only the derived hints change. */
  private updateFileDialogField(input: HTMLElement): void {
    const dialog = this.fileDialog;
    if (!dialog || !(input instanceof HTMLInputElement || input instanceof HTMLSelectElement)) return;
    const field = input.dataset.fileField;
    if (field === 'name') dialog.name = input.value.trim();
    else if (field === 'parent') dialog.parent = input.value;
    else if (field === 'root-type') dialog.rootType = input.value;
    else if (field === 'scene-id') { dialog.sceneId = input.value.trim(); dialog.sceneIdEdited = dialog.sceneId.length > 0; }
    dialog.error = undefined;
    if (!dialog.sceneIdEdited) {
      dialog.sceneId = suggestedSceneId(dialog.parent, dialog.name, this.catalog);
      const sceneIdInput = this.container.querySelector<HTMLInputElement>('[data-file-field="scene-id"]');
      if (sceneIdInput && sceneIdInput !== input) sceneIdInput.value = dialog.sceneId;
    }
    const preview = this.container.querySelector('[data-file-preview]');
    if (preview) preview.textContent = this.fileDialogPath(dialog);
    const error = this.container.querySelector('[data-file-error]');
    if (error) error.textContent = '';
  }

  private fileDialogPath(dialog: FileDialogState): string {
    const leaf = dialog.mode === 'scene' ? `${dialog.name || '…'}.scene.json` : dialog.name || '…';
    return dialog.parent ? `${dialog.parent}/${leaf}` : leaf;
  }

  private async submitFileDialog(): Promise<void> {
    const dialog = this.fileDialog;
    if (!dialog) return;
    try {
      if (!FILE_NAME_PATTERN.test(dialog.name)) throw new Error("Name must be lowercase letters and digits, with '.', '_' or '-' between them (e.g. crystal-cave)");
      const relativePath = this.fileDialogPath(dialog);
      if (dialog.mode === 'folder') {
        if (this.folders.includes(relativePath)) throw new Error(`Folder '${relativePath}' already exists`);
        const created = await this.repository.createFolder(relativePath);
        this.folders = [...this.folders, created].sort();
        for (let index = created.indexOf('/'); index >= 0; index = created.indexOf('/', index + 1)) this.explorerOpen.add(created.slice(0, index));
        this.explorerOpen.add(created);
        this.explorerFolder = created;
        this.fileDialog = undefined;
        this.message = `Created folder ${created}`;
        this.render();
        return;
      }
      const sceneId = dialog.sceneId || suggestedSceneId(dialog.parent, dialog.name, this.catalog);
      if (!FILE_NAME_PATTERN.test(sceneId)) throw new Error(`Scene ID '${sceneId}' must be lowercase letters and digits, with '.', '_' or '-' between them`);
      if (this.catalog.some((item) => item.kind === 'scene' && item.id === sceneId) || this.tabs.some((tab) => tab.key === `scene:${sceneId}`)) throw new Error(`Scene ID '${sceneId}' is already used`);
      if (this.catalog.some((item) => item.relativePath === relativePath) || this.tabs.some((tab) => tab.relativePath === relativePath)) throw new Error(`'${relativePath}' already exists`);
      if (!this.registry.nodeTypes.has(dialog.rootType)) throw new Error(`Unknown root node type '${dialog.rootType}'`);
      this.createSceneTab(toSceneId(sceneId), relativePath, dialog.rootType, rootNodeName(dialog.name));
    } catch (error) {
      dialog.error = error instanceof Error ? error.message : String(error);
      this.render();
    }
  }

  /** Opens an unsaved scene in a new tab; the first save writes it to `relativePath`. */
  private createSceneTab(sceneId: SceneId, relativePath: string, rootType: string, rootName: string): void {
    const rootId = authoredNodeId('root');
    const document: SceneDocument = {
      version: 1,
      sceneId,
      rootNodeId: rootId,
      nodes: [{ id: rootId, name: rootName, type: rootType, parentId: null, order: 0, properties: {} }],
      instances: [],
    };
    this.fileDialog = undefined;
    this.beginTab('scene', sceneId);
    this.state = new SceneDocumentState(document, { registry: this.registry });
    this.setLibraryScene(document);
    this.relativePath = relativePath;
    this.selectedKey = `:${rootId}`;
    this.message = `New scene · Save (Ctrl+S) writes ${relativePath}`;
    window.history.replaceState(null, '', formatSceneStudioRoute({ active: true, scene: sceneId }, window.location.search));
    this.frameInitial(`scene:${sceneId}`);
    this.render();
  }

  private renderFileDialog(): string {
    const dialog = this.fileDialog!;
    const scene = dialog.mode === 'scene';
    const folderOptions = ['', ...this.folders].map((folder) => `<option value="${escapeHtml(folder)}"${folder === dialog.parent ? ' selected' : ''}>${escapeHtml(folder ? `${folder}/` : '(content root)/')}</option>`).join('');
    const types = [...this.registry.nodeTypes.keys()].filter((type) => type !== 'ScriptNode');
    const ordered = [...COMMON_ROOT_TYPES.filter((type) => types.includes(type)), ...types.filter((type) => !COMMON_ROOT_TYPES.includes(type)).sort()];
    const typeOptions = ordered.map((type) => `<option value="${escapeHtml(type)}"${type === dialog.rootType ? ' selected' : ''}>${escapeHtml(type)}</option>`).join('');
    const sceneFields = scene
      ? `<label><span>Root node type</span><select data-file-field="root-type">${typeOptions}</select></label><label><span>Scene ID (referenced by instances and maps)</span><input type="text" data-file-field="scene-id" value="${escapeHtml(dialog.sceneId)}" placeholder="auto from folder and name" spellcheck="false" /></label>`
      : '';
    return `<div class="scene-dialog-backdrop"><form data-file-dialog class="scene-create-dialog scene-file-dialog" role="dialog" aria-modal="true" aria-labelledby="scene-file-title"><header><div><span>PROJECT FILES</span><h2 id="scene-file-title">${scene ? 'New scene' : 'New folder'}</h2></div><button type="button" data-action="close-file-dialog" aria-label="Close">×</button></header><label><span>In folder</span><select data-file-field="parent">${folderOptions}</select></label><label><span>${scene ? 'File name' : 'Folder name'}</span><input type="text" data-file-field="name" value="${escapeHtml(dialog.name)}" placeholder="${scene ? 'crystal-cave' : 'caves'}" spellcheck="false" autocomplete="off" /></label>${sceneFields}<p class="scene-file-preview"><span>Path</span><code data-file-preview>${escapeHtml(this.fileDialogPath(dialog))}</code></p><p class="scene-file-error" data-file-error role="alert">${escapeHtml(dialog.error ?? '')}</p><footer><button type="button" data-action="close-file-dialog">Cancel</button><button type="submit" class="scene-save">${scene ? 'Create scene' : 'Create folder'}</button></footer></form></div>`;
  }

  private renderCreationDialog(): string {
    const entries = sceneCreationEntries(this.registry, this.creationSearch);
    const query = (this.creationSearch ?? '').trim().toLowerCase();
    const templates = WORLD_AREA_TEMPLATES.filter((template) => !query || `${template.label} ${template.description} world area`.toLowerCase().includes(query));
    return `<div class="scene-dialog-backdrop"><section role="dialog" aria-modal="true" aria-labelledby="scene-create-title" class="scene-create-dialog"><header><div><span>REGISTRY</span><h2 id="scene-create-title">Add a universal node</h2></div><button type="button" data-action="close-create" aria-label="Close creation dialog">×</button></header><label><span>Search registered types</span><input autofocus type="search" data-creation-search value="${escapeHtml(this.creationSearch)}" /></label><div role="listbox">${templates.map((template) => `<button type="button" role="option" data-create-template="${escapeHtml(template.kind)}"><span>A</span><strong>${escapeHtml(template.label)}</strong><small>${escapeHtml(template.description)}</small></button>`).join('')}${entries.map((entry) => `<button type="button" role="option" ${entry.kind === 'script' ? `data-create-script-id="${escapeHtml(entry.id)}"` : `data-create-type="${escapeHtml(entry.id)}"`}><span>${entry.kind === 'script' ? 'S' : 'N'}</span><strong>${escapeHtml(entry.label)}</strong><small>${escapeHtml(entry.description)}</small></button>`).join('')}</div></section></div>`;
  }

  private fail(error: unknown): void { this.message = error instanceof Error ? error.message : String(error); this.render(); }

  private tileSetSummaries(): readonly SceneStudioContentSummary[] {
    return this.catalog.filter((item) => item.kind === 'resource' && item.relativePath.endsWith('.tile-set.resource.json'));
  }
}

function runtimeIdFor(node: ComposedSceneNode): string {
  // Must match STUDIO_PREVIEW_NAMESPACE in preview/StudioScenePreview.ts (kept literal to avoid loading Phaser eagerly).
  return runtimeNodeId('studio-preview', node.instancePath, node.nodeId);
}

function round2(value: number): number { return Math.round(value * 100) / 100; }

/** A complete authored source rectangle, or undefined for `{}` / partial values. */
function sourceRectValue(value: JsonValue | undefined): SourceOcclusionBounds | undefined {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const { offsetX, offsetY, width, height } = value as Readonly<Record<string, JsonValue>>;
  return typeof offsetX === 'number' && typeof offsetY === 'number' && typeof width === 'number' && typeof height === 'number' && width > 0 && height > 0
    ? { offsetX, offsetY, width, height }
    : undefined;
}

function localToGlobalPoint(transform: { readonly position: readonly [number, number]; readonly rotation: number; readonly scale: readonly [number, number] }, point: readonly [number, number]): readonly [number, number] {
  const x = point[0] * transform.scale[0];
  const y = point[1] * transform.scale[1];
  const cosine = Math.cos(transform.rotation);
  const sine = Math.sin(transform.rotation);
  return [transform.position[0] + x * cosine - y * sine, transform.position[1] + x * sine + y * cosine];
}

function uniqueId(base: string, taken: ReadonlySet<string>): AuthoredNodeId {
  const normalized = base.replace(/[^a-z0-9._-]+/gi, '-').toLowerCase() || 'node';
  let candidate = normalized;
  let suffix = 1;
  while (taken.has(candidate)) candidate = `${normalized}-${suffix++}`;
  return authoredNodeId(candidate);
}

function hashString(value: string): string {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) hash = Math.imul(hash ^ value.charCodeAt(index), 16777619);
  return (hash >>> 0).toString(36);
}

function shapeExtent(value: CollisionShapeValue): number {
  if (value.shape === 'rectangle') return Math.max(value.width, value.height) / 2 + 16;
  if (value.shape === 'circle') return value.radius + 16;
  if (value.shape === 'ellipse') return Math.max(value.radiusX, value.radiusY) + 16;
  return value.outerRadius + 16;
}

/**
 * Builds a throwaway scene that shows a resource through the real runtime:
 * tile sets become a one-row TileMapLayer2D, textures and sprite sheets become
 * Sprite2D nodes. Other kinds have no visual preview.
 */
function resourcePreviewScene(resource: SceneResourceDocument): { readonly document: SceneDocument; readonly resources: readonly SceneResourceDocument[] } | undefined {
  const root = { id: authoredNodeId('root'), name: 'ResourcePreview', type: 'Node2D', parentId: null, order: 0, properties: {} } as SceneNodeDocument;
  if (resource.kind === 'tile-set') {
    const tiles = Object.keys(resource.tiles);
    if (tiles.length === 0) return undefined;
    const data: TileDataResourceDocument = {
      version: 1,
      resourceId: toResourceId(`${resource.resourceId}.studio-preview-data`),
      kind: 'tile-data',
      tileSet: resource.resourceId,
      columns: tiles.length * 2,
      rows: 1,
      cells: tiles.map((tileId, index) => ({ x: index * 2, y: 0, tileId })),
    };
    return {
      document: { version: 1, sceneId: PREVIEW_SCENE_ID, rootNodeId: root.id, instances: [], nodes: [root, { id: authoredNodeId('tiles'), name: 'Tiles', type: 'TileMapLayer2D', parentId: root.id, order: 0, properties: { position: [0, 0], tileData: { resourceId: data.resourceId }, tileSize: 64, seed: 1, collisionEnabled: false } } as SceneNodeDocument] },
      resources: [data],
    };
  }
  if (resource.kind === 'texture' || resource.kind === 'sprite-sheet') {
    const frames = resource.kind === 'sprite-sheet' ? Math.min(64, Math.max(1, resource.frameCount ?? 16)) : 1;
    const width = resource.kind === 'sprite-sheet' ? resource.frameWidth : 128;
    const height = resource.kind === 'sprite-sheet' ? resource.frameHeight : 128;
    const columns = Math.ceil(Math.sqrt(frames));
    const nodes: SceneNodeDocument[] = [root];
    for (let frame = 0; frame < frames; frame += 1) {
      nodes.push({ id: authoredNodeId(`frame-${frame}`), name: `Frame ${frame}`, type: 'Sprite2D', parentId: root.id, order: frame, properties: { texture: { resourceId: resource.resourceId }, position: [(frame % columns) * (width + 8), Math.floor(frame / columns) * (height + 8)], ...(resource.kind === 'sprite-sheet' ? { frame } : {}) } } as SceneNodeDocument);
    }
    return { document: { version: 1, sceneId: PREVIEW_SCENE_ID, rootNodeId: root.id, instances: [], nodes }, resources: [] };
  }
  return undefined;
}

function renderResourceInspector(resource: SceneResourceDocument, usedBy: readonly SceneId[]): string {
  const fields = Object.entries(resource).filter(([key]) => !['version', 'resourceId', 'kind'].includes(key));
  const usage = `<section class="scene-resource-links" aria-label="Resource consumers"><header><span>USED BY ${usedBy.length} SCENE${usedBy.length === 1 ? '' : 'S'}</span></header>${usedBy.slice(0, 40).map((sceneId) => `<div><button type="button" class="scene-link" data-scene-id="${escapeHtml(sceneId)}">${escapeHtml(sceneId)}</button></div>`).join('')}${usedBy.length > 40 ? `<p>…and ${usedBy.length - 40} more</p>` : ''}</section>`;
  return `<aside class="scene-inspector scene-resource-inspector" aria-label="Resource inspector"><header><span>RESOURCE INSPECTOR</span><h2>${escapeHtml(resource.resourceId)}</h2><small>${escapeHtml(resource.kind)}</small></header><fieldset><legend>Authored fields</legend>${fields.map(([key, value]) => {
    const id = `resource-field-${key}`;
    const control = typeof value === 'boolean'
      ? `<input id="${escapeHtml(id)}" type="checkbox" data-resource-field="${escapeHtml(key)}" ${value ? 'checked' : ''} />`
      : typeof value === 'string'
        ? `<input id="${escapeHtml(id)}" type="text" data-resource-field="${escapeHtml(key)}" value="${escapeHtml(value)}" />`
        : `<textarea id="${escapeHtml(id)}" data-resource-field="${escapeHtml(key)}" rows="${Array.isArray(value) || typeof value === 'object' ? 12 : 2}" spellcheck="false">${escapeHtml(JSON.stringify(value, null, 2))}</textarea>`;
    return `<label class="scene-resource-field" for="${escapeHtml(id)}"><span>${escapeHtml(key)}</span>${control}</label>`;
  }).join('')}</fieldset>${usage}</aside>`;
}

function renderTileMapTools(context: TileMapContext, tileSets: readonly SceneStudioContentSummary[]): string {
  const region = context.effectiveRegion;
  const tileSetOptions = tileSets.map((item) => `<option value="${escapeHtml(item.id)}" ${item.id === context.tileSet.resourceId ? 'selected' : ''}>${escapeHtml(item.id)}</option>`).join('');
  return `<section class="scene-tile-tools" aria-label="Tile map tools"><header><span>TILE MAP CONTEXT</span><strong>${context.document.columns} × ${context.document.rows}</strong></header><div class="scene-tile-tool-row" role="toolbar" aria-label="Tile paint tools">${(['brush', 'erase', 'fill'] as const).map((tool) => `<button type="button" data-tile-tool="${tool}" aria-pressed="${context.tool === tool}">${tool}</button>`).join('')}</div><label class="scene-tile-field"><span>Brush footprint</span><select data-tile-brush-size><option value="1" ${context.brushSize === 1 ? 'selected' : ''}>1 × 1</option><option value="3" ${context.brushSize === 3 ? 'selected' : ''}>3 × 3</option><option value="5" ${context.brushSize === 5 ? 'selected' : ''}>5 × 5</option></select></label><label class="scene-tile-field"><span>Tile set</span><select data-tile-set>${tileSetOptions}</select></label><div class="scene-tile-palette" aria-label="Tile palette">${Object.entries(context.tileSet.tiles).map(([tileId, tile]) => `<button type="button" data-tile-id="${escapeHtml(tileId)}" class="${context.selectedTile === tileId ? 'is-selected' : ''}"><strong>${escapeHtml(tileId)}</strong><small>${tile.physics ? 'solid' : 'walkable'}</small></button>`).join('')}</div><div class="scene-tile-toggle-row"><button type="button" data-action="toggle-tile-collision" aria-pressed="${context.showCollision}">Collision</button><button type="button" data-action="toggle-effective-region" aria-pressed="${context.showEffectiveRegion}">Effective region</button></div><div class="scene-tile-layer-row"><button type="button" data-action="tile-layer-up">Layer ↑</button><button type="button" data-action="tile-layer-down">Layer ↓</button><button type="button" data-action="add-tile-layer">+ Layer</button></div><p>${region ? `Effective cells ${region.minX},${region.minY} → ${region.maxX},${region.maxY}` : 'Layer is empty'} · paint by clicking or dragging on the viewport; middle-drag or Space+drag pans.</p></section>`;
}

export function mountSceneStudio(container: HTMLElement): void {
  const controller = new SceneStudioController(container);
  (window as unknown as { sceneStudio?: SceneStudioController }).sceneStudio = controller;
  void controller.start();
}
