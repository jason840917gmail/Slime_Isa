import './character-studio.css';

import type { CharacterStudioAssetCatalog, CharacterStudioAssetEntry } from '../content/characters/characterAssetCatalog';
import type { AnimationPackageCatalog, AnimationPackageCatalogEntry, AnimationPackageDocument, AnimationPackageReference } from '../content/animations/types';
import { resolveAssetUrl } from '../infrastructure/assets/assetUrls';
import {
  layeredAnimationFrameAtStep,
  layeredTimelineFrameCount,
  normalizeAnimationBlockTransform,
  normalizeAnimationLayerTransform,
  type AnimationVisualBlockDocument,
  type AnimationVisualLayerDocument,
} from '../shared/animation';
import { SharedAnimationDocumentState } from './SharedAnimationDocumentState';
import { handleStudioHistoryShortcut } from './StudioHistoryShortcut';
import { renderLayeredAnimationBlockInspector } from './LayeredAnimationBlockInspector';
import {
  renderLayeredAnimationPreviewPanel,
  syncLayeredAnimationPreviewPlaybackButton,
  updateLayeredAnimationPreviewPlayback,
} from './LayeredAnimationPreviewPanel';
import { renderLayeredAnimationTimelinePanel } from './LayeredAnimationTimelinePanel';
import { createLayeredAnimationTimelineView, renderLayeredBlockHoldControls, renderLayeredBlockResizeHandle } from './LayeredAnimationTimelineView';
import { adjustPreviewZoom } from './PreviewZoom';
import { ensureStudioModeTabs } from './StudioModeTabs';
import { renderStudioLibraryTree, type StudioWeaponLibraryEntry } from './StudioLibraryTree';

interface WeaponCatalogResponse { readonly weapons: readonly StudioWeaponLibraryEntry[] }

export interface AnimationStudioOptions {
  readonly initialAnimationId?: string;
  readonly onSelectWeapon?: (weaponId: string) => void;
  readonly expandedFolders?: ReadonlySet<string>;
  readonly onExpandedFoldersChange?: (expandedFolders: ReadonlySet<string>) => void;
}

interface AnimationStudioState {
  readonly catalog?: AnimationPackageCatalog;
  readonly assets?: CharacterStudioAssetCatalog;
  readonly weapons: readonly StudioWeaponLibraryEntry[];
  readonly selectedPath?: string;
  readonly draft?: SharedAnimationDocumentState;
  readonly search: string;
  readonly expandedFolders: ReadonlySet<string>;
  readonly loading: boolean;
  readonly saving: boolean;
  readonly pickerOpen: boolean;
  readonly pickerFrames: readonly number[];
  readonly playing: boolean;
  readonly previewZoom: number;
  readonly previewSplit: number;
  readonly notice?: string;
}

interface ResizeDrag {
  readonly pointerId: number;
  readonly layerId: string;
  readonly blockIndex: number;
  readonly originalThrough: number;
  readonly startX: number;
  readonly frameWidth: number;
}

interface MoveDrag {
  readonly pointerId: number;
  readonly layerId: string;
  readonly blockIndex: number;
  readonly originalFrom: number;
  readonly startX: number;
  readonly frameWidth: number;
  readonly blockElement: HTMLElement;
  previewDelta: number;
}

interface WorkbenchSplitDrag {
  readonly pointerId: number;
  readonly startY: number;
  readonly startRatio: number;
  readonly availableHeight: number;
  readonly workbench: HTMLElement;
  lastRatio: number;
}

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>'"]/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;',
  })[character] ?? character);
}

async function loadJson<T>(url: string): Promise<T> {
  const response = await fetch(url);
  const payload = await response.json() as { ok?: boolean; data?: T; error?: { message?: string } };
  if (!response.ok || payload.ok === false || payload.data === undefined) throw new Error(payload.error?.message ?? `Failed to load ${url}`);
  return payload.data;
}

async function transact(body: unknown): Promise<AnimationPackageCatalog> {
  const response = await fetch('/__animation-library/transaction', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  });
  const payload = await response.json() as { ok?: boolean; data?: { catalog?: AnimationPackageCatalog }; error?: { message?: string } };
  if (!response.ok || !payload.ok || !payload.data?.catalog) throw new Error(payload.error?.message ?? 'Animation library transaction failed');
  return payload.data.catalog;
}

function spritesheets(state: AnimationStudioState): readonly CharacterStudioAssetEntry[] {
  return state.assets?.assets.filter((asset) => asset.kind === 'spritesheet') ?? [];
}

function assetInfo(asset: CharacterStudioAssetEntry | undefined) {
  const frame = asset?.frame;
  return {
    url: asset ? resolveAssetUrl(asset.sourcePath) : '',
    width: frame?.width ?? 1,
    height: frame?.height ?? 1,
    columns: frame?.columns ?? 1,
    rows: frame?.rows ?? 1,
    count: frame?.count ?? 1,
  };
}

function frameSprite(asset: CharacterStudioAssetEntry | undefined, sourceFrame: number, className: string): string {
  const info = assetInfo(asset);
  if (!info.url) return '<span class="layered-frame-missing">?</span>';
  const column = sourceFrame % info.columns;
  const row = Math.floor(sourceFrame / info.columns);
  return `<span class="${className}" style="--sheet-url:url('${escapeHtml(info.url)}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:${column * info.width}px;--frame-y:${row * info.height}px"></span>`;
}

function renderLibrary(state: AnimationStudioState, returnEditor: string): string {
  const selectedAnimationId = state.draft?.value.animationId;
  return renderStudioLibraryTree({
    weapons: state.weapons,
    animations: state.catalog?.packages ?? [],
    search: state.search,
    expandedFolders: state.expandedFolders,
    selectedAnimationId,
    footerHtml: `<button type="button" class="studio-button studio-button--outline" data-animation-action="new-folder">NEW FOLDER</button><button type="button" class="studio-button studio-button--outline" data-animation-action="new-package">NEW ANIMATION</button><button type="button" class="studio-button studio-button--outline" data-animation-action="duplicate" ${state.draft ? '' : 'disabled'}>DUPLICATE</button><button type="button" class="studio-button studio-button--outline" data-animation-action="move" ${state.draft ? '' : 'disabled'}>MOVE</button><button type="button" class="studio-button studio-button--danger" data-animation-action="delete" ${state.draft ? '' : 'disabled'}>DELETE</button><a class="studio-button studio-button--outline studio-button--navigation" href="?studio=characters&amp;editor=${encodeURIComponent(returnEditor)}">↗ CHARACTER STUDIO</a>`,
  });
}

