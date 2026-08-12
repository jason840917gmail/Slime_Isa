import './character-studio.css';

import { characterPackages } from 'virtual-character-content';
import type { CharacterStudioAssetCatalog, CharacterStudioAssetEntry } from '../content/characters/characterAssetCatalog';
import type { EffectDefinition, EffectDirection } from '../content/effects/types';
import { resolveEffectVariant } from '../content/effects/normalize';
import { validateEffectDefinition } from '../content/effects/validation';
import { migrateLegacyAnimation, migrateLegacyWeaponDefinition } from '../content/weapons/migrateLegacyWeapon';
import type {
  AuthoredWeaponDefinition,
  LayeredWeaponDefinition,
  LegacyWeaponDefinition,
  WeaponAttackDirection,
  WeaponAttackTrackDocument,
  WeaponHitboxDocument,
} from '../content/weapons/types';
import { validateWeaponDefinition } from '../content/weapons/validation';
import { resolveAssetUrl } from '../infrastructure/assets/assetUrls';
import {
  layeredTimelineFrameCount,
  type AnimationVisualLayerDocument,
  type LayeredAnimationDocument,
} from '../shared/animation';
import { LayeredAnimationDocumentState } from './LayeredAnimationDocumentState';
import { renderLayeredAnimationTimelinePanel } from './LayeredAnimationTimelinePanel';
import {
  createLayeredAnimationTimelineView,
  renderLayeredBlockHoldControls,
  renderLayeredBlockResizeHandle,
} from './LayeredAnimationTimelineView';
import { ensureStudioModeTabs } from './StudioModeTabs';
import { resolveWeaponHitboxPreviewGeometry, WEAPON_HITBOX_PREVIEW_SCALE } from './WeaponHitboxPreview';

const DIRECTIONS = ['right', 'left', 'up', 'down'] as const satisfies readonly WeaponAttackDirection[];
const EFFECT_DIRECTIONS = DIRECTIONS satisfies readonly EffectDirection[];

type AnimationScope = 'idle' | 'attack' | 'effect';
type InspectorTab = 'identity' | 'combat' | 'layer' | 'on-hit';

type CatalogWeapon = AuthoredWeaponDefinition & { readonly revision: string };
type CatalogEffect = EffectDefinition & { readonly revision: string };
interface WeaponCatalogResponse { readonly weapons: readonly CatalogWeapon[] }
interface EffectCatalogResponse { readonly effects: readonly CatalogEffect[] }

interface StudioState {
  readonly assets?: CharacterStudioAssetCatalog;
  readonly weapons: readonly CatalogWeapon[];
  readonly effects: readonly CatalogEffect[];
  readonly selectedId: string;
  readonly draft?: LayeredWeaponDefinition;
  readonly revision?: string;
  readonly scope: AnimationScope;
  readonly direction: WeaponAttackDirection;
  readonly effectDirection: EffectDirection;
  readonly effectDraft?: EffectDefinition;
  readonly effectRevision?: string;
  readonly effectIsNew: boolean;
  readonly effectDirty: boolean;
  readonly selectedLayerId?: string;
  readonly selectedBlockIndex?: number;
  readonly selectedHitboxId?: string;
  readonly playhead: number;
  readonly inspectorTab: InspectorTab;
  readonly pickerOpen: boolean;
  readonly pickerFrames: readonly number[];
  readonly dirty: boolean;
  readonly saving: boolean;
  readonly playing: boolean;
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

function clone<T>(value: T): T { return structuredClone(value); }

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;',
  })[character] ?? character);
}

function assetInfo(asset: CharacterStudioAssetEntry | undefined) {
  const frame = asset?.frame;
  return {
    url: asset ? resolveAssetUrl(asset.sourcePath) : '',
    width: frame?.width ?? asset?.dimensions.width ?? 1,
    height: frame?.height ?? asset?.dimensions.height ?? 1,
    columns: frame?.columns ?? 1,
    rows: frame?.rows ?? 1,
    count: frame?.count ?? 1,
  };
}

function spritesheetAssets(assets: CharacterStudioAssetCatalog | undefined): readonly CharacterStudioAssetEntry[] {
  return assets?.assets.filter((asset) => asset.kind === 'spritesheet') ?? [];
}

function animationFor(state: StudioState): LayeredAnimationDocument | undefined {
  const weapon = state.draft;
  if (!weapon) return undefined;
  if (state.scope === 'idle') return weapon.animations.idle;
  if (state.scope === 'attack') {
    const attack = state.direction === 'left' && !weapon.directionalAttacks.left
      ? weapon.directionalAttacks.right
      : weapon.directionalAttacks[state.direction];
    return attack?.animation;
  }
  if (!state.effectDraft) return undefined;
  return resolveEffectVariant(state.effectDraft, state.effectDirection)?.animation;
}

function replaceAnimation(state: StudioState, animation: LayeredAnimationDocument): StudioState {
  if (!state.draft) return state;
  if (state.scope === 'idle') {
    return { ...state, draft: { ...state.draft, animations: { idle: animation } }, dirty: true };
  }
  if (state.scope === 'attack') {
    const sourceDirection = state.direction === 'left' && !state.draft.directionalAttacks.left ? 'right' : state.direction;
    const attack = state.draft.directionalAttacks[sourceDirection];
    if (!attack) return state;
    return {
      ...state,
      draft: {
        ...state.draft,
        directionalAttacks: {
          ...state.draft.directionalAttacks,
          [sourceDirection]: { ...attack, animation },
        },
      },
      dirty: true,
    };
  }
  if (!state.effectDraft) return state;
  const directions = { ...(state.effectDraft.directions ?? {}), [state.effectDirection]: { ...animation, loop: false } };
  return {
    ...state,
    effectDraft: { ...state.effectDraft, directions },
    effectDirty: true,
  };
}

function selectionForAnimation(state: StudioState, animation: LayeredAnimationDocument): StudioState {
  const layer = animation.layers.find((candidate) => candidate.layerId === state.selectedLayerId) ?? animation.layers[0];
  const blockIndex = layer && state.selectedBlockIndex !== undefined && layer.blocks[state.selectedBlockIndex]
    ? state.selectedBlockIndex
    : layer?.blocks.length ? 0 : undefined;
  const playhead = Math.min(state.playhead, layeredTimelineFrameCount(animation) - 1);
  return { ...state, selectedLayerId: layer?.layerId, selectedBlockIndex: blockIndex, playhead };
}

function transformAnimationState(
  state: StudioState,
  operation: (document: LayeredAnimationDocumentState) => boolean,
): StudioState {
  const animation = animationFor(state);
  if (!animation) return state;
  const document = new LayeredAnimationDocumentState(animation);
  if (state.selectedLayerId) document.selectLayer(state.selectedLayerId);
  if (state.selectedLayerId && state.selectedBlockIndex !== undefined) document.selectBlock(state.selectedLayerId, state.selectedBlockIndex);
  document.setPlayhead(state.playhead);
  if (!operation(document)) return { ...state, notice: 'That edit would overlap another block or leave the timeline.' };
  const value = document.value;
  return {
    ...replaceAnimation(state, value.animation),
    selectedLayerId: value.selection.layerId,
    selectedBlockIndex: value.selection.blockIndex,
    playhead: value.selection.playhead,
    notice: undefined,
  };
}

function stripWeaponRevision(entry: CatalogWeapon): AuthoredWeaponDefinition {
  const { revision: _revision, ...weapon } = entry;
  return weapon as AuthoredWeaponDefinition;
}

function stripEffectRevision(entry: CatalogEffect): EffectDefinition {
  const { revision: _revision, ...effect } = entry;
  return effect;
}

