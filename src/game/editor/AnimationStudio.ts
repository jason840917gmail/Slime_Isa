import './character-studio.css';
import { characterPackages } from 'virtual-character-content';

import type { CharacterStudioAssetCatalog, CharacterStudioAssetEntry } from '../content/characters/characterAssetCatalog';
import { CharacterDocumentState, type CharacterDocumentSnapshot } from './CharacterDocumentState';
import { collectCharacterSourceSheetIssues } from './CharacterSourceSheetCompatibility';
import type { CharacterPackage, VisualSetDocument, VisualTransformDocument } from '../content/characters/types';
import type { AnimationPackageCatalog, AnimationPackageCatalogEntry, AnimationPackageDocument, AnimationPackageReference } from '../content/animations/types';
import type { AuthoredWeaponDefinition, WeaponAttackDirection } from '../content/weapons/types';
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
import { renderStudioLibraryTree } from './StudioLibraryTree';
import { buildAnimationStudioCatalog, type AnimationStudioCatalog } from './AnimationStudioCatalog';
import { WeaponOwnedAnimationDocumentState, type WeaponOwnedAnimationSlot } from './WeaponOwnedAnimationDocumentState';
import { parseAnimationStudioRoute, writeAnimationStudioRoute, type AnimationStudioSelection } from './AnimationStudioRoute';

interface WeaponCatalogResponse { readonly weapons: readonly (AuthoredWeaponDefinition & { readonly revision: string })[] }

export interface AnimationStudioOptions {
  readonly initialAnimationId?: string;
  readonly onSelectWeapon?: (weaponId: string) => void;
  readonly expandedFolders?: ReadonlySet<string>;
  readonly onExpandedFoldersChange?: (expandedFolders: ReadonlySet<string>) => void;
}