function renderPreviewSprite(state: AnimationStudioState, layer: AnimationVisualLayerDocument, block: AnimationVisualBlockDocument, index: number): string {
  const info = assetInfo(state.assets?.assets.find((entry) => entry.assetId === layer.assetId));
  if (!info.url) return '';
  const layerTransform = normalizeAnimationLayerTransform(layer.transform);
  const blockTransform = normalizeAnimationBlockTransform(block.transform);
  const column = block.sourceFrame % info.columns;
  const row = Math.floor(block.sourceFrame / info.columns);
  const scaleX = layerTransform.scale[0] * blockTransform.scale[0] * 2.8;
  const scaleY = layerTransform.scale[1] * blockTransform.scale[1] * 2.8;
  return `<span class="stage-sprite stage-weapon-sprite${layer.layerId === state.draft?.value.animation.selection.layerId ? ' is-selected-layer' : ''}" data-preview-layer="${escapeHtml(layer.layerId)}" style="z-index:${3 + index};--sheet-url:url('${escapeHtml(info.url)}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:${column * info.width}px;--frame-y:${row * info.height}px;--preview-scale-x:${scaleX};--preview-scale-y:${scaleY};--origin-offset-x:${-layerTransform.origin[0] * info.width * scaleX}px;--origin-offset-y:${-layerTransform.origin[1] * info.height * scaleY}px;--offset-x:${(layerTransform.offset[0] + blockTransform.offset[0]) * 2.8}px;--offset-y:${(layerTransform.offset[1] + blockTransform.offset[1]) * 2.8}px;--weapon-rotation:${layerTransform.rotationDeg + blockTransform.rotationDeg}deg;--weapon-flip-x:${layerTransform.flipX !== blockTransform.flipX ? -1 : 1};--weapon-flip-y:${layerTransform.flipY !== blockTransform.flipY ? -1 : 1}"></span>`;
}

function renderPreview(state: AnimationStudioState): string {
  const value = state.draft?.value.animation;
  if (!value) return '';
  const { animation, selection } = value;
  const sprites = animation.layers.flatMap((layer, index) => {
    const block = layer.blocks.find((candidate) => candidate.from <= selection.playhead && selection.playhead <= candidate.through);
    return block ? [renderPreviewSprite(state, layer, block, index)] : [];
  }).join('');
  const activeLayerCount = animation.layers.filter((layer) => layer.blocks.some((candidate) => candidate.from <= selection.playhead && selection.playhead <= candidate.through)).length;
  return renderLayeredAnimationPreviewPanel({
    kicker: 'SHARED PREVIEW',
    summaryHtml: `${Number(selection.playhead / animation.framesPerSecond).toFixed(2)}s / ${animation.durationSeconds.toFixed(2)}s · ${activeLayerCount} active layer${activeLayerCount === 1 ? '' : 's'}`,
    previewZoom: state.previewZoom,
    playing: state.playing,
    sceneHtml: `<span class="stage-axis stage-axis-x"></span><span class="stage-axis stage-axis-y"></span><span class="stage-anchor">+</span><span class="stage-label">PACKAGE ORIGIN</span>${sprites || '<p class="studio-empty-note">No tile at this time.</p>'}<span class="stage-caption"><b>${escapeHtml(state.draft?.value.displayName)}</b><span>${selection.playhead + 1} / ${layeredTimelineFrameCount(animation)} · shared package</span></span>`,
    footerHtml: '<span><i class="legend-dot legend-dot--cyan"></i> shared clock</span><span><i class="legend-dot legend-dot--amber"></i> selected visual layer</span><span>Wheel over preview to zoom · Same preview frame as weapon animations.</span>',
  });
}

function renderTimeline(state: AnimationStudioState): string {
  const value = state.draft?.value.animation;
  if (!value) return '';
  const { animation, selection } = value;
  const timeline = createLayeredAnimationTimelineView(animation);
  return renderLayeredAnimationTimelinePanel({
    titleHtml: `${animation.framesPerSecond} FPS · ${timeline.effectiveDurationSeconds.toFixed(2)}s`,
    hint: 'Select a tile to edit timing, rotation, and mirroring.', timeline,
    selectedLayerId: selection.layerId, selectedBlockIndex: selection.blockIndex, playhead: selection.playhead,
    renderBlock: (layerId, blockIndex) => {
      const block = animation.layers.find((layer) => layer.layerId === layerId)!.blocks[blockIndex];
      const selected = layerId === selection.layerId && blockIndex === selection.blockIndex;
      const asset = state.assets?.assets.find((entry) => entry.assetId === animation.layers.find((layer) => layer.layerId === layerId)?.assetId);
      const hold = block.through - block.from + 1;
      const startSeconds = Number(block.from / animation.framesPerSecond).toFixed(2);
      return `<article class="timeline-frame layered-timeline-block${selected ? ' is-selected' : ''}" style="grid-column:${block.from + 1} / span ${hold}" data-layer-block data-layer-id="${escapeHtml(layerId)}" data-block-index="${blockIndex}"><button type="button" class="timeline-frame-select" data-select-block data-layer-id="${escapeHtml(layerId)}" data-block-index="${blockIndex}" aria-label="Select tile from source frame ${block.sourceFrame}, starting at ${startSeconds} seconds. Drag horizontally to change its start time." title="Drag horizontally to change start time">${frameSprite(asset, block.sourceFrame, 'timeline-tile-preview')}<b class="timeline-frame-number">${String(block.from).padStart(2, '0')}</b><small class="timeline-frame-source">SRC ${block.sourceFrame}</small><span class="timeline-frame-hold">${Number(hold / animation.framesPerSecond).toFixed(2)}s / ${hold}F</span></button>${renderLayeredBlockHoldControls(layerId, blockIndex, hold)}<button type="button" class="layered-block-delete" data-animation-action="delete-block" data-layer-id="${escapeHtml(layerId)}" data-block-index="${blockIndex}" aria-label="Delete block">×</button>${renderLayeredBlockResizeHandle(layerId, blockIndex, hold)}</article>`;
    },
  });
}

function numberField(label: string, field: string, value: number, step = '1'): string {
  return `<label class="studio-field"><span>${label}</span><input type="number" step="${step}" value="${value}" data-animation-edit="${field}" /></label>`;
}