function legacyImpactEffect(weapon: LegacyWeaponDefinition): EffectDefinition | undefined {
  if (!weapon.assetId || !weapon.animations?.impact) return undefined;
  const base = migrateLegacyAnimation(weapon, weapon.animations.impact, 'impact', true);
  const rotate = (rotationDeg: number): LayeredAnimationDocument => ({
    ...clone(base),
    layers: base.layers.map((layer) => ({
      ...layer,
      blocks: layer.blocks.map((block) => ({
        ...block,
        transform: { ...(block.transform ?? {}), rotationDeg },
      })),
    })),
  });
  return {
    version: 1,
    effectId: `${weapon.weaponId}-impact`,
    displayName: `${weapon.displayName} impact`,
    mirrorLeftFromRight: true,
    directions: { right: rotate(0), up: rotate(-90), down: rotate(90) },
  };
}

interface PreparedWeapon {
  readonly draft: LayeredWeaponDefinition;
  readonly effectDraft?: EffectDefinition;
  readonly effectRevision?: string;
  readonly effectIsNew: boolean;
  readonly effectDirty: boolean;
}

function prepareWeapon(entry: CatalogWeapon, effects: readonly CatalogEffect[]): PreparedWeapon {
  const source = stripWeaponRevision(entry);
  if (source.version === 2) {
    const effect = source.onHitEffectId ? effects.find((candidate) => candidate.effectId === source.onHitEffectId) : undefined;
    return {
      draft: clone(source),
      effectDraft: effect ? clone(stripEffectRevision(effect)) : undefined,
      effectRevision: effect?.revision,
      effectIsNew: false,
      effectDirty: false,
    };
  }
  const generated = legacyImpactEffect(source);
  const existing = generated ? effects.find((candidate) => candidate.effectId === generated.effectId) : undefined;
  const onHitEffectId = existing?.effectId ?? generated?.effectId;
  return {
    draft: migrateLegacyWeaponDefinition(source, { onHitEffectId }),
    effectDraft: existing ? clone(stripEffectRevision(existing)) : generated,
    effectRevision: existing?.revision,
    effectIsNew: Boolean(generated && !existing),
    effectDirty: Boolean(generated && !existing),
  };
}

function emptyAnimation(assetId: string, loop: boolean): LayeredAnimationDocument {
  return {
    version: 2,
    durationSeconds: 1 / 12,
    framesPerSecond: 12,
    loop,
    loopMode: 'wrap',
    layers: [{ layerId: 'base', displayName: 'Base', assetId, depthOffset: 0, blocks: [{ from: 0, through: 0, sourceFrame: 0 }] }],
  };
}

function createWeaponDraft(assetId: string): LayeredWeaponDefinition {
  const attack = () => ({
    animation: emptyAnimation(assetId, false),
    characterActionId: 'attack-1',
    hitboxes: { primary: { shape: 'sector' as const, width: 42, height: 24, offsetX: 24, offsetY: 0, outerRadius: 48, arcWidthRad: 1.35 } },
    attackTrack: { hitboxSpans: [{ hitboxId: 'primary', from: 0, through: 0 }], events: [] },
  });
  return {
    version: 2,
    weaponId: 'new-weapon',
    displayName: 'New weapon',
    category: 'melee',
    characterActionId: 'attack-1',
    animations: { idle: emptyAnimation(assetId, true) },
    directionalAttacks: { right: attack(), up: attack(), down: attack() },
    presentation: { facingMode: 'vector' },
    baseDamage: 10,
    cooldownMs: 500,
    hitboxWidth: 42,
    hitboxHeight: 24,
    hitboxOffset: 24,
    hitboxDurationMs: 100,
    knockStrength: 100,
    vfxColor: 0x79e8e1,
    unlockLevel: 1,
    iconKey: 'weapon-generic',
    description: 'A reusable layered weapon definition.',
  };
}

function frameSprite(asset: CharacterStudioAssetEntry | undefined, sourceFrame: number, className: string): string {
  const info = assetInfo(asset);
  if (!info.url) return '<span class="layered-frame-missing">NO SOURCE</span>';
  const column = sourceFrame % info.columns;
  const row = Math.floor(sourceFrame / info.columns);
  return `<span class="${className}" style="--sheet-url:url('${escapeHtml(info.url)}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:${column * info.width}px;--frame-y:${row * info.height}px"></span>`;
}

function resolvedLayerAt(animation: LayeredAnimationDocument, timelineFrame: number) {
  return animation.layers.flatMap((layer, layerIndex) => {
    const blockIndex = layer.blocks.findIndex((block) => block.from <= timelineFrame && timelineFrame <= block.through);
    const block = layer.blocks[blockIndex];
    return block ? [{ layer, layerIndex, block, blockIndex }] : [];
  });
}

function characterSprite(state: StudioState): string {
  const character = characterPackages.find((entry) => entry.characterId === 'player-slime') ?? characterPackages[0];
  const asset = state.assets?.assets.find((entry) => entry.assetId === character?.visualSet.assetId);
  const actionId = state.scope === 'attack'
    ? state.draft?.directionalAttacks[state.direction]?.characterActionId ?? state.draft?.characterActionId
    : 'idle';
  const clip = character?.visualSet.clips[actionId ?? 'idle'] ?? character?.visualSet.clips.idle;
  const sourceFrame = clip?.frames[state.playhead % Math.max(1, clip.frames.length)] ?? 0;
  const info = assetInfo(asset);
  if (!asset || !info.url) return '';
  const visual = character.visualSet.frameVisuals?.[String(sourceFrame)] ?? character.visualSet.defaults;
  const origin = visual.origin ?? character.visualSet.defaults.origin;
  const scale = (visual.scale ?? character.visualSet.defaults.scale)[0] * 2.8;
  const offset = visual.sourceOffset ?? character.visualSet.defaults.sourceOffset;
  const column = sourceFrame % info.columns;
  const row = Math.floor(sourceFrame / info.columns);
  return `<span class="stage-sprite stage-character-sprite" style="--sheet-url:url('${escapeHtml(info.url)}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:${column * info.width}px;--frame-y:${row * info.height}px;--preview-scale:${scale};--origin-offset-x:${-origin[0] * info.width * scale}px;--origin-offset-y:${-origin[1] * info.height * scale}px;--offset-x:${offset[0] * scale}px;--offset-y:${offset[1] * scale}px"></span>`;
}

function layerPreviewSprite(state: StudioState, layer: AnimationVisualLayerDocument, block: AnimationVisualLayerDocument['blocks'][number], layerIndex: number): string {
  const asset = state.assets?.assets.find((entry) => entry.assetId === layer.assetId);
  const info = assetInfo(asset);
  if (!info.url) return '';
  const transform = layer.transform ?? {};
  const blockTransform = block.transform ?? {};
  const scale = [
    (transform.scale?.[0] ?? 1) * (blockTransform.scale?.[0] ?? 1) * 2.8,
    (transform.scale?.[1] ?? 1) * (blockTransform.scale?.[1] ?? 1) * 2.8,
  ] as const;
  const origin = transform.origin ?? [0.5, 0.5];
  const offset = [
    (transform.offset?.[0] ?? 0) + (blockTransform.offset?.[0] ?? 0),
    (transform.offset?.[1] ?? 0) + (blockTransform.offset?.[1] ?? 0),
  ] as const;
  const column = block.sourceFrame % info.columns;
  const row = Math.floor(block.sourceFrame / info.columns);
  const flipX = Boolean(blockTransform.flipX) !== Boolean(transform.flipX);
  const rotation = (transform.rotationDeg ?? 0) + (blockTransform.rotationDeg ?? 0);
  return `<span class="stage-sprite stage-weapon-sprite${layer.layerId === state.selectedLayerId ? ' is-selected-layer' : ''}" data-preview-layer="${escapeHtml(layer.layerId)}" style="z-index:${3 + layerIndex};--sheet-url:url('${escapeHtml(info.url)}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:${column * info.width}px;--frame-y:${row * info.height}px;--preview-scale-x:${scale[0]};--preview-scale-y:${scale[1]};--origin-offset-x:${-origin[0] * info.width * scale[0]}px;--origin-offset-y:${-origin[1] * info.height * scale[1]}px;--offset-x:${offset[0] * 2.8}px;--offset-y:${offset[1] * 2.8}px;--weapon-rotation:${rotation}deg;--weapon-flip-x:${flipX ? -1 : 1}"></span>`;
}