interface AnimationStudioState {
  readonly catalog?: AnimationPackageCatalog;
  readonly assets?: CharacterStudioAssetCatalog;
  readonly weapons: readonly (AuthoredWeaponDefinition & { readonly revision: string })[];
  readonly animationCatalog?: AnimationStudioCatalog;
  readonly characters: readonly CharacterPackage[];
  readonly characterState?: CharacterDocumentState;
  readonly selectedCharacterId?: string;
  readonly weaponState?: WeaponOwnedAnimationDocumentState;
  readonly selectedWeaponOwnedKey?: string;
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

function sharedAnimationTimingLocks(
  animationId: string,
  weapons: readonly (AuthoredWeaponDefinition & { readonly revision: string })[],
): readonly string[] {
  return weapons.flatMap((weapon) => {
    if (weapon.version !== 2) return [];
    return (['right', 'left', 'up', 'down'] as const).flatMap((direction) => {
      const attack = weapon.directionalAttacks[direction];
      const track = attack?.attackTrack;
      const hasMarkers = Boolean(track && ((track.events?.length ?? 0) > 0 || track.hitboxSpans.length > 0));
      return attack?.animationId === animationId && hasMarkers ? [`${weapon.displayName} · ${direction.toUpperCase()}`] : [];
    });
  });
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

function frameSprite(asset: CharacterStudioAssetEntry | undefined, sourceFrame: number, className: string, extraStyle = ''): string {
  const info = assetInfo(asset);
  if (!info.url) return '<span class="layered-frame-missing">?</span>';
  const column = sourceFrame % info.columns;
  const row = Math.floor(sourceFrame / info.columns);
  const frameScale = className.includes('studio-frame-image') ? Math.min(52 / info.width, 36 / info.height) : 1;
  return `<span class="${className}" style="--sheet-url:url('${escapeHtml(info.url)}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:${column * info.width}px;--frame-y:${row * info.height}px;--frame-scale:${frameScale};${extraStyle}"></span>`;
}

function resolveCharacterVisualTransform(visualSet: VisualSetDocument, sourceFrame: number, clipId?: string): {
  readonly origin: readonly [number, number];
  readonly scale: readonly [number, number];
  readonly sourceOffset: readonly [number, number];
} {
  const override = visualSet.frameVisuals?.[String(sourceFrame)];
  const clip = clipId ? visualSet.clips[clipId] : undefined;
  return {
    origin: override?.origin ?? visualSet.defaults.origin,
    scale: override?.scale ?? visualSet.defaults.scale,
    sourceOffset: override?.sourceOffset ?? clip?.sourceOffset ?? visualSet.defaults.sourceOffset,
  };
}

function visualField(label: string, path: string, value: number, unit: string, step = '0.01'): string {
  return `<label class="studio-field"><span>${label}<small>${unit}</small></span><input type="number" step="${step}" inputmode="decimal" value="${escapeHtml(String(value))}" data-character-visual="${path}" /></label>`;
}

function renderLibrary(state: AnimationStudioState, returnEditor: string): string {
  const selectedAnimationId = state.draft?.value.animationId;
  return renderStudioLibraryTree({
    weapons: state.weapons,
    animations: state.catalog?.packages ?? [],
    search: state.search,
    expandedFolders: state.expandedFolders,
    selectedAnimationId,
    characters: state.characters,
    selectedCharacterId: state.selectedCharacterId,
    selectedWeaponOwnedKey: state.selectedWeaponOwnedKey,
    animationCatalog: state.animationCatalog,
    footerHtml: `<button type="button" class="studio-button studio-button--outline" data-animation-action="new-folder">NEW FOLDER</button><button type="button" class="studio-button studio-button--outline" data-animation-action="new-package">NEW ANIMATION</button><button type="button" class="studio-button studio-button--outline" data-animation-action="duplicate" ${state.draft ? '' : 'disabled'}>DUPLICATE</button><button type="button" class="studio-button studio-button--outline" data-animation-action="move" ${state.draft ? '' : 'disabled'}>MOVE</button><button type="button" class="studio-button studio-button--danger" data-animation-action="delete" ${state.draft ? '' : 'disabled'}>DELETE</button><a class="studio-button studio-button--outline studio-button--navigation" href="?studio=scenes&amp;editor=${encodeURIComponent(returnEditor)}">↗ SCENE STUDIO</a>`,
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

function numberField(label: string, field: string, value: number, step = '1', disabled = false): string {
  return `<label class="studio-field${disabled ? ' is-disabled' : ''}"><span>${label}</span><input type="number" step="${step}" value="${value}" data-animation-edit="${field}"${disabled ? ' disabled aria-disabled="true"' : ''} /></label>`;
}

function renderInspector(state: AnimationStudioState): string {
  const draft = state.draft;
  if (!draft) return '';
  const value = draft.value;
  const { animation, selection } = value.animation;
  const layer = animation.layers.find((candidate) => candidate.layerId === selection.layerId);
  const block = layer && selection.blockIndex !== undefined ? layer.blocks[selection.blockIndex] : undefined;
  const layerTransform = layer ? normalizeAnimationLayerTransform(layer.transform) : undefined;
  const timingLocks = state.animationCatalog?.timingLocks.find((lock) => lock.animationId === value.animationId)?.consumers
    ?? sharedAnimationTimingLocks(value.animationId, state.weapons);
  const timingLocked = timingLocks.length > 0;
  const timingLockNotice = timingLocked
    ? `<p class="studio-help studio-help--warning">Timing is locked because ${timingLocks.map((entry) => `<b>${escapeHtml(entry)}</b>`).join(', ')} uses attack markers. Visual edits remain available.</p>`
    : '';
  const assetOptions = spritesheets(state).map((asset) => `<option value="${escapeHtml(asset.assetId)}" ${asset.assetId === layer?.assetId ? 'selected' : ''}>${escapeHtml(asset.assetId)}</option>`).join('');
  const blockInspector = block ? `${renderLayeredAnimationBlockInspector({ block, framesPerSecond: animation.framesPerSecond, timelineFrames: layeredTimelineFrameCount(animation) })}<button type="button" class="studio-button studio-button--danger" data-animation-action="delete-block">DELETE TILE</button>` : '<p class="studio-empty-note">Select a tile to edit its transform.</p>';
  return `<aside class="studio-inspector layered-weapon-inspector"><div class="studio-inspector-heading"><span class="studio-kicker">Inspector</span><h2>Animation controls</h2><p>Stable ID: <code>${escapeHtml(value.animationId)}</code></p></div><div class="studio-inspector-scroll"><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Package</span><strong>Metadata</strong></div><label class="studio-field"><span>Display name</span><input type="text" value="${escapeHtml(value.displayName)}" data-animation-metadata="displayName" /></label><label class="studio-field"><span>Description</span><textarea data-animation-metadata="description">${escapeHtml(value.description)}</textarea></label><div class="studio-field-grid">${numberField('FPS', 'fps', animation.framesPerSecond, '1', timingLocked)}${numberField('Duration', 'duration', animation.durationSeconds, '0.05', timingLocked)}<label class="studio-field studio-field--toggle"><span>Loop</span><input type="checkbox" ${animation.loop ? 'checked ' : ''}data-animation-edit="loop" /></label><label class="studio-field"><span>Loop mode</span><select data-animation-edit="loopMode"><option value="wrap" ${(animation.loopMode ?? 'wrap') === 'wrap' ? 'selected' : ''}>Wrap</option><option value="ping-pong" ${animation.loopMode === 'ping-pong' ? 'selected' : ''}>Ping-pong</option></select></label></div>${timingLockNotice}</section>${layer && layerTransform ? `<section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Visual layer</span><strong>${escapeHtml(layer.displayName)}</strong></div><label class="studio-field"><span>Layer name</span><input type="text" value="${escapeHtml(layer.displayName)}" data-layer-edit="displayName" /></label><label class="studio-field"><span>Source sheet</span><select data-layer-edit="assetId">${assetOptions}</select></label><div class="studio-field-grid">${numberField('Depth', 'layerDepth', layer.depthOffset, '0.1')}${numberField('Offset X', 'layerOffsetX', layerTransform.offset[0], '0.25')}${numberField('Offset Y', 'layerOffsetY', layerTransform.offset[1], '0.25')}${numberField('Scale X', 'layerScaleX', layerTransform.scale[0], '0.05')}${numberField('Scale Y', 'layerScaleY', layerTransform.scale[1], '0.05')}${numberField('Rotation', 'layerRotation', layerTransform.rotationDeg)}</div><div class="layered-layer-actions"><button type="button" class="studio-button studio-button--quiet" data-animation-action="layer-front">↑ FRONT</button><button type="button" class="studio-button studio-button--quiet" data-animation-action="layer-back">↓ BACK</button><button type="button" class="studio-button studio-button--danger" data-animation-action="delete-layer">DELETE LAYER</button></div>${blockInspector}</section>` : '<section class="studio-inspector-section"><p class="studio-empty-note">Add a visual layer to begin.</p></section>'}</div></aside>`;
}

function renderFramePicker(state: AnimationStudioState): string {
  if (!state.pickerOpen || !state.draft) return '';
  const selection = state.draft.value.animation.selection;
  const layer = state.draft.value.animation.animation.layers.find((candidate) => candidate.layerId === selection.layerId);
  const info = assetInfo(state.assets?.assets.find((entry) => entry.assetId === layer?.assetId));
  return `<div class="studio-asset-shelf-backdrop layered-tile-picker-backdrop" data-picker-backdrop><section class="studio-asset-shelf weapon-tile-picker" role="dialog" aria-modal="true" aria-labelledby="shared-tile-picker-title"><header class="studio-asset-shelf-heading"><div><span class="studio-kicker">${escapeHtml(layer?.displayName ?? 'Layer')} source</span><h2 id="shared-tile-picker-title">Add tiles to animation</h2><p>Select one or more source tiles, then add them at the current playhead.</p></div><button type="button" class="studio-icon-button" data-action="close-picker" aria-label="Close">×</button></header><div class="studio-sheet-grid projectile-frame-grid weapon-picker-grid">${Array.from({ length: info.count }, (_, frame) => `<button type="button" class="projectile-frame-option${state.pickerFrames.includes(frame) ? ' is-selected' : ''}" data-picker-frame="${frame}" aria-pressed="${state.pickerFrames.includes(frame)}">${frameSprite(state.assets?.assets.find((entry) => entry.assetId === layer?.assetId), frame, 'projectile-frame-preview')}<span>${String(frame).padStart(2, '0')}</span></button>`).join('')}</div><footer class="weapon-tile-picker-footer"><span>${state.pickerFrames.length} selected · inserted at playhead ${selection.playhead}</span><div><button type="button" class="studio-button studio-button--quiet" data-action="close-picker">CANCEL</button><button type="button" class="studio-button studio-button--accent" data-action="confirm-picker" ${state.pickerFrames.length ? '' : 'disabled'}>ADD TO LAYER</button></div></footer></section></div>`;
}

function stripSharedWeaponCopies(weapon: AuthoredWeaponDefinition): AuthoredWeaponDefinition {
  if (weapon.version !== 2) return weapon;
  const animations = { ...weapon.animations } as Record<string, unknown>;
  if (animations.idleAnimationId) delete animations.idle;
  const directionalAttacks = Object.fromEntries(Object.entries(weapon.directionalAttacks).map(([direction, attack]) => {
    const next = { ...attack } as Record<string, unknown>;
    if (next.animationId) delete next.animation;
    return [direction, next];
  })) as unknown as typeof weapon.directionalAttacks;
  return { ...weapon, animations: animations as typeof weapon.animations, directionalAttacks };
}

function renderCharacterWorkspace(state: AnimationStudioState, returnEditor: string): string {
  const editor = state.characterState;
  if (!editor) return '<section class="studio-empty-state"><span class="studio-loading-orb">✦</span><h2>Select a character animation</h2></section>';
  const snapshot: CharacterDocumentSnapshot = editor.value;
  const clip = snapshot.visualSet.clips[snapshot.selectedClipId];
  const asset = state.assets?.assets.find((entry) => entry.assetId === snapshot.visualSet.assetId);
  const info = assetInfo(asset);
  const sourceIssues = collectCharacterSourceSheetIssues(snapshot.visualSet, asset?.frame?.count ?? 0);
  const selectedFrames = new Set(snapshot.selectedSourceFrames);
  const selectedTransform = resolveCharacterVisualTransform(snapshot.visualSet, snapshot.selectedSourceFrame, snapshot.selectedClipId);
  const frameOverride = snapshot.visualSet.frameVisuals?.[String(snapshot.selectedSourceFrame)] ?? {};
  const clipSourceOffset = clip?.sourceOffset ?? snapshot.visualSet.defaults.sourceOffset;
  const previewScaleX = Number(selectedTransform.scale[0]) * 2.8;
  const previewScaleY = Number(selectedTransform.scale[1]) * 2.8;
  const characterPreview = frameSprite(asset, snapshot.selectedSourceFrame, 'stage-sprite', `--preview-scale-x:${previewScaleX};--preview-scale-y:${previewScaleY};--origin-offset-x:${-Number(selectedTransform.origin[0]) * info.width * previewScaleX}px;--origin-offset-y:${-Number(selectedTransform.origin[1]) * info.height * previewScaleY}px;--offset-x:${Number(selectedTransform.sourceOffset[0]) * previewScaleX}px;--offset-y:${Number(selectedTransform.sourceOffset[1]) * previewScaleY}px`);
  const sourceOptions = spritesheets(state).map((candidate) => `<option value="${escapeHtml(candidate.assetId)}" ${candidate.assetId === snapshot.visualSet.assetId ? 'selected' : ''}>${escapeHtml(candidate.assetId)} · ${candidate.frame?.count ?? 1} frames</option>`).join('');
  const clipTabs = Object.entries(snapshot.visualSet.clips).map(([clipId, entry]) => `<button type="button" class="studio-clip-tab${clipId === snapshot.selectedClipId ? ' is-active' : ''}" data-character-clip="${escapeHtml(clipId)}"><span>${escapeHtml(clipId)}</span><small>${entry.frames.length}K</small></button>`).join('');
  const timeline = clip?.frames.map((sourceFrame, index) => `<button type="button" class="timeline-frame-select${index === snapshot.selectedTimelineIndex ? ' is-active' : ''}" data-character-timeline-index="${index}" aria-label="Select keyframe ${index + 1}">${frameSprite(asset, sourceFrame, 'timeline-tile-preview')}<b>${String(index + 1).padStart(2, '0')}</b><small>SRC ${sourceFrame}</small></button>`).join('') ?? '';
  const allErrors = [...snapshot.errors, ...sourceIssues];
  const errors = allErrors.length > 0 ? `<section class="studio-errors"><div class="studio-section-heading"><span class="studio-kicker">Validation</span><strong>${allErrors.length} issue${allErrors.length === 1 ? '' : 's'}</strong></div>${allErrors.map((issue) => `<p><b>${escapeHtml(issue.path)}</b> ${escapeHtml(issue.message)}</p>`).join('')}</section>` : '';
  const presentation = `<section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Presentation</span><strong>Runtime visual transform</strong></div><p class="studio-help">These values affect the sprite only. Physics/body dimensions remain separate. Frame overrides take precedence over the defaults.</p><div class="studio-subheading">Global defaults</div><div class="studio-field-grid">${visualField('Origin X', 'defaults.origin.0', Number(snapshot.visualSet.defaults.origin[0]), 'normalized')}${visualField('Origin Y', 'defaults.origin.1', Number(snapshot.visualSet.defaults.origin[1]), 'normalized')}${visualField('Scale X', 'defaults.scale.0', Number(snapshot.visualSet.defaults.scale[0]), 'multiplier')}${visualField('Scale Y', 'defaults.scale.1', Number(snapshot.visualSet.defaults.scale[1]), 'multiplier')}${visualField('Offset X', 'defaults.sourceOffset.0', Number(snapshot.visualSet.defaults.sourceOffset[0]), 'source px')}${visualField('Offset Y', 'defaults.sourceOffset.1', Number(snapshot.visualSet.defaults.sourceOffset[1]), 'source px')}</div><div class="studio-subheading">Animation ${escapeHtml(snapshot.selectedClipId)} offset <button type="button" class="studio-link-button" data-animation-action="reset-animation-visual">reset</button></div><div class="studio-field-grid">${visualField('Offset X', 'animation.sourceOffset.0', Number(clipSourceOffset[0]), clip?.sourceOffset ? 'override' : 'uses default')}${visualField('Offset Y', 'animation.sourceOffset.1', Number(clipSourceOffset[1]), clip?.sourceOffset ? 'override' : 'uses default')}</div><div class="studio-subheading">Frame ${snapshot.selectedSourceFrame} override <button type="button" class="studio-link-button" data-animation-action="reset-frame-visual">reset</button></div><div class="studio-field-grid">${visualField('Origin X', 'frame.origin.0', Number(selectedTransform.origin[0]), frameOverride.origin ? 'override' : 'uses default')}${visualField('Origin Y', 'frame.origin.1', Number(selectedTransform.origin[1]), frameOverride.origin ? 'override' : 'uses default')}${visualField('Scale X', 'frame.scale.0', Number(selectedTransform.scale[0]), frameOverride.scale ? 'override' : 'uses default')}${visualField('Scale Y', 'frame.scale.1', Number(selectedTransform.scale[1]), frameOverride.scale ? 'override' : 'uses default')}${visualField('Offset X', 'frame.sourceOffset.0', Number(selectedTransform.sourceOffset[0]), frameOverride.sourceOffset ? 'override' : 'uses animation')}${visualField('Offset Y', 'frame.sourceOffset.1', Number(selectedTransform.sourceOffset[1]), frameOverride.sourceOffset ? 'override' : 'uses animation')}</div></section>`;
  return `<main class="character-studio animation-studio animation-studio-single-sheet${snapshot.dirty ? ' is-dirty' : ''}><header class="studio-topbar"><a class="studio-brand" href="?" aria-label="Back to game"><span class="brand-mark">✦</span><span><small>FIELD CARTOGRAPHER</small><strong>ANIMATION STUDIO</strong></span></a><div class="studio-topbar-actions"><span class="studio-save-state${allErrors.length ? ' is-error' : ''}"><i></i>${escapeHtml(allErrors.length ? `${allErrors.length} validation issue${allErrors.length === 1 ? '' : 's'}` : snapshot.statusMessage)}</span><button type="button" class="studio-button studio-button--quiet" data-animation-action="undo" ${snapshot.dirty ? '' : 'disabled'}>↶</button><button type="button" class="studio-button studio-button--quiet" data-animation-action="redo">↷</button><button type="button" class="studio-button studio-button--save" data-animation-action="save" ${allErrors.length > 0 || !snapshot.dirty ? 'disabled' : ''}>SAVE CHARACTER</button></div></header><div class="studio-layout">${renderLibrary(state, returnEditor)}<section class="studio-workbench"><div class="studio-workbench-heading"><div><span class="studio-kicker">${snapshot.character.kind.toUpperCase()} · SINGLE SHEET</span><h2>${escapeHtml(snapshot.character.displayName)} <span>${escapeHtml(snapshot.selectedClipId)}</span></h2><div class="studio-clip-tabs">${clipTabs}</div></div><div class="studio-workbench-meta"><span>SHEET <b>${escapeHtml(String(snapshot.visualSet.assetId))}</b></span><span>GRID <b>${info.columns} × ${info.rows}</b></span><span>FRAMES <b>${info.count}</b></span></div></div><section class="studio-preview-card"><div class="studio-preview-toolbar"><span class="studio-kicker">SOURCE PREVIEW</span><label class="studio-inline-field">SHEET <select data-character-source-sheet>${sourceOptions}</select></label></div><div class="studio-stage animation-single-preview">${characterPreview}<span class="stage-anchor">+</span><span class="stage-label">WORLD ANCHOR</span><span class="stage-caption"><b>${escapeHtml(snapshot.selectedClipId)}</b><span>KEYFRAME ${snapshot.selectedTimelineIndex + 1} / ${clip?.frames.length ?? 0} · SOURCE ${snapshot.selectedSourceFrame}</span></span></div></section><section class="studio-sheet-panel"><div class="studio-section-bar"><div><span class="studio-kicker">Spritesheet</span><strong>Click a source frame, then insert or append it</strong></div><span class="studio-muted">${info.width} × ${info.height} px cells</span></div><div class="studio-sheet-grid">${Array.from({ length: info.count }, (_, frame) => `<button type="button" class="studio-frame-tile${selectedFrames.has(frame) ? ' is-selected' : ''}${clip?.frames.includes(frame) ? ' is-in-clip' : ''}" data-character-source-frame="${frame}" aria-label="Source frame ${frame}">${frameSprite(asset, frame, 'studio-frame-image')}<small>${frame}</small></button>`).join('')}</div><div class="studio-sheet-actions"><button type="button" class="studio-button studio-button--accent" data-animation-action="append-character-frames">+ APPEND SELECTED</button><button type="button" class="studio-button studio-button--quiet" data-animation-action="insert-character-frames">INSERT BEFORE SELECTION</button><button type="button" class="studio-button studio-button--quiet" data-animation-action="duplicate-frame" ${clip?.frames.length ? '' : 'disabled'}>DUPLICATE KEYFRAME</button></div></section><section class="studio-timeline studio-timeline--single-sheet"><div class="studio-section-bar"><div><span class="studio-kicker">Timeline</span><strong>${clip?.frames.length ?? 0} keyframes · ${clip?.framesPerSecond ?? 0} FPS</strong></div><span class="studio-muted">Select a keyframe to edit</span></div><div class="timeline-frames">${timeline}</div><div class="studio-playback"><button type="button" class="studio-button studio-button--quiet is-danger" data-animation-action="remove-character-frame" ${!clip || clip.frames.length <= 1 ? 'disabled' : ''}>REMOVE KEYFRAME</button><span>Frame holds and event/span tracks stay attached to timeline positions.</span></div></section></section><aside class="studio-inspector"><div class="studio-inspector-heading"><span class="studio-kicker">Animation package</span><h2>${escapeHtml(snapshot.character.displayName)}</h2><p>${escapeHtml(snapshot.character.characterId)} · ${escapeHtml(snapshot.visualSet.visualSetId)}</p></div><div class="studio-inspector-scroll"><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Source</span><strong>Registered spritesheet</strong></div><label class="studio-field"><span>Asset ID</span><select data-character-source-sheet>${sourceOptions}</select></label><p class="studio-help">Changing the sheet preserves frame numbers, timing, events, spans, and alignment. Invalid references block save.</p></section>${presentation}${errors}</div></aside></div></main>`;
}

function renderWeaponOwnedWorkspace(state: AnimationStudioState, returnEditor: string): string {
  const editor = state.weaponState;
  if (!editor) return '<section class="studio-empty-state"><span class="studio-loading-orb">✦</span><h2>Select a weapon animation</h2></section>';
  const snapshot = editor.value;
  const animation = snapshot.animation.animation;
  const selection = snapshot.animation.selection;
  const selectedLayer = animation.layers.find((layer) => layer.layerId === selection.layerId) ?? animation.layers[0];
  const selectedBlock = selectedLayer && selection.blockIndex !== undefined ? selectedLayer.blocks[selection.blockIndex] : undefined;
  const activeBlock = animation.layers.flatMap((layer) => layer.blocks.map((block) => ({ layer, block }))).find(({ block }) => block.from <= selection.playhead && selection.playhead <= block.through);
  const previewAsset = state.assets?.assets.find((asset) => asset.assetId === activeBlock?.layer.assetId);
  const layerRows = animation.layers.map((layer) => `<button type="button" class="studio-tree-item studio-tree-file${layer.layerId === selectedLayer?.layerId ? ' is-active' : ''}" data-owned-select-layer="${escapeHtml(layer.layerId)}"><span class="studio-tree-file-icon studio-tree-file-icon--animation">◈</span><span class="studio-tree-file-copy"><strong>${escapeHtml(layer.displayName)}</strong><small>${escapeHtml(layer.assetId)}</small></span><em>${layer.blocks.length} TILES</em></button>`).join('');
  const timeline = animation.layers.flatMap((layer) => layer.blocks.map((block, index) => `<button type="button" class="timeline-frame-select${layer.layerId === selectedLayer?.layerId && index === selection.blockIndex ? ' is-active' : ''}" data-owned-select-block="${escapeHtml(layer.layerId)}:${index}" style="grid-column:${block.from + 1} / span ${block.through - block.from + 1}">${frameSprite(state.assets?.assets.find((asset) => asset.assetId === layer.assetId), block.sourceFrame, 'timeline-tile-preview')}<b>${String(block.from).padStart(2, '0')}</b><small>SRC ${block.sourceFrame}</small></button>`)).join('');
  const assetOptions = spritesheets(state).map((asset) => `<option value="${escapeHtml(asset.assetId)}" ${asset.assetId === selectedLayer?.assetId ? 'selected' : ''}>${escapeHtml(asset.assetId)}</option>`).join('');
  const errors = snapshot.errors.length > 0 ? `<section class="studio-errors"><div class="studio-section-heading"><span class="studio-kicker">Validation</span><strong>${snapshot.errors.length} issue${snapshot.errors.length === 1 ? '' : 's'}</strong></div>${snapshot.errors.map((issue) => `<p>${escapeHtml(issue)}</p>`).join('')}</section>` : '';
  const slotLabel = snapshot.slot.slot === 'idle' ? 'IDLE' : `ATTACK · ${snapshot.slot.direction.toUpperCase()}`;
  return `<main class="character-studio animation-studio animation-studio-owned${snapshot.dirty ? ' is-dirty' : ''}"><header class="studio-topbar"><a class="studio-brand" href="?" aria-label="Back to game"><span class="brand-mark">✦</span><span><small>FIELD CARTOGRAPHER</small><strong>ANIMATION STUDIO</strong></span></a><div class="studio-topbar-actions"><span class="studio-save-state${snapshot.errors.length ? ' is-error' : ''}"><i></i>${escapeHtml(snapshot.errors[0] ?? (snapshot.dirty ? 'Unsaved weapon animation' : 'Weapon animation selected'))}</span><button type="button" class="studio-button studio-button--quiet" data-animation-action="owned-undo" ${snapshot.canUndo ? '' : 'disabled'}>↶</button><button type="button" class="studio-button studio-button--quiet" data-animation-action="owned-redo" ${snapshot.canRedo ? '' : 'disabled'}>↷</button><button type="button" class="studio-button studio-button--save" data-animation-action="owned-save" ${snapshot.errors.length || !snapshot.dirty || state.saving ? 'disabled' : ''}>${state.saving ? 'SAVING…' : 'SAVE WEAPON ANIMATION'}</button></div></header><div class="studio-layout">${renderLibrary(state, returnEditor)}<section class="studio-workbench"><div class="studio-workbench-heading"><div><span class="studio-kicker">WEAPON · OWNED LAYERED ANIMATION</span><h2>${escapeHtml(snapshot.weapon.displayName)} <span>${slotLabel}</span></h2></div><div class="studio-workbench-meta"><span>WEAPON <b>${escapeHtml(snapshot.weapon.weaponId)}</b></span><span>FPS <b>${animation.framesPerSecond}</b></span><span>FRAMES <b>${layeredTimelineFrameCount(animation)}</b></span></div></div><section class="studio-preview-card"><div class="studio-preview-toolbar"><span class="studio-kicker">PREVIEW</span><span class="studio-muted">Playhead ${selection.playhead}</span></div><div class="studio-stage animation-single-preview">${activeBlock && previewAsset ? frameSprite(previewAsset, activeBlock.block.sourceFrame, 'stage-sprite') : '<p class="studio-empty-note">No tile at this time.</p>'}<span class="stage-anchor">+</span><span class="stage-label">WORLD ANCHOR</span><span class="stage-caption"><b>${slotLabel}</b><span>${selection.playhead + 1} / ${layeredTimelineFrameCount(animation)}</span></span></div></section><section class="studio-sheet-panel"><div class="studio-section-bar"><div><span class="studio-kicker">Layers</span><strong>One shared layered workbench, weapon-owned document</strong></div><button type="button" class="studio-button studio-button--quiet" data-animation-action="owned-add-layer">+ ADD LAYER</button></div><div class="studio-owned-layers">${layerRows}</div></section><section class="studio-timeline studio-timeline--single-sheet"><div class="studio-section-bar"><div><span class="studio-kicker">Timeline</span><strong>${animation.framesPerSecond} FPS · ${animation.durationSeconds.toFixed(2)}s</strong></div><span class="studio-muted">Click a tile to select · click the playhead ruler to scrub</span></div><div class="timeline-frames">${timeline}</div><div class="studio-playback"><button type="button" class="studio-button studio-button--quiet" data-animation-action="owned-duplicate-block" ${selectedBlock ? '' : 'disabled'}>DUPLICATE TILE</button><button type="button" class="studio-button studio-button--quiet is-danger" data-animation-action="owned-delete-block" ${selectedBlock ? '' : 'disabled'}>DELETE TILE</button></div></section></section><aside class="studio-inspector"><div class="studio-inspector-heading"><span class="studio-kicker">Owned animation</span><h2>${escapeHtml(snapshot.weapon.displayName)}</h2><p>${escapeHtml(snapshot.weapon.weaponId)} · ${slotLabel}</p></div><div class="studio-inspector-scroll"><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Timing</span><strong>Animation clock</strong></div><label class="studio-field"><span>FPS</span><input type="number" min="1" max="240" step="1" value="${animation.framesPerSecond}" data-owned-edit="fps" /></label><label class="studio-field"><span>Duration (seconds)</span><input type="number" min="0.01" step="0.01" value="${animation.durationSeconds}" data-owned-edit="duration" /></label><label class="studio-field studio-field--toggle"><span>Loop</span><input type="checkbox" ${animation.loop ? 'checked ' : ''}data-owned-edit="loop" /></label><label class="studio-field"><span>Loop mode</span><select data-owned-edit="loopMode"><option value="wrap" ${animation.loopMode === 'wrap' ? 'selected' : ''}>Wrap</option><option value="ping-pong" ${animation.loopMode === 'ping-pong' ? 'selected' : ''}>Ping-pong</option></select></label></section>${selectedLayer ? `<section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Visual layer</span><strong>${escapeHtml(selectedLayer.displayName)}</strong></div><label class="studio-field"><span>Source sheet</span><select data-owned-edit="layerAsset">${assetOptions}</select></label><label class="studio-field"><span>Layer name</span><input type="text" value="${escapeHtml(selectedLayer.displayName)}" data-owned-edit="layerName" /></label></section>` : ''}${errors}</div></aside></div></main>`;
}

function renderStudio(container: HTMLDivElement, state: AnimationStudioState, returnEditor: string): void {
  if (state.weaponState) {
    container.innerHTML = renderWeaponOwnedWorkspace(state, returnEditor);
    ensureStudioModeTabs(container, returnEditor, 'animations');
    return;
  }
  if (state.characterState) {
    container.innerHTML = renderCharacterWorkspace(state, returnEditor);
    ensureStudioModeTabs(container, returnEditor, 'animations');
    return;
  }
  const draft = state.draft;
  const issues = draft?.validate() ?? [];
  container.innerHTML = `<main class="character-studio weapon-studio layered-weapon-studio animation-studio${draft?.value.dirty ? ' is-dirty' : ''}"><header class="studio-topbar"><a class="studio-brand" href="?" aria-label="Back to game"><span class="brand-mark">✦</span><span><small>FIELD CARTOGRAPHER</small><strong>ANIMATION STUDIO</strong></span></a><div class="studio-topbar-actions"><span class="studio-save-state${state.notice || issues.length ? ' is-error' : ''}"><i></i>${escapeHtml(state.notice ?? issues[0] ?? (draft?.value.dirty ? 'Unsaved shared animation' : 'Shared animation selected'))}</span>${draft ? `<button type="button" class="studio-button studio-button--save" data-animation-action="save" ${state.saving || !draft.value.dirty || issues.length ? 'disabled' : ''}>${state.saving ? 'SAVING…' : 'SAVE ANIMATION'}</button>` : ''}</div></header><div class="studio-layout">${renderLibrary(state, returnEditor)}${state.loading ? '<section class="studio-empty-state"><span class="studio-loading-orb">✦</span><h2>Loading shared animations</h2></section>' : draft ? `<section class="studio-workbench" style="--preview-split:${state.previewSplit}fr;--controls-split:${100 - state.previewSplit}fr"><div class="studio-workbench-heading"><div><span class="studio-kicker">Shared animation package</span><h2>${escapeHtml(draft.value.displayName)}</h2></div><div class="studio-workbench-meta"><span>ID <b>${escapeHtml(draft.value.animationId)}</b></span><span>PATH <b>${escapeHtml(state.selectedPath)}</b></span></div></div>${renderPreview(state)}<button type="button" class="layered-workbench-splitter" data-workbench-splitter aria-label="Resize preview and timeline" aria-valuemin="25" aria-valuemax="75" aria-valuenow="${state.previewSplit}" title="Drag to resize preview and timeline"><span></span></button><div class="layered-workbench-bottom layered-workbench-bottom--timeline">${renderTimeline(state)}</div></section>${renderInspector(state)}` : '<section class="studio-empty-state"><span class="studio-loading-orb">✦</span><h2>Select or create an animation</h2></section>'}</div>${renderFramePicker(state)}</main>`;
  ensureStudioModeTabs(container, returnEditor, 'animations');
}

function newPackageDocument(animationId: string, displayName: string, description: string, assetId: string, loop: boolean): AnimationPackageDocument {
  return { $schema: './animation-package.schema.json', version: 1, animationId, displayName, description, animation: { version: 2, durationSeconds: 0.5, framesPerSecond: 8, loop, loopMode: 'wrap', layers: [{ layerId: 'base', displayName: 'Base', assetId, depthOffset: 0, blocks: [{ from: 0, through: 3, sourceFrame: 0 }] }] } };
}

export function mountAnimationStudio(container: HTMLDivElement, options: AnimationStudioOptions = {}): () => void {
  container.classList.add('is-character-studio-host');
  const returnEditor = new URLSearchParams(window.location.search).get('editor') ?? 'level-1';
  let state: AnimationStudioState = { weapons: [], characters: characterPackages as readonly CharacterPackage[], search: '', expandedFolders: new Set(options.expandedFolders ?? ['weapons', 'animations']), loading: true, saving: false, pickerOpen: false, pickerFrames: [], playing: false, previewZoom: 1, previewSplit: 55 };
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
  const updateRoute = (selection: AnimationStudioSelection | undefined): void => {
    const next = writeAnimationStudioRoute(new URLSearchParams(window.location.search), selection);
    window.history.replaceState(null, '', `?${next.toString()}`);
  };
  const openEntry = (entry: AnimationPackageCatalogEntry): void => {
    stopPlayback();
    const dirty = state.draft?.value.dirty || state.characterState?.value.dirty || state.weaponState?.value.dirty;
    if (dirty && !window.confirm('Discard unsaved animation changes?')) return;
    updateRoute({ kind: 'shared', animationId: entry.animationId });
    state = { ...state, selectedPath: entry.packagePath, selectedCharacterId: undefined, selectedWeaponOwnedKey: undefined, characterState: undefined, weaponState: undefined, draft: new SharedAnimationDocumentState(entry), notice: undefined, pickerOpen: false, pickerFrames: [], previewZoom: 1 };
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
    state = { ...state, catalog, animationCatalog: buildAnimationStudioCatalog(state.characters, catalog, state.weapons), loading: false, saving: false, selectedPath: selected?.packagePath, draft: selected ? new SharedAnimationDocumentState(selected) : undefined };
    render();
  };
  const mutateAnimation = (operation: Parameters<SharedAnimationDocumentState['mutateAnimation']>[0], failure = 'That animation edit could not be applied.'): void => {
    if (!state.draft?.mutateAnimation(operation)) state = { ...state, notice: failure };
    else state = { ...state, notice: undefined };
    render();
  };
  const applyHistory = (redo: boolean): boolean => {
    if (state.characterState) {
      const changed = redo ? state.characterState.redo() : state.characterState.undo();
      if (!changed) return false;
      render();
      return true;
    }
    if (state.weaponState) {
      const changed = redo ? state.weaponState.redo() : state.weaponState.undo();
      if (!changed) return false;
      render();
      return true;
    }
    const draft = state.draft;
    if (!draft) return false;
    const changed = redo ? draft.redo() : draft.undo();
    if (!changed) return false;
    stopPlayback();
    state = { ...state, playing: false, notice: undefined };
    render();
    return true;
  };
  const saveCharacter = async (): Promise<void> => {
    const editor = state.characterState;
    const snapshot = editor?.value;
    const asset = snapshot && state.assets?.assets.find((entry) => entry.assetId === snapshot.visualSet.assetId);
    const sourceIssues = snapshot && collectCharacterSourceSheetIssues(snapshot.visualSet, asset?.frame?.count ?? 0);
    if (!editor || !snapshot || snapshot.errors.length > 0 || (sourceIssues?.length ?? 0) > 0 || !snapshot.dirty) return;
    editor.markSaving();
    state = { ...state, saving: true };
    render();
    try {
      const response = await fetch('/__character-studio/package/update', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ characterId: snapshot.character.characterId, expectedRevision: snapshot.revision, character: snapshot.character, visualSet: snapshot.visualSet }),
      });
      const payload = await response.json() as { ok: boolean; data?: { character: CharacterDocumentSnapshot['character']; visualSet: CharacterDocumentSnapshot['visualSet']; revision: string }; error?: { message?: string } };
      if (!response.ok || !payload.ok || !payload.data) {
        editor.markSaveFailure(payload.error?.message ?? 'Character save failed', response.status === 409);
        state = { ...state, saving: false };
        render();
        return;
      }
      editor.markSaved({ character: payload.data.character, visualSet: payload.data.visualSet }, payload.data.revision);
      state = { ...state, saving: false, notice: 'Character animation saved.' };
      render();
    } catch (error) {
      editor.markSaveFailure(error instanceof Error ? error.message : String(error));
      state = { ...state, saving: false };
      render();
    }
  };
  const openCharacter = (characterId: string, clipId?: string): void => {
    stopPlayback();
    const dirty = state.draft?.value.dirty || state.characterState?.value.dirty || state.weaponState?.value.dirty;
    if (dirty && !window.confirm('Discard unsaved animation changes?')) return;
    updateRoute({ kind: 'character', characterId, ...(clipId ? { clipId } : {}) });
    state = { ...state, loading: true, notice: undefined };
    render();
    void loadJson<{ character: CharacterDocumentSnapshot['character']; visualSet: CharacterDocumentSnapshot['visualSet']; revision: string }>(`/__character-studio/package/${encodeURIComponent(characterId)}`)
      .then((data) => {
        const editor = new CharacterDocumentState({ character: data.character, visualSet: data.visualSet }, data.revision);
        if (clipId) editor.selectClip(clipId);
        state = { ...state, characterState: editor, selectedCharacterId: characterId, selectedWeaponOwnedKey: undefined, selectedPath: undefined, weaponState: undefined, draft: undefined, loading: false, saving: false, notice: undefined, pickerOpen: false, pickerFrames: [] };
        render();
      })
      .catch((error: unknown) => { state = { ...state, loading: false, notice: error instanceof Error ? error.message : String(error) }; render(); });
  };
  const saveWeaponOwned = async (): Promise<void> => {
    const editor = state.weaponState;
    if (!editor || !editor.value.dirty || editor.value.errors.length > 0) return;
    const snapshot = editor.value;
    state = { ...state, saving: true, notice: undefined };
    render();
    try {
      const response = await fetch('/__character-studio/weapon/save-package', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ weapon: stripSharedWeaponCopies(snapshot.weapon), weaponOperation: 'update', expectedWeaponRevision: snapshot.revision }),
      });
      const payload = await response.json() as { ok?: boolean; data?: { weaponRevision?: string }; error?: { message?: string; issues?: readonly { message?: string }[] } };
      if (!response.ok || !payload.ok || !payload.data?.weaponRevision) throw new Error(payload.error?.issues?.[0]?.message ?? payload.error?.message ?? 'Weapon animation save failed');
      editor.markSaved(snapshot.weapon, payload.data.weaponRevision);
      state = { ...state, saving: false, notice: 'Weapon animation saved.' };
      render();
    } catch (error) {
      state = { ...state, saving: false, notice: error instanceof Error ? error.message : String(error) };
      render();
    }
  };
  const openWeaponOwned = (weaponId: string, slot: 'idle' | 'attack', direction?: WeaponAttackDirection): void => {
    const dirty = state.draft?.value.dirty || state.characterState?.value.dirty || state.weaponState?.value.dirty;
    if (dirty && !window.confirm('Discard unsaved animation changes?')) return;
    updateRoute(slot === 'idle' ? { kind: 'weapon-idle', weaponId } : { kind: 'weapon-attack', weaponId, direction: direction! });
    const weapon = state.weapons.find((entry) => entry.weaponId === weaponId);
    if (!weapon || weapon.version !== 2 || (slot === 'attack' && !direction)) { state = { ...state, notice: 'That weapon animation is unavailable.' }; render(); return; }
    try {
      const ownedSlot: WeaponOwnedAnimationSlot = slot === 'idle' ? { slot: 'idle' } : { slot: 'attack', direction: direction! };
      const editor = new WeaponOwnedAnimationDocumentState(weapon, weapon.revision, ownedSlot);
      state = { ...state, weaponState: editor, selectedWeaponOwnedKey: slot === 'idle' ? `weapon:${weaponId}:idle` : `weapon:${weaponId}:attack:${direction}`, characterState: undefined, selectedCharacterId: undefined, draft: undefined, selectedPath: undefined, notice: undefined, loading: false, saving: false };
      render();
    } catch (error) { state = { ...state, notice: error instanceof Error ? error.message : String(error) }; render(); }
  };

  const handleClick = (event: MouseEvent): void => {
    const rawTarget = event.target instanceof Element ? event.target : undefined;
    if (rawTarget === rawTarget?.closest('[data-picker-backdrop]')) { state = { ...state, pickerOpen: false, pickerFrames: [] }; render(); return; }
    const target = rawTarget?.closest<HTMLElement>('[data-animation-id], [data-character-id], [data-character-clip], [data-character-source-frame], [data-character-timeline-index], [data-animation-entry-key], [data-animation-alias-key], [data-owned-select-layer], [data-owned-select-block], [data-weapon-id], [data-animation-action], [data-action], [data-select-layer], [data-select-block], [data-layered-playhead-frame], [data-block-hold-delta], [data-picker-frame]');
    if (!target) return;
    if (target.dataset.animationEntryKey && target.dataset.weaponId && target.dataset.weaponSlot) {
      openWeaponOwned(target.dataset.weaponId, target.dataset.weaponSlot as 'idle' | 'attack', target.dataset.weaponDirection as WeaponAttackDirection | undefined);
      return;
    }
    if (target.dataset.animationAliasKey && target.dataset.animationTargetKey?.startsWith('weapon:')) {
      const match = target.dataset.animationTargetKey.match(/^weapon:([^:]+):(idle|attack)(?::(right|left|up|down))?$/);
      if (match) openWeaponOwned(match[1]!, match[2] as 'idle' | 'attack', match[3] as WeaponAttackDirection | undefined);
      return;
    }
    if (target.dataset.animationAliasKey) {
      const sharedId = target.dataset.animationId;
      const entry = sharedId ? state.catalog?.packages.find((candidate) => candidate.animationId === sharedId) : undefined;
      if (entry) openEntry(entry);
      else { state = { ...state, notice: 'This animation alias points to a missing shared package.' }; render(); }
      return;
    }
    if (state.weaponState) {
      const editor = state.weaponState;
      if (target.dataset.ownedSelectLayer) { editor.selectLayer(target.dataset.ownedSelectLayer); render(); return; }
      if (target.dataset.ownedSelectBlock) {
        const [layerId, index] = target.dataset.ownedSelectBlock.split(':');
        if (layerId && index !== undefined) { editor.selectBlock(layerId, Number(index)); render(); }
        return;
      }
      const ownedAction = target.dataset.animationAction ?? target.dataset.action;
      if (ownedAction === 'owned-save') { void saveWeaponOwned(); return; }
      if (ownedAction === 'owned-undo') { editor.undo(); render(); return; }
      if (ownedAction === 'owned-redo') { editor.redo(); render(); return; }
      const selection = editor.value.animation.selection;
      if (ownedAction === 'owned-duplicate-block' && selection.layerId !== undefined && selection.blockIndex !== undefined) { editor.duplicateBlock(selection.layerId, selection.blockIndex); render(); return; }
      if (ownedAction === 'owned-delete-block' && selection.layerId !== undefined && selection.blockIndex !== undefined) { editor.deleteBlock(selection.layerId, selection.blockIndex); render(); return; }
      if (ownedAction === 'owned-add-layer') {
        const base = `layer-${editor.value.animation.animation.layers.length + 1}`;
        const assetId = spritesheets(state)[0]?.assetId;
        if (assetId) editor.addLayer({ layerId: base, displayName: `Layer ${editor.value.animation.animation.layers.length + 1}`, assetId, depthOffset: editor.value.animation.animation.layers.length, blocks: [] });
        render();
        return;
      }
    }
    if (state.characterState) {
      const editor = state.characterState;
      if (target.dataset.characterClip) { editor.selectClip(target.dataset.characterClip); updateRoute({ kind: 'character', characterId: editor.value.character.characterId, clipId: target.dataset.characterClip }); render(); return; }
      if (target.dataset.characterSourceFrame !== undefined) { editor.selectSourceFrame(Number(target.dataset.characterSourceFrame)); render(); return; }
      if (target.dataset.characterTimelineIndex !== undefined) { editor.selectTimelineIndex(Number(target.dataset.characterTimelineIndex)); render(); return; }
      const characterAction = target.dataset.animationAction ?? target.dataset.action;
      if (characterAction === 'save') { void saveCharacter(); return; }
      if (characterAction === 'undo') { editor.undo(); render(); return; }
      if (characterAction === 'redo') { editor.redo(); render(); return; }
      if (characterAction === 'append-character-frames' || characterAction === 'insert-character-frames') {
        const frames = editor.value.selectedSourceFrames.length > 0 ? editor.value.selectedSourceFrames : [editor.value.selectedSourceFrame];
        if (characterAction === 'append-character-frames') editor.appendSelectedFrames(frames);
        else editor.insertSelectedFrames(frames);
        render();
        return;
      }
      if (characterAction === 'duplicate-frame') { editor.duplicateSelectedFrame(); render(); return; }
      if (characterAction === 'remove-character-frame') { editor.removeSelectedFrame(); render(); return; }
      if (characterAction === 'reset-frame-visual') { editor.resetFrameVisual(editor.value.selectedSourceFrame); render(); return; }
      if (characterAction === 'reset-animation-visual') { editor.resetAnimationVisual(); render(); return; }
    }
    const characterId = target.dataset.characterId;
    if (characterId) { openCharacter(characterId); return; }
    const weaponId = target.dataset.weaponId;
    if (weaponId) {
      if ((state.draft?.value.dirty || state.characterState?.value.dirty || state.weaponState?.value.dirty) && !window.confirm('Discard unsaved animation changes?')) return;
      if (options.onSelectWeapon) queueMicrotask(() => options.onSelectWeapon?.(weaponId));
      else {
        const query = new URLSearchParams(window.location.search);
        query.set('studio', 'weapons');
        query.set('weapon', weaponId);
        query.delete('animation');
        window.location.assign(`?${query.toString()}`);
      }
      return;
    }
    const animationId = target.dataset.animationId;
    if (animationId) {
      if ((state.draft?.value.dirty || state.characterState?.value.dirty || state.weaponState?.value.dirty) && !window.confirm('Discard unsaved animation changes?')) return;
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
    if (target.dataset.characterSourceSheet !== undefined && state.characterState) {
      state.characterState.changeSourceSheet(target.value);
      render();
      return;
    }
    if (target.dataset.characterVisual !== undefined && state.characterState) {
      const editor = state.characterState;
      const parts = target.dataset.characterVisual.split('.');
      const value = Number(target.value);
      if (!Number.isFinite(value) || parts.length !== 3) return;
      const axis = parts[2] === '1' ? 1 : 0;
      const property = parts[1] === 'origin' || parts[1] === 'scale' || parts[1] === 'sourceOffset' ? parts[1] : undefined;
      if (!property) return;
      if (parts[0] === 'defaults') {
        const current = editor.value.visualSet.defaults[property];
        const next = [...current] as [number, number];
        next[axis] = value;
        editor.updateDefaults({ [property]: next } as VisualTransformDocument);
      } else if (parts[0] === 'animation' && property === 'sourceOffset') {
        const current = editor.value.visualSet.clips[editor.value.selectedClipId]?.sourceOffset ?? editor.value.visualSet.defaults.sourceOffset;
        const next = [...current] as [number, number];
        next[axis] = value;
        editor.updateAnimationVisual(next);
      } else if (parts[0] === 'frame') {
        const frame = editor.value.selectedSourceFrame;
        const current = editor.value.visualSet.frameVisuals?.[String(frame)]?.[property] ?? editor.value.visualSet.defaults[property];
        const next = [...current] as [number, number];
        next[axis] = value;
        editor.updateFrameVisual(frame, { [property]: next } as VisualTransformDocument);
      }
      render();
      return;
    }
    if (state.weaponState && target.dataset.ownedEdit) {
      const editor = state.weaponState;
      const animation = editor.value.animation.animation;
      const selection = editor.value.animation.selection;
      const layerId = selection.layerId;
      if (target.dataset.ownedEdit === 'fps') editor.setFramesPerSecond(Number(target.value));
      else if (target.dataset.ownedEdit === 'duration') editor.setDurationSeconds(Number(target.value));
      else if (target.dataset.ownedEdit === 'loop' && target instanceof HTMLInputElement) editor.setLoop(target.checked);
      else if (target.dataset.ownedEdit === 'loopMode') editor.setLoopMode(target.value === 'ping-pong' ? 'ping-pong' : 'wrap');
      else if (target.dataset.ownedEdit === 'layerAsset' && layerId) editor.setLayerAsset(layerId, target.value);
      else if (target.dataset.ownedEdit === 'layerName' && layerId) editor.renameLayer(layerId, target.value);
      if (animation) render();
      return;
    }
    if (target.dataset.studioLibrarySearch !== undefined) { state = { ...state, search: target.value }; render(); container.querySelector<HTMLInputElement>('[data-studio-library-search]')?.focus(); return; }
    const metadata = target.dataset.animationMetadata;
    if (metadata && state.draft) { state.draft.updateMetadata(metadata === 'displayName' ? { displayName: target.value } : { description: target.value }); render(); return; }
    const selection = state.draft?.value.animation.selection;
    const animationEdit = target.dataset.animationEdit;
    if (animationEdit) {
      if ((animationEdit === 'fps' || animationEdit === 'duration') && state.draft && sharedAnimationTimingLocks(state.draft.value.animationId, state.weapons).length > 0) {
        state = { ...state, notice: 'Timing is locked while a weapon attack uses markers from this package.' };
        render();
        return;
      }
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
  const handleBeforeUnload = (event: BeforeUnloadEvent): void => {
    if (!state.draft?.value.dirty && !state.characterState?.value.dirty && !state.weaponState?.value.dirty) return;
    event.preventDefault();
    event.returnValue = '';
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
  window.addEventListener('beforeunload', handleBeforeUnload);
  render();
  const query = new URLSearchParams(window.location.search);
  const initialSelection = parseAnimationStudioRoute(query);
  const requestedAnimationId = options.initialAnimationId ?? (initialSelection?.kind === 'shared' ? initialSelection.animationId : undefined);
  const requestedCharacterId = initialSelection?.kind === 'character' ? initialSelection.characterId : undefined;
  const requestedClipId = initialSelection?.kind === 'character' ? initialSelection.clipId : undefined;
  void Promise.all([loadJson<AnimationPackageCatalog>('/__animation-library/catalog'), loadJson<CharacterStudioAssetCatalog>('/__character-studio/assets'), loadJson<WeaponCatalogResponse>('/__character-studio/weapons')]).then(([catalog, assets, weaponCatalog]) => {
    const selected = catalog.packages.find((entry) => entry.animationId === requestedAnimationId) ?? catalog.packages[0];
    state = { ...state, catalog, assets, weapons: weaponCatalog.weapons, characters: characterPackages as readonly CharacterPackage[], animationCatalog: buildAnimationStudioCatalog(characterPackages as readonly CharacterPackage[], catalog, weaponCatalog.weapons), loading: false };
    if (requestedCharacterId && state.characters.some((entry) => entry.character.characterId === requestedCharacterId)) openCharacter(requestedCharacterId, requestedClipId);
    else if (initialSelection?.kind === 'weapon-idle' || initialSelection?.kind === 'weapon-attack') {
      const routeKey = initialSelection.kind === 'weapon-idle'
        ? `weapon:${initialSelection.weaponId}:idle`
        : `weapon:${initialSelection.weaponId}:attack:${initialSelection.direction}`;
      const owned = state.animationCatalog?.entries.some((entry) => entry.kind === 'weapon-owned' && (entry.slot === 'idle' ? routeKey === `weapon:${entry.weaponId}:idle` : routeKey === `weapon:${entry.weaponId}:attack:${entry.direction}`));
      const alias = state.animationCatalog?.aliases.find((candidate) => candidate.key === routeKey.replace(/^weapon:/, 'weapon-alias:'));
      const inherited = alias?.targetKey?.match(/^weapon:([^:]+):(idle|attack)(?::(right|left|up|down))?$/);
      const sharedTarget = alias?.targetAnimationId ? state.catalog?.packages.find((entry) => entry.animationId === alias.targetAnimationId) : undefined;
      if (owned) openWeaponOwned(initialSelection.weaponId, initialSelection.kind === 'weapon-idle' ? 'idle' : 'attack', initialSelection.kind === 'weapon-attack' ? initialSelection.direction : undefined);
      else if (inherited) openWeaponOwned(inherited[1]!, inherited[2] as 'idle' | 'attack', inherited[3] as WeaponAttackDirection | undefined);
      else if (sharedTarget) openEntry(sharedTarget);
      else if (selected) openEntry(selected); else render();
    } else if (selected) openEntry(selected); else render();
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
    window.removeEventListener('beforeunload', handleBeforeUnload);
    container.classList.remove('is-character-studio-host');
    container.replaceChildren();
  };
}