function renderInspector(state: AnimationStudioState): string {
  const draft = state.draft;
  if (!draft) return '';
  const value = draft.value;
  const { animation, selection } = value.animation;
  const layer = animation.layers.find((candidate) => candidate.layerId === selection.layerId);
  const block = layer && selection.blockIndex !== undefined ? layer.blocks[selection.blockIndex] : undefined;
  const layerTransform = layer ? normalizeAnimationLayerTransform(layer.transform) : undefined;
  const assetOptions = spritesheets(state).map((asset) => `<option value="${escapeHtml(asset.assetId)}" ${asset.assetId === layer?.assetId ? 'selected' : ''}>${escapeHtml(asset.assetId)}</option>`).join('');
  const blockInspector = block ? `${renderLayeredAnimationBlockInspector({ block, framesPerSecond: animation.framesPerSecond, timelineFrames: layeredTimelineFrameCount(animation) })}<button type="button" class="studio-button studio-button--danger" data-animation-action="delete-block">DELETE TILE</button>` : '<p class="studio-empty-note">Select a tile to edit its transform.</p>';
  return `<aside class="studio-inspector layered-weapon-inspector"><div class="studio-inspector-heading"><span class="studio-kicker">Inspector</span><h2>Animation controls</h2><p>Stable ID: <code>${escapeHtml(value.animationId)}</code></p></div><div class="studio-inspector-scroll"><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Package</span><strong>Metadata</strong></div><label class="studio-field"><span>Display name</span><input type="text" value="${escapeHtml(value.displayName)}" data-animation-metadata="displayName" /></label><label class="studio-field"><span>Description</span><textarea data-animation-metadata="description">${escapeHtml(value.description)}</textarea></label><div class="studio-field-grid">${numberField('FPS', 'fps', animation.framesPerSecond)}${numberField('Duration', 'duration', animation.durationSeconds, '0.05')}<label class="studio-field studio-field--toggle"><span>Loop</span><input type="checkbox" ${animation.loop ? 'checked ' : ''}data-animation-edit="loop" /></label><label class="studio-field"><span>Loop mode</span><select data-animation-edit="loopMode"><option value="wrap" ${(animation.loopMode ?? 'wrap') === 'wrap' ? 'selected' : ''}>Wrap</option><option value="ping-pong" ${animation.loopMode === 'ping-pong' ? 'selected' : ''}>Ping-pong</option></select></label></div></section>${layer && layerTransform ? `<section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Visual layer</span><strong>${escapeHtml(layer.displayName)}</strong></div><label class="studio-field"><span>Layer name</span><input type="text" value="${escapeHtml(layer.displayName)}" data-layer-edit="displayName" /></label><label class="studio-field"><span>Source sheet</span><select data-layer-edit="assetId">${assetOptions}</select></label><div class="studio-field-grid">${numberField('Depth', 'layerDepth', layer.depthOffset, '0.1')}${numberField('Offset X', 'layerOffsetX', layerTransform.offset[0], '0.25')}${numberField('Offset Y', 'layerOffsetY', layerTransform.offset[1], '0.25')}${numberField('Scale X', 'layerScaleX', layerTransform.scale[0], '0.05')}${numberField('Scale Y', 'layerScaleY', layerTransform.scale[1], '0.05')}${numberField('Rotation', 'layerRotation', layerTransform.rotationDeg)}</div><div class="layered-layer-actions"><button type="button" class="studio-button studio-button--quiet" data-animation-action="layer-front">↑ FRONT</button><button type="button" class="studio-button studio-button--quiet" data-animation-action="layer-back">↓ BACK</button><button type="button" class="studio-button studio-button--danger" data-animation-action="delete-layer">DELETE LAYER</button></div>${blockInspector}</section>` : '<section class="studio-inspector-section"><p class="studio-empty-note">Add a visual layer to begin.</p></section>'}</div></aside>`;
}

function renderFramePicker(state: AnimationStudioState): string {
  if (!state.pickerOpen || !state.draft) return '';
  const selection = state.draft.value.animation.selection;
  const layer = state.draft.value.animation.animation.layers.find((candidate) => candidate.layerId === selection.layerId);
  const info = assetInfo(state.assets?.assets.find((entry) => entry.assetId === layer?.assetId));
  return `<div class="studio-asset-shelf-backdrop layered-tile-picker-backdrop" data-picker-backdrop><section class="studio-asset-shelf weapon-tile-picker" role="dialog" aria-modal="true" aria-labelledby="shared-tile-picker-title"><header class="studio-asset-shelf-heading"><div><span class="studio-kicker">${escapeHtml(layer?.displayName ?? 'Layer')} source</span><h2 id="shared-tile-picker-title">Add tiles to animation</h2><p>Select one or more source tiles, then add them at the current playhead.</p></div><button type="button" class="studio-icon-button" data-action="close-picker" aria-label="Close">×</button></header><div class="studio-sheet-grid projectile-frame-grid weapon-picker-grid">${Array.from({ length: info.count }, (_, frame) => `<button type="button" class="projectile-frame-option${state.pickerFrames.includes(frame) ? ' is-selected' : ''}" data-picker-frame="${frame}" aria-pressed="${state.pickerFrames.includes(frame)}">${frameSprite(state.assets?.assets.find((entry) => entry.assetId === layer?.assetId), frame, 'projectile-frame-preview')}<span>${String(frame).padStart(2, '0')}</span></button>`).join('')}</div><footer class="weapon-tile-picker-footer"><span>${state.pickerFrames.length} selected · inserted at playhead ${selection.playhead}</span><div><button type="button" class="studio-button studio-button--quiet" data-action="close-picker">CANCEL</button><button type="button" class="studio-button studio-button--accent" data-action="confirm-picker" ${state.pickerFrames.length ? '' : 'disabled'}>ADD TO LAYER</button></div></footer></section></div>`;
}

function renderStudio(container: HTMLDivElement, state: AnimationStudioState, returnEditor: string): void {
  const draft = state.draft;
  const issues = draft?.validate() ?? [];
  container.innerHTML = `<main class="character-studio weapon-studio layered-weapon-studio animation-studio${draft?.value.dirty ? ' is-dirty' : ''}"><header class="studio-topbar"><a class="studio-brand" href="?" aria-label="Back to game"><span class="brand-mark">✦</span><span><small>FIELD CARTOGRAPHER</small><strong>WEAPON STUDIO</strong></span></a><div class="studio-topbar-actions"><span class="studio-save-state${state.notice || issues.length ? ' is-error' : ''}"><i></i>${escapeHtml(state.notice ?? issues[0] ?? (draft?.value.dirty ? 'Unsaved shared animation' : 'Shared animation selected'))}</span>${draft ? `<button type="button" class="studio-button studio-button--save" data-animation-action="save" ${state.saving || !draft.value.dirty || issues.length ? 'disabled' : ''}>${state.saving ? 'SAVING…' : 'SAVE ANIMATION'}</button>` : ''}</div></header><div class="studio-layout">${renderLibrary(state, returnEditor)}${state.loading ? '<section class="studio-empty-state"><span class="studio-loading-orb">✦</span><h2>Loading shared animations</h2></section>' : draft ? `<section class="studio-workbench" style="--preview-split:${state.previewSplit}fr;--controls-split:${100 - state.previewSplit}fr"><div class="studio-workbench-heading"><div><span class="studio-kicker">Shared animation package</span><h2>${escapeHtml(draft.value.displayName)}</h2></div><div class="studio-workbench-meta"><span>ID <b>${escapeHtml(draft.value.animationId)}</b></span><span>PATH <b>${escapeHtml(state.selectedPath)}</b></span></div></div>${renderPreview(state)}<button type="button" class="layered-workbench-splitter" data-workbench-splitter aria-label="Resize preview and timeline" aria-valuemin="25" aria-valuemax="75" aria-valuenow="${state.previewSplit}" title="Drag to resize preview and timeline"><span></span></button><div class="layered-workbench-bottom layered-workbench-bottom--timeline">${renderTimeline(state)}</div></section>${renderInspector(state)}` : '<section class="studio-empty-state"><span class="studio-loading-orb">✦</span><h2>Select or create an animation</h2></section>'}</div>${renderFramePicker(state)}</main>`;
  ensureStudioModeTabs(container, returnEditor, 'weapons');
}