function renderPreviewHitboxes(state: StudioState): string {
  if (state.scope !== 'attack') return '';
  const attack = selectedAttack(state);
  if (!attack) return '';
  const spans = attack.attackTrack?.hitboxSpans ?? [];
  return `<span class="weapon-hitbox-guides">${Object.entries(attack.hitboxes).map(([hitboxId, hitbox], index) => {
    const geometry = resolveWeaponHitboxPreviewGeometry(hitbox, state.direction);
    const active = spans.some((span) => span.hitboxId === hitboxId && span.from <= state.playhead && state.playhead <= span.through);
    const selected = hitboxId === state.selectedHitboxId || (!state.selectedHitboxId && index === 0);
    const classes = `stage-hitbox stage-hitbox--${geometry.shape}${active ? ' is-hot' : ''}${selected ? ' is-selected' : ''}${geometry.valid ? '' : ' is-invalid'}`;
    const label = `<button type="button" class="stage-hitbox-select" style="--hitbox-label-index:${index}" data-select-hitbox="${escapeHtml(hitboxId)}">${escapeHtml(hitboxId)}</button>`;
    if (!geometry.valid) return `<span class="${classes}" style="transform:translate(-50%,-50%)">${label}</span>`;
    const style = `width:${geometry.width * WEAPON_HITBOX_PREVIEW_SCALE}px;height:${geometry.height * WEAPON_HITBOX_PREVIEW_SCALE}px;transform:translate(-50%,-50%) translate(${geometry.centerX * WEAPON_HITBOX_PREVIEW_SCALE}px,${geometry.centerY * WEAPON_HITBOX_PREVIEW_SCALE}px)`;
    const sector = geometry.shape === 'sector' ? `<svg class="weapon-hitbox-sector" viewBox="${geometry.sectorViewBox}" aria-hidden="true"><path class="weapon-hitbox-sector-area" fill-rule="evenodd" d="${geometry.sectorAreaPath ?? ''}"></path>${geometry.sectorBoundaryPath ? `<path class="weapon-hitbox-sector-boundary" d="${geometry.sectorBoundaryPath}"></path>` : ''}</svg>` : '';
    return `<span class="${classes}" style="${style}">${sector}${label}</span>`;
  }).join('')}</span>`;
}

function renderPreview(state: StudioState, animation: LayeredAnimationDocument): string {
  const duration = layeredTimelineFrameCount(animation) / animation.framesPerSecond;
  const activeLayers = resolvedLayerAt(animation, state.playhead);
  const effectOnly = state.scope === 'effect';
  return `<section class="studio-preview-card weapon-preview-card layered-preview-card"><div class="studio-preview-toolbar"><span class="studio-kicker">COMBINED PREVIEW</span><span class="studio-muted">${state.scope.toUpperCase()}${state.scope === 'idle' ? '' : ` / ${(state.scope === 'effect' ? state.effectDirection : state.direction).toUpperCase()}`} · ${Number(state.playhead / animation.framesPerSecond).toFixed(2)}s / ${duration.toFixed(2)}s · ${activeLayers.length} active layer${activeLayers.length === 1 ? '' : 's'}</span><button type="button" class="studio-button studio-button--quiet" data-action="play-preview">${state.playing ? '■ STOP' : '▶ PLAY'}</button></div><div class="studio-stage weapon-stage layered-preview"><span class="stage-axis stage-axis-x"></span><span class="stage-axis stage-axis-y"></span><span class="stage-anchor">+</span><span class="stage-label">${effectOnly ? 'ENEMY CONTACT' : 'PLAYER ANCHOR'}</span>${effectOnly ? '' : characterSprite(state)}${activeLayers.map(({ layer, layerIndex, block }) => layerPreviewSprite(state, layer, block, layerIndex)).join('')}${renderPreviewHitboxes(state)}<span class="stage-caption"><b>${escapeHtml(state.scope === 'effect' ? state.effectDraft?.displayName : state.draft?.displayName)}</b><span>${activeLayers.map(({ layer, block }) => `${escapeHtml(layer.displayName)} · TILE ${block.sourceFrame}`).join('  /  ') || 'NO VISUAL AT PLAYHEAD'}</span></span></div><div class="studio-preview-footer"><span><i class="legend-dot legend-dot--cyan"></i> shared clock</span><span><i class="legend-dot legend-dot--amber"></i> selected visual layer</span><span><i class="legend-dot legend-dot--red"></i> hitbox active window</span><span>Effects spawn only after confirmed damage.</span></div></section>`;
}

function selectedAttack(state: StudioState) {
  if (!state.draft) return undefined;
  return state.draft.directionalAttacks[state.direction]
    ?? (state.direction === 'left' ? state.draft.directionalAttacks.right : undefined);
}

function toggleSpan(track: WeaponAttackTrackDocument, hitboxId: string, frame: number): WeaponAttackTrackDocument {
  const spans = [...track.hitboxSpans];
  const containing = spans.findIndex((span) => span.hitboxId === hitboxId && span.from <= frame && frame <= span.through);
  if (containing >= 0) {
    const span = spans[containing];
    spans.splice(containing, 1);
    if (span.from < frame) spans.push({ ...span, through: frame - 1 });
    if (frame < span.through) spans.push({ ...span, from: frame + 1 });
  } else {
    spans.push({ hitboxId, from: frame, through: frame });
    spans.sort((left, right) => left.from - right.from);
    for (let index = spans.length - 1; index > 0; index -= 1) {
      const left = spans[index - 1];
      const right = spans[index];
      if (left.hitboxId === right.hitboxId && left.through + 1 >= right.from) {
        spans.splice(index - 1, 2, { hitboxId, from: Math.min(left.from, right.from), through: Math.max(left.through, right.through) });
      }
    }
  }
  return { ...track, hitboxSpans: spans };
}

function renderAttackRows(state: StudioState, animation: LayeredAnimationDocument): string {
  if (state.scope !== 'attack') return '';
  const attack = selectedAttack(state);
  if (!attack) return '';
  const frameCount = layeredTimelineFrameCount(animation);
  const track = attack.attackTrack ?? { hitboxSpans: [], events: [] };
  return Object.keys(attack.hitboxes).map((hitboxId) => `<div class="timeline-track-row layered-host-row"><button type="button" class="timeline-track-label layered-track-label${hitboxId === state.selectedHitboxId ? ' is-selected' : ''}" data-select-hitbox="${escapeHtml(hitboxId)}">${escapeHtml(hitboxId)}</button>${Array.from({ length: frameCount }, (_, frame) => `<button type="button" class="timeline-cell${track.hitboxSpans.some((span) => span.hitboxId === hitboxId && span.from <= frame && frame <= span.through) ? ' is-hot' : ''}" data-toggle-hitbox-frame="${frame}" data-hitbox-id="${escapeHtml(hitboxId)}" aria-label="Toggle ${escapeHtml(hitboxId)} at frame ${frame}"></button>`).join('')}</div>`).join('');
}

function renderBlock(state: StudioState, animation: LayeredAnimationDocument, layerId: string, blockIndex: number): string {
  const layer = animation.layers.find((candidate) => candidate.layerId === layerId)!;
  const block = layer.blocks[blockIndex];
  const asset = state.assets?.assets.find((entry) => entry.assetId === layer.assetId);
  const hold = block.through - block.from + 1;
  const selected = layerId === state.selectedLayerId && blockIndex === state.selectedBlockIndex;
  return `<article class="timeline-frame layered-timeline-block${selected ? ' is-selected' : ''}" style="grid-column:${block.from + 1} / span ${hold}" data-layer-block data-layer-id="${escapeHtml(layerId)}" data-block-index="${blockIndex}"><button type="button" class="timeline-frame-select" data-select-block data-layer-id="${escapeHtml(layerId)}" data-block-index="${blockIndex}">${frameSprite(asset, block.sourceFrame, 'timeline-tile-preview')}<b class="timeline-frame-number">${String(block.from).padStart(2, '0')}</b><small class="timeline-frame-source">SRC ${block.sourceFrame}</small><span class="timeline-frame-hold">${Number(hold / animation.framesPerSecond).toFixed(2)}s / ${hold}F</span></button>${renderLayeredBlockHoldControls(layerId, blockIndex, hold)}<button type="button" class="layered-block-delete" data-delete-block data-layer-id="${escapeHtml(layerId)}" data-block-index="${blockIndex}" aria-label="Delete block">×</button>${renderLayeredBlockResizeHandle(layerId, blockIndex, hold)}</article>`;
}

function renderTimeline(state: StudioState, animation: LayeredAnimationDocument): string {
  return renderLayeredAnimationTimelinePanel({
    titleHtml: `Editing ${escapeHtml(state.scope)}${state.scope === 'idle' ? '' : ` / ${escapeHtml(state.scope === 'effect' ? state.effectDirection : state.direction)}`}`,
    hint: 'Each layer has its own source · blocks share one seconds clock · drag the right edge to resize',
    timeline: createLayeredAnimationTimelineView(animation),
    selectedLayerId: state.selectedLayerId,
    selectedBlockIndex: state.selectedBlockIndex,
    playhead: state.playhead,
    hostRowsHtml: renderAttackRows(state, animation),
    renderBlock: (layerId, blockIndex) => renderBlock(state, animation, layerId, blockIndex),
  });
}

function inputField(label: string, field: string, value: string | number, options: { readonly type?: string; readonly step?: string; readonly hint?: string } = {}): string {
  return `<label class="studio-field"><span>${escapeHtml(label)}${options.hint ? `<small>${escapeHtml(options.hint)}</small>` : ''}</span><input type="${options.type ?? 'text'}" ${options.step ? `step="${options.step}"` : ''} value="${escapeHtml(value)}" data-weapon-field="${escapeHtml(field)}" /></label>`;
}

function selectedLayer(state: StudioState, animation: LayeredAnimationDocument): AnimationVisualLayerDocument | undefined {
  return animation.layers.find((layer) => layer.layerId === state.selectedLayerId) ?? animation.layers[0];
}

function renderIdentityInspector(state: StudioState): string {
  const weapon = state.draft!;
  return `<section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Identity</span><strong>Reusable weapon package</strong></div><div class="studio-field-grid">${inputField('Stable ID', 'weaponId', weapon.weaponId, { hint: 'lowercase kebab-case' })}${inputField('Display name', 'displayName', weapon.displayName)}</div><label class="studio-field studio-field--wide"><span>Category<small>combat family</small></span><select data-weapon-field="category"><option value="melee" ${weapon.category === 'melee' ? 'selected' : ''}>Melee</option><option value="ranged" ${weapon.category === 'ranged' ? 'selected' : ''}>Ranged</option></select></label>${inputField('Default character action', 'characterActionId', weapon.characterActionId)}${inputField('Description', 'description', weapon.description)}</section>`;
}

function renderCombatInspector(state: StudioState): string {
  const weapon = state.draft!;
  const attack = selectedAttack(state);
  const hitboxes = attack?.hitboxes ?? {};
  const selectedId = state.selectedHitboxId && hitboxes[state.selectedHitboxId] ? state.selectedHitboxId : Object.keys(hitboxes)[0];
  const hitbox = selectedId ? hitboxes[selectedId] : undefined;
  return `<section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Combat profile</span><strong>Damage and timing</strong></div><div class="studio-field-grid">${inputField('Base damage', 'baseDamage', weapon.baseDamage, { type: 'number', step: '1' })}${inputField('Cooldown', 'cooldownMs', weapon.cooldownMs, { type: 'number', step: '1', hint: 'milliseconds' })}${inputField('Knockback', 'knockStrength', weapon.knockStrength, { type: 'number', step: '1' })}${inputField('Unlock level', 'unlockLevel', weapon.unlockLevel, { type: 'number', step: '1' })}</div></section><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Directional collision</span><strong>${state.direction.toUpperCase()} hitboxes</strong><button type="button" class="studio-icon-button" data-action="add-hitbox" aria-label="Add hitbox">+</button></div><div class="layered-hitbox-tabs">${Object.keys(hitboxes).map((id) => `<button type="button" class="studio-pill${id === selectedId ? ' is-active' : ''}" data-select-hitbox="${escapeHtml(id)}">${escapeHtml(id)}</button>`).join('')}</div>${hitbox && selectedId ? renderHitboxFields(selectedId, hitbox) : '<p class="studio-empty-note">Add a hitbox for this direction.</p>'}</section>`;
}

function renderHitboxFields(hitboxId: string, hitbox: WeaponHitboxDocument): string {
  return `<div class="layered-hitbox-editor"><div class="studio-field-grid"><label class="studio-field"><span>Shape<small>runtime primitive</small></span><select data-hitbox-field="shape" data-hitbox-id="${escapeHtml(hitboxId)}">${['rectangle', 'circle', 'ellipse', 'sector'].map((shape) => `<option value="${shape}" ${hitbox.shape === shape ? 'selected' : ''}>${shape}</option>`).join('')}</select></label>${inputField('Width', `hitbox:${hitboxId}:width`, hitbox.width, { type: 'number', step: '1' })}${inputField('Height', `hitbox:${hitboxId}:height`, hitbox.height, { type: 'number', step: '1' })}${inputField('Offset X', `hitbox:${hitboxId}:offsetX`, hitbox.offsetX, { type: 'number', step: '1' })}${inputField('Offset Y', `hitbox:${hitboxId}:offsetY`, hitbox.offsetY, { type: 'number', step: '1' })}${hitbox.shape === 'sector' ? `${inputField('Outer radius', `hitbox:${hitboxId}:outerRadius`, hitbox.outerRadius ?? 1, { type: 'number', step: '1' })}${inputField('Arc radians', `hitbox:${hitboxId}:arcWidthRad`, hitbox.arcWidthRad ?? 1.35, { type: 'number', step: '0.01' })}` : ''}</div><button type="button" class="studio-button studio-button--danger" data-action="delete-hitbox" data-hitbox-id="${escapeHtml(hitboxId)}">DELETE HITBOX</button></div>`;
}

function renderLayerInspector(state: StudioState, animation: LayeredAnimationDocument): string {
  const layer = selectedLayer(state, animation);
  if (!layer) return `<section class="studio-inspector-section"><p class="studio-empty-note">Add a visual layer to start this animation.</p></section>`;
  const options = spritesheetAssets(state.assets).map((asset) => `<option value="${escapeHtml(asset.assetId)}" ${asset.assetId === layer.assetId ? 'selected' : ''}>${escapeHtml(asset.assetId)}</option>`).join('');
  const transform = layer.transform ?? {};
  return `<section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Visual layer</span><strong>${escapeHtml(layer.displayName)}</strong></div>${inputField('Layer name', 'layer:displayName', layer.displayName)}<label class="studio-field studio-field--wide"><span>Source sheet<small>one source per layer</small></span><select data-layer-field="assetId">${options}</select></label><div class="studio-field-grid">${inputField('Depth', 'layer:depthOffset', layer.depthOffset, { type: 'number', step: '0.1' })}${inputField('Offset X', 'layer:offsetX', transform.offset?.[0] ?? 0, { type: 'number', step: '0.1' })}${inputField('Offset Y', 'layer:offsetY', transform.offset?.[1] ?? 0, { type: 'number', step: '0.1' })}${inputField('Scale X', 'layer:scaleX', transform.scale?.[0] ?? 1, { type: 'number', step: '0.01' })}${inputField('Scale Y', 'layer:scaleY', transform.scale?.[1] ?? 1, { type: 'number', step: '0.01' })}${inputField('Rotation', 'layer:rotationDeg', transform.rotationDeg ?? 0, { type: 'number', step: '1', hint: 'degrees' })}</div><div class="layered-layer-actions"><button type="button" class="studio-button studio-button--quiet" data-action="layer-up">↑ FRONT</button><button type="button" class="studio-button studio-button--quiet" data-action="layer-down">↓ BACK</button><button type="button" class="studio-button studio-button--danger" data-action="delete-layer">DELETE LAYER</button></div></section>`;
}