function newPackageDocument(animationId: string, displayName: string, description: string, assetId: string, loop: boolean): AnimationPackageDocument {
  return { $schema: './animation-package.schema.json', version: 1, animationId, displayName, description, animation: { version: 2, durationSeconds: 0.5, framesPerSecond: 8, loop, loopMode: 'wrap', layers: [{ layerId: 'base', displayName: 'Base', assetId, depthOffset: 0, blocks: [{ from: 0, through: 3, sourceFrame: 0 }] }] } };
}

export function mountAnimationStudio(container: HTMLDivElement, options: AnimationStudioOptions = {}): () => void {
  container.classList.add('is-character-studio-host');
  const returnEditor = new URLSearchParams(window.location.search).get('editor') ?? 'meadow-crossing';
  let state: AnimationStudioState = { weapons: [], search: '', expandedFolders: new Set(options.expandedFolders ?? ['weapons', 'animations']), loading: true, saving: false, pickerOpen: false, pickerFrames: [], playing: false, previewZoom: 1, previewSplit: 55 };
  let resize: ResizeDrag | undefined;
  let move: MoveDrag | undefined;
  let splitDrag: WorkbenchSplitDrag | undefined;
  let suppressedBlockClick: string | undefined;
  let playbackTimer: number | undefined;
  let playbackGeneration = 0;
  let playbackStep = 0;
  const stopPlayback = (): void => {
    playbackGeneration += 1;
    if (playbackTimer !== undefined) window.clearInterval(playbackTimer);
    playbackTimer = undefined;
    state = { ...state, playing: false };
    syncLayeredAnimationPreviewPlaybackButton(container, false);
  };
  const render = (): void => {
    const workbench = container.querySelector<HTMLElement>('.studio-workbench');
    const inspector = container.querySelector<HTMLElement>('.studio-inspector-scroll');
    const roster = container.querySelector<HTMLElement>('.studio-tree');
    const workbenchScroll = workbench ? { top: workbench.scrollTop, left: workbench.scrollLeft } : undefined;
    const inspectorScroll = inspector?.scrollTop ?? 0;
    const rosterScroll = roster?.scrollTop ?? 0;
    renderStudio(container, state, returnEditor);
    const nextWorkbench = container.querySelector<HTMLElement>('.studio-workbench');
    if (nextWorkbench && workbenchScroll) { nextWorkbench.scrollTop = workbenchScroll.top; nextWorkbench.scrollLeft = workbenchScroll.left; }
    const nextInspector = container.querySelector<HTMLElement>('.studio-inspector-scroll');
    if (nextInspector) nextInspector.scrollTop = inspectorScroll;
    const nextRoster = container.querySelector<HTMLElement>('.studio-tree');
    if (nextRoster) nextRoster.scrollTop = rosterScroll;
  };
  const openEntry = (entry: AnimationPackageCatalogEntry): void => {
    stopPlayback();
    state = { ...state, selectedPath: entry.packagePath, draft: new SharedAnimationDocumentState(entry), notice: undefined, pickerOpen: false, pickerFrames: [], previewZoom: 1 };
    render();
    window.requestAnimationFrame(() => {
      const roster = container.querySelector<HTMLElement>('.studio-tree');
      const selected = container.querySelector<HTMLElement>(`[data-animation-id="${CSS.escape(entry.animationId)}"]`);
      if (!roster || !selected) return;
      const rosterBounds = roster.getBoundingClientRect();
      const selectedBounds = selected.getBoundingClientRect();
      if (selectedBounds.top < rosterBounds.top) roster.scrollTop -= rosterBounds.top - selectedBounds.top + 8;
      else if (selectedBounds.bottom > rosterBounds.bottom) roster.scrollTop += selectedBounds.bottom - rosterBounds.bottom + 8;
    });
  };
  const refresh = async (preferredPath = state.selectedPath): Promise<void> => {
    const catalog = await loadJson<AnimationPackageCatalog>('/__animation-library/catalog');
    const selected = catalog.packages.find((entry) => entry.packagePath === preferredPath) ?? catalog.packages[0];
    state = { ...state, catalog, loading: false, saving: false, selectedPath: selected?.packagePath, draft: selected ? new SharedAnimationDocumentState(selected) : undefined };
    render();
  };
  const mutateAnimation = (operation: Parameters<SharedAnimationDocumentState['mutateAnimation']>[0], failure = 'That animation edit could not be applied.'): void => {
    if (!state.draft?.mutateAnimation(operation)) state = { ...state, notice: failure };
    else state = { ...state, notice: undefined };
    render();
  };
  const applyHistory = (redo: boolean): boolean => {
    const draft = state.draft;
    if (!draft) return false;
    const changed = redo ? draft.redo() : draft.undo();
    if (!changed) return false;
    stopPlayback();
    state = { ...state, playing: false, notice: undefined };
    render();
    return true;
  };

  const handleClick = (event: MouseEvent): void => {
    const rawTarget = event.target instanceof Element ? event.target : undefined;
    if (rawTarget === rawTarget?.closest('[data-picker-backdrop]')) { state = { ...state, pickerOpen: false, pickerFrames: [] }; render(); return; }
    const target = rawTarget?.closest<HTMLElement>('[data-animation-id], [data-weapon-id], [data-animation-action], [data-action], [data-select-layer], [data-select-block], [data-layered-playhead-frame], [data-block-hold-delta], [data-picker-frame]');
    if (!target) return;
    const weaponId = target.dataset.weaponId;
    if (weaponId) {
      if (state.draft?.value.dirty && !window.confirm('Discard unsaved animation changes?')) return;
      queueMicrotask(() => options.onSelectWeapon?.(weaponId));
      return;
    }
    const animationId = target.dataset.animationId;
    if (animationId) {
      if (state.draft?.value.dirty && !window.confirm('Discard unsaved animation changes?')) return;
      const entry = state.catalog?.packages.find((candidate) => candidate.animationId === animationId);
      if (entry) openEntry(entry);
      return;
    }
    const layerId = target.dataset.layerId ?? target.dataset.selectLayer;
    const blockIndex = target.dataset.blockIndex === undefined ? undefined : Number(target.dataset.blockIndex);
    if (target.dataset.selectBlock !== undefined && layerId && blockIndex !== undefined) {
      const blockKey = `${layerId}:${blockIndex}`;
      if (suppressedBlockClick === blockKey) { suppressedBlockClick = undefined; return; }
      mutateAnimation((document) => document.selectBlock(layerId, blockIndex)); return;
    }
    if (target.dataset.selectLayer && layerId) { mutateAnimation((document) => document.selectLayer(layerId)); return; }
    if (target.dataset.layeredPlayheadFrame !== undefined) { mutateAnimation((document) => { document.setPlayhead(Number(target.dataset.layeredPlayheadFrame)); return true; }); return; }
    if (target.dataset.blockHoldDelta && layerId && blockIndex !== undefined) { mutateAnimation((document) => document.adjustBlockHold(layerId, blockIndex, Number(target.dataset.blockHoldDelta))); return; }
    if (target.dataset.pickerFrame !== undefined) {
      const frame = Number(target.dataset.pickerFrame);
      state = { ...state, pickerFrames: state.pickerFrames.includes(frame) ? state.pickerFrames.filter((value) => value !== frame) : [...state.pickerFrames, frame] };
      render();
      return;
    }
    const action = target.dataset.animationAction ?? target.dataset.action;
    if (!action) return;
    if (action === 'save' && state.draft && state.selectedPath && state.catalog) {
      const entry = state.catalog.packages.find((candidate) => candidate.packagePath === state.selectedPath);
      if (!entry) return;
      const catalogRevision = state.catalog.revision;
      const packageDocument = state.draft.toDocument();
      state = { ...state, saving: true, notice: undefined }; render();
      void transact({ expectedCatalogRevision: catalogRevision, writes: [{ packagePath: entry.packagePath, expectedRevision: entry.revision, operation: 'update', package: packageDocument }] })
        .then(() => refresh(entry.packagePath)).then(() => { state = { ...state, saving: false, notice: 'Animation saved.' }; render(); })
        .catch((error: unknown) => { state = { ...state, saving: false, notice: error instanceof Error ? error.message : String(error) }; render(); });
      return;
    }
    if (action === 'new-folder' && state.catalog) {
      const folder = window.prompt('New folder path (lowercase kebab-case segments):', 'objects/new-folder')?.trim();
      if (!folder) return;
      void transact({ expectedCatalogRevision: state.catalog.revision, createFolders: [folder] }).then(() => refresh()).catch((error: unknown) => { state = { ...state, notice: error instanceof Error ? error.message : String(error) }; render(); });
      return;
    }
    if (action === 'new-package' && state.catalog) {
      const folder = window.prompt('Package folder path:', 'objects/new-animation')?.trim();
      const animationId = window.prompt('Stable animation ID:', 'object.new-animation.idle')?.trim();
      if (!folder || !animationId) return;
      const displayName = window.prompt('Display name:', 'New animation')?.trim() || 'New animation';
      const description = window.prompt('Description:', 'Reusable shared animation package.')?.trim() || 'Reusable shared animation package.';
      const assetId = spritesheets(state)[0]?.assetId;
      if (!assetId) { state = { ...state, notice: 'No spritesheet asset is available.' }; render(); return; }
      const packagePath = `${folder.replace(/\/+$/g, '')}/animation.json`;
      const packageValue = newPackageDocument(animationId, displayName, description, assetId, window.confirm('Should this animation loop?'));
      void transact({ expectedCatalogRevision: state.catalog.revision, writes: [{ packagePath, operation: 'create', package: packageValue }] }).then(() => refresh(packagePath)).catch((error: unknown) => { state = { ...state, notice: error instanceof Error ? error.message : String(error) }; render(); });
      return;
    }
    if (action === 'duplicate' && state.catalog && state.draft) {
      const folder = window.prompt('Duplicate package folder:', `${state.selectedPath?.replace(/\/animation\.json$/, '')}-copy`)?.trim();
      const animationId = window.prompt('New stable animation ID:', `${state.draft.value.animationId}.copy`)?.trim();
      if (!folder || !animationId) return;
      const packagePath = `${folder.replace(/\/+$/g, '')}/animation.json`;
      const source = state.draft.toDocument();
      const packageValue = { ...source, animationId, displayName: `${source.displayName} Copy` };
      void transact({ expectedCatalogRevision: state.catalog.revision, writes: [{ packagePath, operation: 'create', package: packageValue }] }).then(() => refresh(packagePath)).catch((error: unknown) => { state = { ...state, notice: error instanceof Error ? error.message : String(error) }; render(); });
      return;
    }
    if (action === 'move' && state.catalog && state.draft && state.selectedPath) {
      const folder = window.prompt('Move package to folder:', state.selectedPath.replace(/\/animation\.json$/, ''))?.trim();
      if (!folder) return;
      const destination = `${folder.replace(/\/+$/g, '')}/animation.json`;
      const source = state.catalog.packages.find((entry) => entry.packagePath === state.selectedPath);
      if (!source || destination === source.packagePath) return;
      void transact({ expectedCatalogRevision: state.catalog.revision, writes: [{ packagePath: destination, operation: 'create', package: state.draft.toDocument() }], deletes: [{ packagePath: source.packagePath, expectedRevision: source.revision }] }).then(() => refresh(destination)).catch((error: unknown) => { state = { ...state, notice: error instanceof Error ? error.message : String(error) }; render(); });
      return;
    }
    if (action === 'delete' && state.catalog && state.draft && state.selectedPath) {
      const entry = state.catalog.packages.find((candidate) => candidate.packagePath === state.selectedPath);
      if (!entry) return;
      void loadJson<readonly AnimationPackageReference[]>(`/__animation-library/references?animationId=${encodeURIComponent(entry.animationId)}`).then((references) => {
        if (references.length > 0) { state = { ...state, notice: `Delete blocked: ${references.map((reference) => `${reference.ownerKind} ${reference.ownerId} · ${reference.field}`).join('; ')}` }; render(); return; }
        if (!window.confirm(`Delete ${entry.displayName}?`)) return;
        void transact({ expectedCatalogRevision: state.catalog!.revision, deletes: [{ packagePath: entry.packagePath, expectedRevision: entry.revision }] }).then(() => refresh(undefined)).catch((error: unknown) => { state = { ...state, notice: error instanceof Error ? error.message : String(error) }; render(); });
      }).catch((error: unknown) => { state = { ...state, notice: error instanceof Error ? error.message : String(error) }; render(); });
      return;
    }
    const selection = state.draft?.value.animation.selection;
    if (action === 'preview-zoom-in') { state = { ...state, previewZoom: adjustPreviewZoom(state.previewZoom, -1) }; render(); return; }
    if (action === 'preview-zoom-out') { state = { ...state, previewZoom: adjustPreviewZoom(state.previewZoom, 1) }; render(); return; }
    if (action === 'preview-zoom-reset') { state = { ...state, previewZoom: 1 }; render(); return; }
    if (action === 'play-preview' && state.draft) {
      if (state.playing) { stopPlayback(); render(); return; }
      const draft = state.draft;
      const animation = draft.value.animation.animation;
      if (playbackTimer !== undefined) window.clearInterval(playbackTimer);
      playbackTimer = undefined;
      const generation = ++playbackGeneration;
      playbackStep = 0;
      state = { ...state, playing: true }; render();
      playbackTimer = window.setInterval(() => {
        if (generation !== playbackGeneration || !state.playing) return;
        const current = state.draft?.value.animation;
        if (!current) { stopPlayback(); render(); return; }
        const count = layeredTimelineFrameCount(current.animation);
        const nextStep = playbackStep + 1;
        if (nextStep >= count && !current.animation.loop) { stopPlayback(); render(); return; }
        playbackStep = nextStep;
        const next = layeredAnimationFrameAtStep(current.animation, playbackStep);
        if (!draft.mutateAnimation((document) => { document.setPlayhead(next % count); return true; })) { stopPlayback(); render(); return; }
        const updated = draft.value.animation;
        updateLayeredAnimationPreviewPlayback(container, renderPreview(state), updated.selection.playhead);
      }, 1000 / animation.framesPerSecond);
      return;
    }
    if (action === 'add-layer') {
      const assetId = spritesheets(state)[0]?.assetId;
      const animation = state.draft?.value.animation.animation;
      if (!assetId || !animation) return;
      let index = animation.layers.length + 1;
      while (animation.layers.some((layer) => layer.layerId === `layer-${index}`)) index += 1;
      mutateAnimation((document) => document.addLayer({ layerId: `layer-${index}`, displayName: `Layer ${index}`, assetId, depthOffset: animation.layers.length, blocks: [] }));
      return;
    }
    if (action === 'add-layer-tiles') { state = { ...state, pickerOpen: true, pickerFrames: [] }; render(); return; }
    if (action === 'close-picker') { state = { ...state, pickerOpen: false, pickerFrames: [] }; render(); return; }
    if (action === 'confirm-picker') {
      const frames = [...state.pickerFrames];
      const activeSelection = state.draft?.value.animation.selection;
      state = { ...state, pickerOpen: false, pickerFrames: [] };
      if (activeSelection?.layerId) mutateAnimation((document) => document.placeTiles(activeSelection.layerId!, frames, activeSelection.playhead), 'Those tiles could not be placed inside the animation duration.');
      else render();
      return;
    }
    if (action === 'layer-front' && selection?.layerId) { mutateAnimation((document) => document.moveLayer(selection.layerId!, 1)); return; }
    if (action === 'layer-back' && selection?.layerId) { mutateAnimation((document) => document.moveLayer(selection.layerId!, -1)); return; }
    if (action === 'delete-layer' && selection?.layerId) { mutateAnimation((document) => document.deleteLayer(selection.layerId!)); return; }
    if (action === 'delete-block') {
      const targetLayerId = target.dataset.layerId ?? selection?.layerId;
      const targetBlockIndex = target.dataset.blockIndex === undefined ? selection?.blockIndex : Number(target.dataset.blockIndex);
      if (targetLayerId && targetBlockIndex !== undefined) mutateAnimation((document) => document.deleteBlock(targetLayerId, targetBlockIndex));
      return;
    }
    if (action === 'duplicate-block' && selection?.layerId && selection.blockIndex !== undefined) { mutateAnimation((document) => document.duplicateBlock(selection.layerId!, selection.blockIndex!)); return; }
    if (action === 'reset-block-transform' && selection?.layerId && selection.blockIndex !== undefined) mutateAnimation((document) => document.setBlockTransform(selection.layerId!, selection.blockIndex!));
  };

  const handleInput = (event: Event): void => {
    const target = event.target;
    if (!(target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement)) return;
    if (target.dataset.studioLibrarySearch !== undefined) { state = { ...state, search: target.value }; render(); container.querySelector<HTMLInputElement>('[data-studio-library-search]')?.focus(); return; }
    const metadata = target.dataset.animationMetadata;
    if (metadata && state.draft) { state.draft.updateMetadata(metadata === 'displayName' ? { displayName: target.value } : { description: target.value }); render(); return; }
    const selection = state.draft?.value.animation.selection;
    const animationEdit = target.dataset.animationEdit;
    if (animationEdit) {
      if (animationEdit === 'fps') mutateAnimation((document) => document.setFramesPerSecond(Number(target.value)));
      else if (animationEdit === 'duration') mutateAnimation((document) => document.setDurationSeconds(Number(target.value)));
      else if (animationEdit === 'loop' && target instanceof HTMLInputElement) mutateAnimation((document) => document.setLoop(target.checked));
      else if (animationEdit === 'loopMode') mutateAnimation((document) => document.setLoopMode(target.value === 'ping-pong' ? 'ping-pong' : 'wrap'));
      else if (selection?.layerId) {
        const layer = state.draft?.value.animation.animation.layers.find((candidate) => candidate.layerId === selection.layerId);
        if (!layer) return;
        const transform = normalizeAnimationLayerTransform(layer.transform);
        const offset = [...transform.offset] as [number, number];
        const scale = [...transform.scale] as [number, number];
        if (animationEdit === 'layerOffsetX') offset[0] = Number(target.value);
        if (animationEdit === 'layerOffsetY') offset[1] = Number(target.value);
        if (animationEdit === 'layerScaleX') scale[0] = Number(target.value);
        if (animationEdit === 'layerScaleY') scale[1] = Number(target.value);
        if (animationEdit === 'layerDepth') mutateAnimation((document) => document.setLayerDepth(selection.layerId!, Number(target.value)));
        else mutateAnimation((document) => document.setLayerTransform(selection.layerId!, { ...transform, offset, scale, rotationDeg: animationEdit === 'layerRotation' ? Number(target.value) : transform.rotationDeg }));
      }
      return;
    }
    const layerEdit = target.dataset.layerEdit;
    if (layerEdit && selection?.layerId) { mutateAnimation((document) => layerEdit === 'displayName' ? document.renameLayer(selection.layerId!, target.value) : document.setLayerAsset(selection.layerId!, target.value)); return; }
    if (target.dataset.blockTimingField === 'startSeconds' && selection?.layerId && selection.blockIndex !== undefined) {
      const fps = state.draft?.value.animation.animation.framesPerSecond ?? 1;
      mutateAnimation((document) => document.moveBlock(selection.layerId!, selection.blockIndex!, Number(target.value) * fps));
      return;
    }
    const blockField = target.dataset.blockTransformField;
    if (blockField && selection?.layerId && selection.blockIndex !== undefined) {
      const block = state.draft?.value.animation.animation.layers.find((layer) => layer.layerId === selection.layerId)?.blocks[selection.blockIndex];
      if (!block) return;
      const transform = normalizeAnimationBlockTransform(block.transform);
      const offset = [...transform.offset] as [number, number];
      const scale = [...transform.scale] as [number, number];
      const value = Number(target.value);
      if (blockField === 'offsetX') offset[0] = value;
      if (blockField === 'offsetY') offset[1] = value;
      if (blockField === 'scaleX') scale[0] = value;
      if (blockField === 'scaleY') scale[1] = value;
      mutateAnimation((document) => document.setBlockTransform(selection.layerId!, selection.blockIndex!, { offset, scale, rotationDeg: blockField === 'rotationDeg' ? value : transform.rotationDeg, flipX: blockField === 'flipX' && target instanceof HTMLInputElement ? target.checked : transform.flipX, flipY: blockField === 'flipY' && target instanceof HTMLInputElement ? target.checked : transform.flipY }));
    }
  };

  const animationDocument = () => state.draft?.value.animation.animation;
  const handleWheel = (event: WheelEvent): void => {
    if (!(event.target instanceof Element) || !event.target.closest('.layered-preview')) return;
    event.preventDefault();
    const previewZoom = adjustPreviewZoom(state.previewZoom, event.deltaY);
    if (previewZoom !== state.previewZoom) { state = { ...state, previewZoom }; render(); }
  };

  const applyWorkbenchSplit = (workbench: HTMLElement, requestedRatio: number): number => {
    const ratio = Math.max(25, Math.min(75, requestedRatio));
    workbench.style.setProperty('--preview-split', `${ratio}fr`);
    workbench.style.setProperty('--controls-split', `${100 - ratio}fr`);
    workbench.querySelector<HTMLElement>('[data-workbench-splitter]')?.setAttribute('aria-valuenow', String(ratio));
    return ratio;
  };

  const clearWorkbenchSplitState = (): void => {
    container.querySelector<HTMLElement>('.layered-weapon-studio')?.classList.remove('is-splitting');
  };

  const handlePointerDown = (event: PointerEvent): void => {
    if (!(event.target instanceof Element) || event.button !== 0) return;
    const splitHandle = event.target.closest<HTMLElement>('[data-workbench-splitter]');
    if (splitHandle) {
      const workbench = splitHandle.closest<HTMLElement>('.studio-workbench');
      const preview = workbench?.querySelector<HTMLElement>('.layered-preview-card');
      const bottom = workbench?.querySelector<HTMLElement>('.layered-workbench-bottom');
      if (!workbench || !preview || !bottom) return;
      const previewRect = preview.getBoundingClientRect();
      const bottomRect = bottom.getBoundingClientRect();
      event.preventDefault();
      splitDrag = {
        pointerId: event.pointerId,
        startY: splitHandle.getBoundingClientRect().top + splitHandle.getBoundingClientRect().height / 2,
        startRatio: state.previewSplit,
        availableHeight: previewRect.height + bottomRect.height,
        workbench,
        lastRatio: state.previewSplit,
      };
      container.querySelector<HTMLElement>('.layered-weapon-studio')?.classList.add('is-splitting');
      if (event.isTrusted) splitHandle.setPointerCapture(event.pointerId);
      return;
    }
    const resizeHandle = event.target.closest<HTMLElement>('[data-layer-resize-handle]');
    if (resizeHandle) {
      const animation = animationDocument();
      const lane = resizeHandle.closest<HTMLElement>('.layered-timeline-blocks');
      if (!animation || !lane) return;
      const layerId = resizeHandle.dataset.layerId!;
      const blockIndex = Number(resizeHandle.dataset.blockIndex);
      const block = animation.layers.find((layer) => layer.layerId === layerId)?.blocks[blockIndex];
      if (!block) return;
      event.preventDefault();
      event.stopPropagation();
      resize = { pointerId: event.pointerId, layerId, blockIndex, originalThrough: block.through, startX: event.clientX, frameWidth: lane.getBoundingClientRect().width / layeredTimelineFrameCount(animation) };
      resizeHandle.setPointerCapture(event.pointerId);
      return;
    }
    const moveHandle = event.target.closest<HTMLElement>('[data-select-block]');
    const lane = moveHandle?.closest<HTMLElement>('.layered-timeline-blocks');
    const blockElement = moveHandle?.closest<HTMLElement>('[data-layer-block]');
    const animation = animationDocument();
    if (!moveHandle || !lane || !blockElement || !animation) return;
    const layerId = moveHandle.dataset.layerId!;
    const blockIndex = Number(moveHandle.dataset.blockIndex);
    const block = animation.layers.find((layer) => layer.layerId === layerId)?.blocks[blockIndex];
    if (!block) return;
    move = { pointerId: event.pointerId, layerId, blockIndex, originalFrom: block.from, startX: event.clientX, frameWidth: lane.getBoundingClientRect().width / layeredTimelineFrameCount(animation), blockElement, previewDelta: 0 };
    blockElement.classList.add('is-moving');
    moveHandle.setPointerCapture(event.pointerId);
  };
  const handlePointerMove = (event: PointerEvent): void => {
    if (splitDrag && splitDrag.pointerId === event.pointerId) {
      event.preventDefault();
      splitDrag.lastRatio = applyWorkbenchSplit(splitDrag.workbench, splitDrag.startRatio + ((event.clientY - splitDrag.startY) / splitDrag.availableHeight) * 100);
      return;
    }
    if (!move || move.pointerId !== event.pointerId) return;
    event.preventDefault();
    const animation = animationDocument();
    const layer = animation?.layers.find((candidate) => candidate.layerId === move?.layerId);
    const block = layer?.blocks[move.blockIndex];
    if (!animation || !layer || !block) return;
    const hold = block.through - block.from + 1;
    const requestedDelta = Math.round((event.clientX - move.startX) / move.frameWidth);
    const delta = Math.max(-move.originalFrom, Math.min(layeredTimelineFrameCount(animation) - hold - move.originalFrom, requestedDelta));
    if (delta === move.previewDelta) return;
    move.previewDelta = delta;
    const from = move.originalFrom + delta;
    const through = from + hold - 1;
    const blocked = layer.blocks.some((candidate, index) => index !== move!.blockIndex && candidate.from <= through && from <= candidate.through);
    move.blockElement.style.transform = `translateX(${delta * move.frameWidth}px)`;
    move.blockElement.classList.toggle('is-blocked', blocked);
    const startLabel = move.blockElement.querySelector<HTMLElement>('.timeline-frame-number');
    if (startLabel) startLabel.textContent = String(from).padStart(2, '0');
  };
  const clearMovePreview = (drag: MoveDrag): void => {
    drag.blockElement.classList.remove('is-moving', 'is-blocked');
    drag.blockElement.style.removeProperty('transform');
  };
  const handlePointerUp = (event: PointerEvent): void => {
    if (splitDrag && splitDrag.pointerId === event.pointerId) {
      event.preventDefault();
      const current = splitDrag;
      splitDrag = undefined;
      state = { ...state, previewSplit: current.lastRatio };
      clearWorkbenchSplitState();
      return;
    }
    if (resize?.pointerId === event.pointerId) {
      event.preventDefault();
      const current = resize;
      resize = undefined;
      const delta = Math.round((event.clientX - current.startX) / current.frameWidth);
      if (delta !== 0) mutateAnimation((document) => document.resizeBlock(current.layerId, current.blockIndex, current.originalThrough + delta));
      return;
    }
    if (!move || move.pointerId !== event.pointerId) return;
    const current = move;
    move = undefined;
    clearMovePreview(current);
    if (current.previewDelta === 0) return;
    event.preventDefault();
    const blockKey = `${current.layerId}:${current.blockIndex}`;
    suppressedBlockClick = blockKey;
    window.setTimeout(() => { if (suppressedBlockClick === blockKey) suppressedBlockClick = undefined; }, 0);
    mutateAnimation((document) => document.moveBlock(current.layerId, current.blockIndex, current.originalFrom + current.previewDelta));
  };
  const handlePointerCancel = (event: PointerEvent): void => {
    if (splitDrag?.pointerId === event.pointerId) {
      const current = splitDrag;
      splitDrag = undefined;
      applyWorkbenchSplit(current.workbench, current.startRatio);
      state = { ...state, previewSplit: current.startRatio };
      clearWorkbenchSplitState();
      return;
    }
    if (resize?.pointerId === event.pointerId) resize = undefined;
    if (!move || move.pointerId !== event.pointerId) return;
    const current = move;
    move = undefined;
    clearMovePreview(current);
  };
  const handleKeyDown = (event: KeyboardEvent): void => {
    if (handleStudioHistoryShortcut(event, () => applyHistory(false), () => applyHistory(true))) return;
    const splitHandle = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-workbench-splitter]') : undefined;
    if (splitHandle && ['ArrowUp', 'ArrowDown', 'Home', 'End'].includes(event.key)) {
      const workbench = splitHandle.closest<HTMLElement>('.studio-workbench');
      if (!workbench) return;
      event.preventDefault();
      const nextRatio = event.key === 'Home' ? 25 : event.key === 'End' ? 75 : state.previewSplit + (event.key === 'ArrowUp' ? -5 : 5);
      const previewSplit = applyWorkbenchSplit(workbench, nextRatio);
      state = { ...state, previewSplit };
      return;
    }
    const blockButton = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-select-block]') : undefined;
    if (!blockButton || !['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
    const animation = animationDocument();
    const layerId = blockButton.dataset.layerId!;
    const blockIndex = Number(blockButton.dataset.blockIndex);
    const block = animation?.layers.find((layer) => layer.layerId === layerId)?.blocks[blockIndex];
    if (!animation || !block) return;
    event.preventDefault();
    const hold = block.through - block.from + 1;
    const requestedFrom = event.key === 'Home' ? 0 : event.key === 'End' ? layeredTimelineFrameCount(animation) - hold : block.from + (event.key === 'ArrowLeft' ? -1 : 1);
    mutateAnimation((document) => document.moveBlock(layerId, blockIndex, requestedFrom));
  };

  const handleToggle = (event: Event): void => {
    const folder = event.target;
    if (!(folder instanceof HTMLDetailsElement) || !folder.dataset.libraryFolder) return;
    const expandedFolders = new Set(state.expandedFolders);
    if (folder.open) expandedFolders.add(folder.dataset.libraryFolder);
    else expandedFolders.delete(folder.dataset.libraryFolder);
    state = { ...state, expandedFolders };
    options.onExpandedFoldersChange?.(expandedFolders);
  };

  container.addEventListener('click', handleClick);
  container.addEventListener('input', handleInput);
  container.addEventListener('change', handleInput);
  container.addEventListener('wheel', handleWheel, { passive: false });
  container.addEventListener('pointerdown', handlePointerDown);
  container.addEventListener('pointermove', handlePointerMove);
  container.addEventListener('pointerup', handlePointerUp);
  container.addEventListener('pointercancel', handlePointerCancel);
  container.addEventListener('keydown', handleKeyDown);
  container.addEventListener('toggle', handleToggle, true);
  render();
  const requestedAnimationId = options.initialAnimationId ?? new URLSearchParams(window.location.search).get('animation');
  void Promise.all([loadJson<AnimationPackageCatalog>('/__animation-library/catalog'), loadJson<CharacterStudioAssetCatalog>('/__character-studio/assets'), loadJson<WeaponCatalogResponse>('/__character-studio/weapons')]).then(([catalog, assets, weaponCatalog]) => {
    const selected = catalog.packages.find((entry) => entry.animationId === requestedAnimationId) ?? catalog.packages[0];
    state = { ...state, catalog, assets, weapons: weaponCatalog.weapons, loading: false };
    if (selected) openEntry(selected); else render();
  }).catch((error: unknown) => { state = { ...state, loading: false, notice: error instanceof Error ? error.message : String(error) }; render(); });
  return () => {
    stopPlayback();
    container.removeEventListener('click', handleClick);
    container.removeEventListener('input', handleInput);
    container.removeEventListener('change', handleInput);
    container.removeEventListener('wheel', handleWheel);
    container.removeEventListener('pointerdown', handlePointerDown);
    container.removeEventListener('pointermove', handlePointerMove);
    container.removeEventListener('pointerup', handlePointerUp);
    container.removeEventListener('pointercancel', handlePointerCancel);
    container.removeEventListener('keydown', handleKeyDown);
    container.removeEventListener('toggle', handleToggle, true);
    container.classList.remove('is-character-studio-host');
    container.replaceChildren();
  };
}