function renderOnHitInspector(state: StudioState): string {
  const effectId = state.draft?.onHitEffectId ?? '';
  return `<section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Confirmed contact</span><strong>On-hit effect</strong></div><p class="studio-help">This effect spawns at the enemy contact edge only after positive damage is accepted.</p><label class="studio-field studio-field--wide"><span>Effect package<small>reusable library asset</small></span><select data-weapon-field="onHitEffectId"><option value="">No effect</option>${state.effects.map((effect) => `<option value="${escapeHtml(effect.effectId)}" ${effect.effectId === effectId ? 'selected' : ''}>${escapeHtml(effect.displayName)}</option>`).join('')}${state.effectDraft && !state.effects.some((effect) => effect.effectId === state.effectDraft?.effectId) ? `<option value="${escapeHtml(state.effectDraft.effectId)}" selected>${escapeHtml(state.effectDraft.displayName)} (new)</option>` : ''}</select></label><button type="button" class="studio-button studio-button--accent" data-action="create-effect-from-current">CREATE EFFECT FROM CURRENT ART</button>${state.effectDraft ? `<div class="studio-callout"><strong>${escapeHtml(state.effectDraft.displayName)}</strong><span>${escapeHtml(state.effectDraft.effectId)} · directional variants share this editor</span></div>` : ''}</section>`;
}

function renderInspector(state: StudioState, animation: LayeredAnimationDocument): string {
  const tabs: readonly [InspectorTab, string, string][] = [
    ['identity', 'IDENTITY', 'package'], ['combat', 'COMBAT', 'hitboxes'], ['layer', 'LAYER', 'visuals'], ['on-hit', 'ON HIT', 'contact'],
  ];
  return `<aside class="studio-inspector layered-weapon-inspector"><div class="studio-inspector-heading"><span class="studio-kicker">Inspector</span><h2>Weapon controls</h2><p>One animation model, specialized weapon tracks.</p></div><nav class="weapon-inspector-tabs layered-inspector-tabs">${tabs.map(([id, label, hint]) => `<button type="button" class="weapon-inspector-tab${state.inspectorTab === id ? ' is-active' : ''}" data-inspector-tab="${id}"><strong>${label}</strong><small>${hint}</small></button>`).join('')}</nav><div class="studio-inspector-scroll">${state.inspectorTab === 'identity' ? renderIdentityInspector(state) : state.inspectorTab === 'combat' ? renderCombatInspector(state) : state.inspectorTab === 'layer' ? renderLayerInspector(state, animation) : renderOnHitInspector(state)}</div></aside>`;
}

function renderScopeControls(state: StudioState, animation: LayeredAnimationDocument): string {
  const effectReady = Boolean(state.effectDraft);
  return `<section class="layered-scope-strip"><div class="studio-clip-tabs"><button type="button" class="studio-clip-tab${state.scope === 'idle' ? ' is-active' : ''}" data-scope="idle"><span>IDLE</span><small>${state.draft?.animations.idle.layers.length ?? 0} layers</small></button><button type="button" class="studio-clip-tab${state.scope === 'attack' ? ' is-active' : ''}" data-scope="attack"><span>ATTACK</span><small>directional</small></button><button type="button" class="studio-clip-tab${state.scope === 'effect' ? ' is-active' : ''}" data-scope="effect" ${effectReady ? '' : 'disabled'}><span>ON-HIT EFFECT</span><small>${effectReady ? 'contact' : 'none assigned'}</small></button></div>${state.scope === 'attack' ? `<div class="layered-direction-tabs">${DIRECTIONS.map((direction) => `<button type="button" class="studio-pill${state.direction === direction ? ' is-active' : ''}" data-direction="${direction}">${direction.toUpperCase()}${direction === 'left' && !state.draft?.directionalAttacks.left ? ' · MIRROR R' : ''}</button>`).join('')}</div>` : state.scope === 'effect' ? `<div class="layered-direction-tabs">${EFFECT_DIRECTIONS.map((direction) => `<button type="button" class="studio-pill${state.effectDirection === direction ? ' is-active' : ''}" data-effect-direction="${direction}">${direction.toUpperCase()}</button>`).join('')}</div>` : ''}<div class="layered-clock-controls"><label>FPS <input type="number" min="1" max="240" step="1" value="${animation.framesPerSecond}" data-animation-field="fps" /></label><label>DURATION <input type="number" min="0.01" max="60" step="0.01" value="${animation.durationSeconds}" data-animation-field="duration" /><span>s</span></label></div></section>`;
}

function renderPicker(state: StudioState, animation: LayeredAnimationDocument): string {
  if (!state.pickerOpen) return '';
  const layer = selectedLayer(state, animation);
  const asset = state.assets?.assets.find((candidate) => candidate.assetId === layer?.assetId);
  const info = assetInfo(asset);
  return `<div class="studio-asset-shelf-backdrop layered-tile-picker-backdrop" data-picker-backdrop><section class="studio-asset-shelf weapon-tile-picker" role="dialog" aria-modal="true" aria-labelledby="layered-tile-picker-title"><header class="studio-asset-shelf-heading"><div><span class="studio-kicker">${escapeHtml(layer?.displayName ?? 'Layer')} source</span><h2 id="layered-tile-picker-title">Add tiles to animation</h2><p>Source tiles stay in this popup. The timeline only shows authored blocks and their hold time.</p></div><button type="button" class="studio-icon-button" data-action="close-picker" aria-label="Close">×</button></header><div class="studio-sheet-grid projectile-frame-grid weapon-picker-grid">${Array.from({ length: info.count }, (_, frame) => `<button type="button" class="projectile-frame-option${state.pickerFrames.includes(frame) ? ' is-selected' : ''}" data-picker-frame="${frame}" aria-pressed="${state.pickerFrames.includes(frame)}">${frameSprite(asset, frame, 'projectile-frame-preview')}<span>${String(frame).padStart(2, '0')}</span></button>`).join('')}</div><footer class="weapon-tile-picker-footer"><span>${state.pickerFrames.length} selected · inserted at playhead ${state.playhead}</span><div><button type="button" class="studio-button studio-button--quiet" data-action="close-picker">CANCEL</button><button type="button" class="studio-button studio-button--accent" data-action="confirm-picker" ${state.pickerFrames.length ? '' : 'disabled'}>ADD TO LAYER</button></div></footer></section></div>`;
}

function renderStudio(state: StudioState, returnEditor: string): string {
  const animation = animationFor(state);
  if (!state.draft || !animation) {
    return `<main class="character-studio weapon-studio layered-weapon-studio"><header class="studio-topbar"><a class="studio-brand" href="?"><span class="brand-mark">✦</span><span><small>FIELD CARTOGRAPHER</small><strong>WEAPON STUDIO</strong></span></a><div class="studio-topbar-actions"><span class="studio-save-state"><i></i>${escapeHtml(state.notice ?? 'Loading layered weapon library…')}</span></div></header><section class="studio-empty-state"><span class="studio-loading-orb">✦</span><h2>${escapeHtml(state.notice ?? 'Loading weapons')}</h2></section></main>`;
  }
  const isNew = !state.revision;
  return `<main class="character-studio weapon-studio layered-weapon-studio${state.dirty || state.effectDirty ? ' is-dirty' : ''}"><header class="studio-topbar"><a class="studio-brand" href="?" aria-label="Back to game"><span class="brand-mark">✦</span><span><small>FIELD CARTOGRAPHER</small><strong>WEAPON STUDIO</strong></span></a><div class="studio-topbar-actions"><span class="studio-save-state${state.notice ? ' is-error' : ''}"><i></i>${escapeHtml(state.notice ?? (state.dirty || state.effectDirty ? 'Unsaved layered package' : 'Saved library'))}</span><button type="button" class="studio-button studio-button--save" data-action="save" ${(!state.dirty && !state.effectDirty) || state.saving ? 'disabled' : ''}>${state.saving ? 'SAVING…' : isNew ? 'CREATE WEAPON' : 'SAVE WEAPON'}</button></div></header><div class="studio-layout"><aside class="studio-library"><div class="studio-panel-title"><div><span class="studio-kicker">Equipment library</span><h1>Weapons</h1></div><span class="studio-count">${String(state.weapons.length).padStart(2, '0')}</span></div><div class="studio-roster">${state.weapons.map((weapon) => `<button type="button" class="studio-roster-item${weapon.weaponId === state.selectedId ? ' is-active' : ''}" data-weapon-id="${escapeHtml(weapon.weaponId)}"><span class="roster-glyph player">◆</span><span><strong>${escapeHtml(weapon.displayName)}</strong><small>V${weapon.version} · ${weapon.category.toUpperCase()}</small></span><em>${weapon.weaponId === state.selectedId ? 'OPEN' : ''}</em></button>`).join('')}</div><div class="studio-library-footer"><button type="button" class="studio-button studio-button--outline" data-action="new-weapon">NEW WEAPON</button><a class="studio-button studio-button--outline studio-button--navigation" href="?studio=characters&editor=${encodeURIComponent(returnEditor)}">↗ CHARACTER STUDIO</a></div></aside><section class="studio-workbench"><div class="studio-workbench-heading"><div><span class="studio-kicker">Layered animation package</span><h2>${escapeHtml(state.draft.displayName)} <span>V2</span></h2></div><div class="studio-workbench-meta"><span>WEAPON <b>${escapeHtml(state.draft.weaponId)}</b></span><span>PLAYHEAD <b>${Number(state.playhead / animation.framesPerSecond).toFixed(2)}s</b></span><span>LAYERS <b>${animation.layers.length}</b></span></div></div>${renderPreview(state, animation)}${renderScopeControls(state, animation)}${renderTimeline(state, animation)}</section>${renderInspector(state, animation)}</div>${renderPicker(state, animation)}</main>`;
}

async function loadJson<T>(url: string): Promise<T> {
  const response = await fetch(url);
  const payload = await response.json() as { ok?: boolean; data?: T; error?: { message?: string } };
  if (!response.ok || payload.ok === false || !payload.data) throw new Error(payload.error?.message ?? `Failed to load ${url}`);
  return payload.data;
}

function withLayer(state: StudioState, update: (layer: AnimationVisualLayerDocument) => AnimationVisualLayerDocument): StudioState {
  const animation = animationFor(state);
  if (!animation || !state.selectedLayerId) return state;
  const layers = animation.layers.map((layer) => layer.layerId === state.selectedLayerId ? update(layer) : layer);
  return replaceAnimation(state, { ...animation, layers });
}

function updateWeaponField(state: StudioState, field: string, value: string): StudioState {
  if (!state.draft) return state;
  if (field.startsWith('hitbox:')) {
    const [, hitboxId, hitboxField] = field.split(':');
    const attack = selectedAttack(state);
    if (!attack || !hitboxId || !hitboxField) return state;
    const nextValue = hitboxField === 'shape' ? value : Number(value);
    if (hitboxField !== 'shape' && !Number.isFinite(nextValue)) return state;
    const sourceDirection = state.direction === 'left' && !state.draft.directionalAttacks.left ? 'right' : state.direction;
    const hitbox = attack.hitboxes[hitboxId];
    return {
      ...state,
      draft: {
        ...state.draft,
        directionalAttacks: {
          ...state.draft.directionalAttacks,
          [sourceDirection]: { ...attack, hitboxes: { ...attack.hitboxes, [hitboxId]: { ...hitbox, [hitboxField]: nextValue } } },
        },
      },
      dirty: true,
    };
  }
  if (field.startsWith('layer:')) {
    const layerField = field.slice('layer:'.length);
    return withLayer(state, (layer) => {
      if (layerField === 'displayName') return { ...layer, displayName: value };
      if (layerField === 'depthOffset') return { ...layer, depthOffset: Number(value) };
      const transform = { ...(layer.transform ?? {}) };
      if (layerField === 'offsetX' || layerField === 'offsetY') {
        const offset = [...(transform.offset ?? [0, 0])] as [number, number];
        offset[layerField === 'offsetX' ? 0 : 1] = Number(value);
        transform.offset = offset;
      } else if (layerField === 'scaleX' || layerField === 'scaleY') {
        const scale = [...(transform.scale ?? [1, 1])] as [number, number];
        scale[layerField === 'scaleX' ? 0 : 1] = Number(value);
        transform.scale = scale;
      } else if (layerField === 'rotationDeg') transform.rotationDeg = Number(value);
      return { ...layer, transform };
    });
  }
  const numericFields = new Set(['baseDamage', 'cooldownMs', 'knockStrength', 'unlockLevel']);
  return { ...state, draft: { ...state.draft, [field]: numericFields.has(field) ? Number(value) : value }, dirty: true };
}

async function savePackage(state: StudioState): Promise<Partial<StudioState>> {
  if (!state.draft) throw new Error('No weapon is open');
  const weaponIssues = validateWeaponDefinition(state.draft);
  if (weaponIssues.length) throw new Error(weaponIssues[0]);
  if (state.effectDraft) {
    const effectIssues = validateEffectDefinition(state.effectDraft, {
      assetLookup: (assetId) => {
        const asset = state.assets?.assets.find((candidate) => candidate.assetId === assetId);
        return asset ? { kind: asset.kind, frameCount: asset.frame?.count ?? 1 } : undefined;
      },
    });
    if (effectIssues.length) throw new Error(effectIssues[0]);
  }
  const response = await fetch('/__character-studio/weapon/save-package', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      weapon: state.draft,
      weaponOperation: state.revision ? 'update' : 'create',
      ...(state.revision ? { expectedWeaponRevision: state.revision } : {}),
      ...(state.effectDraft && state.effectDirty ? {
        effect: state.effectDraft,
        effectOperation: state.effectIsNew ? 'create' : 'update',
        ...(state.effectIsNew ? {} : { expectedEffectRevision: state.effectRevision }),
      } : {}),
    }),
  });
  const payload = await response.json() as { ok?: boolean; data?: { weaponRevision: string; effectRevision?: string }; error?: { message?: string } };
  if (!response.ok || !payload.ok || !payload.data) throw new Error(payload.error?.message ?? 'Weapon package save failed');
  return { revision: payload.data.weaponRevision, effectRevision: payload.data.effectRevision ?? state.effectRevision, effectIsNew: false, effectDirty: false, dirty: false, notice: 'Saved. Reload the game to use changed content.' };
}

export function mountLayeredWeaponStudio(container: HTMLDivElement): () => void {
  container.classList.add('is-character-studio-host');
  const returnEditor = new URLSearchParams(window.location.search).get('editor') ?? 'meadow-crossing';
  let state: StudioState = {
    weapons: [], effects: [], selectedId: '', scope: 'attack', direction: 'right', effectDirection: 'right',
    effectIsNew: false, effectDirty: false, playhead: 0, inspectorTab: 'layer', pickerOpen: false,
    pickerFrames: [], dirty: false, saving: false, playing: false,
  };
  let resize: ResizeDrag | undefined;
  let playbackTimer: number | undefined;

  const stopPlayback = (): void => {
    if (playbackTimer !== undefined) window.clearInterval(playbackTimer);
    playbackTimer = undefined;
    state = { ...state, playing: false };
  };
  const render = (): void => {
    const workbench = container.querySelector<HTMLElement>('.studio-workbench');
    const inspector = container.querySelector<HTMLElement>('.studio-inspector-scroll');
    const workbenchScroll = workbench ? { top: workbench.scrollTop, left: workbench.scrollLeft } : undefined;
    const inspectorScroll = inspector?.scrollTop ?? 0;
    container.innerHTML = renderStudio(state, returnEditor);
    ensureStudioModeTabs(container, returnEditor, 'weapons');
    const nextWorkbench = container.querySelector<HTMLElement>('.studio-workbench');
    if (nextWorkbench && workbenchScroll) { nextWorkbench.scrollTop = workbenchScroll.top; nextWorkbench.scrollLeft = workbenchScroll.left; }
    const nextInspector = container.querySelector<HTMLElement>('.studio-inspector-scroll');
    if (nextInspector) nextInspector.scrollTop = inspectorScroll;
  };
  const selectCatalogWeapon = (entry: CatalogWeapon): void => {
    stopPlayback();
    const prepared = prepareWeapon(entry, state.effects);
    const animation = prepared.draft.directionalAttacks.right.animation;
    state = selectionForAnimation({
      ...state, ...prepared, selectedId: entry.weaponId, revision: entry.revision, scope: 'attack', direction: 'right',
      effectDirection: 'right', playhead: 0, dirty: entry.version === 1, inspectorTab: 'layer', pickerOpen: false,
      notice: entry.version === 1 ? 'Legacy weapon migrated in memory. Save to commit version 2.' : undefined,
    }, animation);
    render();
  };
  const mutate = (next: StudioState): void => { state = next; render(); };
  const mutateAnimation = (operation: (document: LayeredAnimationDocumentState) => boolean): void => mutate(transformAnimationState(state, operation));
  const updateAttack = (update: (attack: NonNullable<ReturnType<typeof selectedAttack>>) => NonNullable<ReturnType<typeof selectedAttack>>): void => {
    if (!state.draft) return;
    const attack = selectedAttack(state);
    if (!attack) return;
    const sourceDirection = state.direction === 'left' && !state.draft.directionalAttacks.left ? 'right' : state.direction;
    mutate({ ...state, draft: { ...state.draft, directionalAttacks: { ...state.draft.directionalAttacks, [sourceDirection]: update(attack) } }, dirty: true });
  };

  const handleClick = (event: MouseEvent): void => {
    const target = event.target instanceof Element ? event.target : undefined;
    if (!target) return;
    if (target === target.closest('[data-picker-backdrop]')) { mutate({ ...state, pickerOpen: false, pickerFrames: [] }); return; }
    const weaponButton = target.closest<HTMLElement>('[data-weapon-id]');
    if (weaponButton) { const entry = state.weapons.find((weapon) => weapon.weaponId === weaponButton.dataset.weaponId); if (entry) selectCatalogWeapon(entry); return; }
    const tab = target.closest<HTMLElement>('[data-inspector-tab]');
    if (tab) { mutate({ ...state, inspectorTab: tab.dataset.inspectorTab as InspectorTab }); return; }
    const scope = target.closest<HTMLElement>('[data-scope]')?.dataset.scope as AnimationScope | undefined;
    if (scope) {
      const scoped = { ...state, scope, playhead: 0 };
      const animation = animationFor(scoped);
      if (animation) mutate(selectionForAnimation(scoped, animation));
      return;
    }
    const direction = target.closest<HTMLElement>('[data-direction]')?.dataset.direction as WeaponAttackDirection | undefined;
    if (direction) { const next = { ...state, direction, playhead: 0 }; const animation = animationFor(next); if (animation) mutate(selectionForAnimation(next, animation)); return; }
    const effectDirection = target.closest<HTMLElement>('[data-effect-direction]')?.dataset.effectDirection as EffectDirection | undefined;
    if (effectDirection) { const next = { ...state, effectDirection, playhead: 0 }; const animation = animationFor(next); if (animation) mutate(selectionForAnimation(next, animation)); return; }
    const layerButton = target.closest<HTMLElement>('[data-select-layer]');
    if (layerButton) { mutate({ ...state, selectedLayerId: layerButton.dataset.selectLayer, selectedBlockIndex: undefined, inspectorTab: 'layer' }); return; }
    const blockButton = target.closest<HTMLElement>('[data-select-block]');
    if (blockButton) {
      const layerId = blockButton.dataset.layerId!;
      const blockIndex = Number(blockButton.dataset.blockIndex);
      const block = animationFor(state)?.layers.find((layer) => layer.layerId === layerId)?.blocks[blockIndex];
      mutate({ ...state, selectedLayerId: layerId, selectedBlockIndex: blockIndex, playhead: block?.from ?? state.playhead, inspectorTab: 'layer' }); return;
    }
    const ruler = target.closest<HTMLElement>('[data-layered-playhead-frame]');
    if (ruler) { mutate({ ...state, playhead: Number(ruler.dataset.layeredPlayheadFrame) }); return; }
    const hold = target.closest<HTMLElement>('[data-block-hold-delta]');
    if (hold) { mutateAnimation((document) => document.adjustBlockHold(hold.dataset.layerId!, Number(hold.dataset.blockIndex), Number(hold.dataset.blockHoldDelta))); return; }
    const deleteBlock = target.closest<HTMLElement>('[data-delete-block]');
    if (deleteBlock) { mutateAnimation((document) => document.deleteBlock(deleteBlock.dataset.layerId!, Number(deleteBlock.dataset.blockIndex))); return; }
    const pickerFrame = target.closest<HTMLElement>('[data-picker-frame]');
    if (pickerFrame) { const frame = Number(pickerFrame.dataset.pickerFrame); mutate({ ...state, pickerFrames: state.pickerFrames.includes(frame) ? state.pickerFrames.filter((value) => value !== frame) : [...state.pickerFrames, frame] }); return; }
    const hitboxSelect = target.closest<HTMLElement>('[data-select-hitbox]');
    if (hitboxSelect) { mutate({ ...state, selectedHitboxId: hitboxSelect.dataset.selectHitbox, inspectorTab: 'combat' }); return; }
    const hitboxCell = target.closest<HTMLElement>('[data-toggle-hitbox-frame]');
    if (hitboxCell) { updateAttack((attack) => ({ ...attack, attackTrack: toggleSpan(attack.attackTrack ?? { hitboxSpans: [], events: [] }, hitboxCell.dataset.hitboxId!, Number(hitboxCell.dataset.toggleHitboxFrame)) })); return; }
    const action = target.closest<HTMLElement>('[data-action]')?.dataset.action;
    if (!action) return;
    if (action === 'add-layer') {
      const animation = animationFor(state); const fallbackAsset = spritesheetAssets(state.assets)[0]?.assetId;
      if (!animation || !fallbackAsset) return;
      let index = animation.layers.length + 1; while (animation.layers.some((layer) => layer.layerId === `layer-${index}`)) index += 1;
      mutateAnimation((document) => document.addLayer({ layerId: `layer-${index}`, displayName: `Layer ${index}`, assetId: fallbackAsset, depthOffset: index - 1, blocks: [] })); return;
    }
    if (action === 'add-layer-tiles') { mutate({ ...state, pickerOpen: true, pickerFrames: [] }); return; }
    if (action === 'close-picker') { mutate({ ...state, pickerOpen: false, pickerFrames: [] }); return; }
    if (action === 'confirm-picker') { const frames = [...state.pickerFrames]; state = { ...state, pickerOpen: false, pickerFrames: [] }; mutateAnimation((document) => Boolean(state.selectedLayerId && document.insertTiles(state.selectedLayerId, frames, state.playhead))); return; }
    if (action === 'delete-layer' && state.selectedLayerId) { mutateAnimation((document) => document.deleteLayer(state.selectedLayerId!)); return; }
    if (action === 'layer-up' && state.selectedLayerId) { mutateAnimation((document) => document.moveLayer(state.selectedLayerId!, 1)); return; }
    if (action === 'layer-down' && state.selectedLayerId) { mutateAnimation((document) => document.moveLayer(state.selectedLayerId!, -1)); return; }
    if (action === 'add-hitbox') {
      updateAttack((attack) => { let index = 2; while (attack.hitboxes[`hitbox-${index}`]) index += 1; const id = `hitbox-${index}`; state = { ...state, selectedHitboxId: id }; return { ...attack, hitboxes: { ...attack.hitboxes, [id]: { shape: 'rectangle', width: 32, height: 24, offsetX: 24, offsetY: 0 } } }; }); return;
    }
    if (action === 'delete-hitbox') {
      const id = target.closest<HTMLElement>('[data-hitbox-id]')?.dataset.hitboxId; if (!id) return;
      updateAttack((attack) => { const hitboxes = { ...attack.hitboxes }; delete hitboxes[id]; return { ...attack, hitboxes, attackTrack: { ...(attack.attackTrack ?? { events: [] }), hitboxSpans: (attack.attackTrack?.hitboxSpans ?? []).filter((span) => span.hitboxId !== id) } }; }); return;
    }
    if (action === 'create-effect-from-current') {
      const animation = animationFor({ ...state, scope: state.scope === 'effect' ? 'attack' : state.scope }) ?? animationFor({ ...state, scope: 'attack' });
      if (!state.draft || !animation) return;
      const effectId = `${state.draft.weaponId}-impact`;
      const effect: EffectDefinition = { version: 1, effectId, displayName: `${state.draft.displayName} impact`, mirrorLeftFromRight: true, directions: { right: { ...clone(animation), loop: false }, up: { ...clone(animation), loop: false }, down: { ...clone(animation), loop: false } } };
      mutate({ ...state, draft: { ...state.draft, onHitEffectId: effectId }, effectDraft: effect, effectRevision: undefined, effectIsNew: true, effectDirty: true, dirty: true, scope: 'effect', effectDirection: 'right', playhead: 0 }); return;
    }
    if (action === 'new-weapon') {
      const assetId = spritesheetAssets(state.assets).find((asset) => asset.tags.includes('weapon'))?.assetId ?? spritesheetAssets(state.assets)[0]?.assetId ?? '';
      const draft = createWeaponDraft(assetId); mutate(selectionForAnimation({ ...state, selectedId: '', draft, revision: undefined, effectDraft: undefined, effectRevision: undefined, effectIsNew: false, effectDirty: false, dirty: true, scope: 'attack', direction: 'right', playhead: 0, notice: undefined }, draft.directionalAttacks.right.animation)); return;
    }
    if (action === 'play-preview') {
      if (state.playing) { stopPlayback(); render(); return; }
      const animation = animationFor(state); if (!animation) return;
      const frames = layeredTimelineFrameCount(animation); state = { ...state, playing: true, playhead: 0 }; render();
      playbackTimer = window.setInterval(() => { const current = animationFor(state); if (!current) return; const next = state.playhead + 1; if (next >= frames) { stopPlayback(); state = { ...state, playhead: current.loop ? 0 : frames - 1 }; render(); return; } state = { ...state, playhead: next }; render(); }, 1000 / animation.framesPerSecond); return;
    }
    if (action === 'save') {
      state = { ...state, saving: true, notice: undefined }; render();
      void savePackage(state).then((saved) => { state = { ...state, ...saved, saving: false }; render(); }).catch((error: unknown) => { state = { ...state, saving: false, notice: error instanceof Error ? error.message : String(error) }; render(); });
    }
  };

  const handleChange = (event: Event): void => {
    const target = event.target;
    if (!(target instanceof HTMLInputElement || target instanceof HTMLSelectElement)) return;
    const field = target.dataset.weaponField;
    if (field) {
      if (field === 'onHitEffectId') {
        const effect = state.effects.find((candidate) => candidate.effectId === target.value);
        mutate({ ...state, draft: state.draft ? { ...state.draft, ...(target.value ? { onHitEffectId: target.value } : { onHitEffectId: undefined }) } : undefined, effectDraft: effect ? clone(stripEffectRevision(effect)) : undefined, effectRevision: effect?.revision, effectIsNew: false, effectDirty: false, dirty: true });
      } else mutate(updateWeaponField(state, field, target.value));
      return;
    }
    const layerField = target.dataset.layerField;
    if (layerField === 'assetId') { mutate(withLayer(state, (layer) => ({ ...layer, assetId: target.value }))); return; }
    const hitboxField = target.dataset.hitboxField;
    if (hitboxField === 'shape') { mutate(updateWeaponField(state, `hitbox:${target.dataset.hitboxId}:shape`, target.value)); return; }
    const animationField = target.dataset.animationField;
    if (animationField) {
      const value = Number(target.value);
      mutateAnimation((document) => animationField === 'fps' ? document.setFramesPerSecond(value) : document.setDurationSeconds(value));
    }
  };

  const handlePointerDown = (event: PointerEvent): void => {
    const handle = event.target instanceof Element ? event.target.closest<HTMLElement>('[data-layer-resize-handle]') : undefined;
    if (!handle || event.button !== 0) return;
    const animation = animationFor(state); const lane = handle.closest<HTMLElement>('.layered-timeline-blocks');
    if (!animation || !lane) return;
    const layerId = handle.dataset.layerId!; const blockIndex = Number(handle.dataset.blockIndex);
    const block = animation.layers.find((layer) => layer.layerId === layerId)?.blocks[blockIndex];
    if (!block) return;
    event.preventDefault(); event.stopPropagation();
    resize = { pointerId: event.pointerId, layerId, blockIndex, originalThrough: block.through, startX: event.clientX, frameWidth: lane.getBoundingClientRect().width / layeredTimelineFrameCount(animation) };
    handle.setPointerCapture(event.pointerId);
  };
  const handlePointerUp = (event: PointerEvent): void => {
    if (!resize || resize.pointerId !== event.pointerId) return;
    event.preventDefault();
    const delta = Math.round((event.clientX - resize.startX) / resize.frameWidth);
    const current = resize; resize = undefined;
    if (delta !== 0) mutateAnimation((document) => document.resizeBlock(current.layerId, current.blockIndex, current.originalThrough + delta));
  };

  container.addEventListener('click', handleClick);
  container.addEventListener('change', handleChange);
  container.addEventListener('pointerdown', handlePointerDown);
  container.addEventListener('pointerup', handlePointerUp);
  render();
  void Promise.all([
    loadJson<WeaponCatalogResponse>('/__character-studio/weapons'),
    loadJson<EffectCatalogResponse>('/__character-studio/effects'),
    loadJson<CharacterStudioAssetCatalog>('/__character-studio/assets'),
  ]).then(([weaponCatalog, effectCatalog, assets]) => {
    state = { ...state, weapons: weaponCatalog.weapons, effects: effectCatalog.effects, assets };
    const selected = weaponCatalog.weapons[0];
    if (selected) selectCatalogWeapon(selected); else { state = { ...state, notice: 'No weapon packages found.' }; render(); }
  }).catch((error: unknown) => { state = { ...state, notice: error instanceof Error ? error.message : String(error) }; render(); });

  return () => {
    stopPlayback();
    container.removeEventListener('click', handleClick);
    container.removeEventListener('change', handleChange);
    container.removeEventListener('pointerdown', handlePointerDown);
    container.removeEventListener('pointerup', handlePointerUp);
    container.classList.remove('is-character-studio-host');
    container.replaceChildren();
  };
}
