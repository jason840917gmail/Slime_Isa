import './character-studio.css';

import { characterPackages } from 'virtual-character-content';
import type { CharacterStudioAssetCatalog, CharacterStudioAssetEntry } from '../content/characters/characterAssetCatalog';
import type { EffectDefinition, EffectDirection } from '../content/effects/types';
import { resolveEffectVariant } from '../content/effects/normalize';
import { validateEffectDefinition } from '../content/effects/validation';
import { getAnimationPackage } from '../content/animations/AnimationCatalog';
import type { AnimationPackageCatalog, AnimationPackageCatalogEntry } from '../content/animations/types';
import { migrateLegacyAnimation, migrateLegacyWeaponDefinition } from '../content/weapons/migrateLegacyWeapon';
import { resolveWeaponPresentationOffsetY } from '../content/weapons/presentation';
import { weaponIconSelection } from '../content/weapons/WeaponIcon';
import {
  isProceduralWeaponIconKey,
  proceduralWeaponIconChoices,
  validateWeaponIconAgainstCatalog,
  weaponIconCatalogFromStudio,
} from '../content/weapons/WeaponIconCatalog';
import type {
  AuthoredWeaponDefinition,
  LayeredWeaponDefinition,
  LayeredWeaponDirectionalAttackDocument,
  LegacyWeaponDefinition,
  WeaponAttackDirection,
  WeaponAttackTrackDocument,
} from '../content/weapons/types';
import { validateWeaponDefinitionForStudioSave } from '../content/weapons/validation';
import { resolveAssetUrl, tryResolveAssetUrl } from '../infrastructure/assets/assetUrls';
import {
  DOWN_UP_INHERITANCE,
  layeredAnimationFrameAtStep,
  layeredTimelineFrameCount,
  materializeDirectionalAnimation,
  normalizeAnimationBlockTransform,
  resolveDirectionalVariant,
  RIGHT_LEFT_INHERITANCE,
  type AnimationVisualLayerDocument,
  type LayeredAnimationDocument,
} from '../shared/animation';
import { LayeredAnimationDocumentState } from './LayeredAnimationDocumentState';
import { renderLayeredAnimationBlockInspector } from './LayeredAnimationBlockInspector';
import {
  renderLayeredAnimationPreviewPanel,
  syncLayeredAnimationPreviewPlaybackButton,
  updateLayeredAnimationPreviewPlayback,
} from './LayeredAnimationPreviewPanel';
import { renderLayeredAnimationTimelinePanel } from './LayeredAnimationTimelinePanel';
import { renderLayeredWeaponHitboxControls, updateWeaponHitboxControl } from './LayeredWeaponHitboxControls';
import {
  createLayeredAnimationTimelineView,
  renderLayeredBlockHoldControls,
  renderLayeredBlockResizeHandle,
} from './LayeredAnimationTimelineView';
import { ensureStudioModeTabs } from './StudioModeTabs';
import { renderStudioLibraryTree } from './StudioLibraryTree';
import { renderWeaponHitboxGuides } from './WeaponHitboxGuides';
import { resolveDirectionalStudioState } from './DirectionalInheritanceState';
import { directionalStatusLabel } from './DirectionalInheritanceView';
import { adjustPreviewZoom } from './PreviewZoom';
import { handleStudioHistoryShortcut } from './StudioHistoryShortcut';
import {
  applyWeaponStudioHistory,
  commitWeaponStudioMutation,
  reduceWeaponIconAction,
  WEAPON_STUDIO_INSPECTOR_TABS,
  type WeaponStudioAnimationScope,
  type WeaponStudioHistory,
  type WeaponStudioInspectorTab,
} from './LayeredWeaponStudioMutation';
import { reduceWeaponTargetingAction, renderWeaponTargetingInspector } from './WeaponTargetingEditor';

const DIRECTIONS = ['right', 'left', 'up', 'down'] as const satisfies readonly WeaponAttackDirection[];
const EFFECT_DIRECTIONS = DIRECTIONS satisfies readonly EffectDirection[];
const WEAPON_DIRECTIONAL_PAIRS = [RIGHT_LEFT_INHERITANCE, DOWN_UP_INHERITANCE] as const;

type AnimationScope = WeaponStudioAnimationScope;
type InspectorTab = WeaponStudioInspectorTab;

type CatalogWeapon = AuthoredWeaponDefinition & { readonly revision: string };
type CatalogEffect = EffectDefinition & { readonly revision: string };
interface WeaponCatalogResponse { readonly weapons: readonly CatalogWeapon[] }
interface EffectCatalogResponse { readonly effects: readonly CatalogEffect[] }

interface StudioState {
  readonly assets?: CharacterStudioAssetCatalog;
  readonly weapons: readonly CatalogWeapon[];
  readonly effects: readonly CatalogEffect[];
  readonly animationPackages: readonly AnimationPackageCatalogEntry[];
  readonly librarySearch: string;
  readonly sourceSheetSearch: string;
  readonly expandedFolders: ReadonlySet<string>;
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
  readonly previewZoom: number;
  readonly previewSplit: number;
  readonly inspectorTab: InspectorTab;
  readonly pickerOpen: boolean;
  readonly pickerFrames: readonly number[];
  readonly iconPickerOpen: boolean;
  readonly iconPickerAssetId?: string;
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

function clone<T>(value: T): T { return structuredClone(value); }

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;',
  })[character] ?? character);
}

function assetInfo(asset: CharacterStudioAssetEntry | undefined) {
  if (asset && !tryResolveAssetUrl(asset.sourcePath)) {
    return { url: resolveAssetUrl(asset.sourcePath), width: 128, height: 128, columns: 1, rows: 1, count: 1 };
  }
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

function sourceSheetMatches(asset: CharacterStudioAssetEntry, query: string): boolean {
  const normalizedQuery = query.trim().toLocaleLowerCase();
  if (!normalizedQuery) return true;
  return [asset.assetId, asset.sourcePath, asset.textureKey, ...asset.tags]
    .some((value) => value.toLocaleLowerCase().includes(normalizedQuery));
}

function animationFor(state: StudioState): LayeredAnimationDocument | undefined {
  const weapon = state.draft;
  if (!weapon) return undefined;
  if (state.scope === 'idle') return weapon.animations.idle;
  if (state.scope === 'attack') {
    return resolveWeaponAttack(weapon, state.direction)?.attack.animation;
  }
  if (!state.effectDraft) return undefined;
  return resolveEffectVariant(state.effectDraft, state.effectDirection)?.animation;
}

function resolveWeaponAttack(
  weapon: LayeredWeaponDefinition,
  direction: WeaponAttackDirection,
) {
  const resolved = resolveDirectionalStudioState(
    weapon.directionalAttacks,
    direction,
    { pairs: WEAPON_DIRECTIONAL_PAIRS },
  );
  if (!resolved || resolved.sourceDirection === 'default') return undefined;
  return { ...resolved, attack: resolved.value as LayeredWeaponDirectionalAttackDocument };
}

function resolveEffectDocumentVariant(effect: EffectDefinition, direction: EffectDirection) {
  return resolveDirectionalVariant(
    effect.directions ?? {},
    direction,
    {
      pairs: [
        { ...RIGHT_LEFT_INHERITANCE, enabled: effect.mirrorLeftFromRight === true },
        { ...DOWN_UP_INHERITANCE, enabled: effect.mirrorUpFromDown === true },
      ],
      defaultValue: effect.default,
    },
  );
}

function reconcileWeaponAttackTrack(
  track: WeaponAttackTrackDocument,
  previousAnimation: LayeredAnimationDocument,
  nextAnimation: LayeredAnimationDocument,
): WeaponAttackTrackDocument {
  const frameCount = layeredTimelineFrameCount(nextAnimation);
  const fpsChanged = previousAnimation.framesPerSecond !== nextAnimation.framesPerSecond;
  const projectFrom = (frame: number): number => fpsChanged
    ? Math.round(frame / previousAnimation.framesPerSecond * nextAnimation.framesPerSecond)
    : frame;
  const projectThrough = (frame: number): number => fpsChanged
    ? Math.round((frame + 1) / previousAnimation.framesPerSecond * nextAnimation.framesPerSecond) - 1
    : frame;

  const spans = track.hitboxSpans
    .flatMap((span) => {
      const from = projectFrom(span.from);
      const through = Math.min(projectThrough(span.through), frameCount - 1);
      return from >= 0 && from < frameCount && through >= from ? [{ ...span, from, through }] : [];
    })
    .sort((left, right) => left.from - right.from || left.through - right.through || left.hitboxId.localeCompare(right.hitboxId));
  const mergedSpans: Array<{ readonly hitboxId: string; readonly from: number; readonly through: number }> = [];
  for (const span of spans) {
    const previous = mergedSpans[mergedSpans.length - 1];
    if (previous && previous.hitboxId === span.hitboxId && previous.through + 1 >= span.from) {
      mergedSpans[mergedSpans.length - 1] = { ...previous, through: Math.max(previous.through, span.through) };
    } else {
      mergedSpans.push(span);
    }
  }

  const events = track.events?.flatMap((event) => {
    const at = projectFrom(event.at);
    return at >= 0 && at < frameCount ? [{ ...event, at }] : [];
  });
  return {
    ...track,
    hitboxSpans: mergedSpans,
    ...(track.events ? { events } : {}),
  };
}

function replaceAnimation(state: StudioState, animation: LayeredAnimationDocument): StudioState {
  if (!state.draft) return state;
  if (state.scope === 'idle') {
    return { ...state, draft: { ...state.draft, animations: { ...state.draft.animations, idle: animation } }, dirty: true };
  }
  if (state.scope === 'attack') {
    const resolved = resolveWeaponAttack(state.draft, state.direction);
    if (!resolved?.authored) return { ...state, notice: `${state.direction.toUpperCase()} is inherited. Make it custom before editing.` };
    const attack = state.draft.directionalAttacks[state.direction];
    if (!attack) return state;
    const previousAnimation = animationFor(state);
    const attackTrack = attack.attackTrack && previousAnimation
      ? reconcileWeaponAttackTrack(attack.attackTrack, previousAnimation, animation)
      : attack.attackTrack;
    return {
      ...state,
      draft: {
        ...state.draft,
        directionalAttacks: {
          ...state.draft.directionalAttacks,
          [state.direction]: { ...attack, animation, ...(attackTrack ? { attackTrack } : {}) },
        },
      },
      dirty: true,
    };
  }
  if (!state.effectDraft) return state;
  const resolved = resolveEffectDocumentVariant(state.effectDraft, state.effectDirection);
  if (!resolved?.authored) return { ...state, notice: `${state.effectDirection.toUpperCase()} is inherited. Make it custom before editing.` };
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
  failureNotice = 'That edit could not be applied inside the animation duration.',
): StudioState {
  const animation = animationFor(state);
  if (!animation) return state;
  const document = new LayeredAnimationDocumentState(animation);
  if (state.selectedLayerId) document.selectLayer(state.selectedLayerId);
  if (state.selectedLayerId && state.selectedBlockIndex !== undefined) document.selectBlock(state.selectedLayerId, state.selectedBlockIndex);
  document.setPlayhead(state.playhead);
  if (!operation(document)) return { ...state, notice: failureNotice };
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
      draft: hydrateSharedWeaponAnimations(source),
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

export interface LayeredWeaponStudioOptions {
  readonly initialWeaponId?: string;
  readonly onSelectWeapon?: (weaponId: string) => void;
  readonly onSelectAnimation?: (animationId: string) => void;
  readonly expandedFolders?: ReadonlySet<string>;
  readonly onExpandedFoldersChange?: (expandedFolders: ReadonlySet<string>) => void;
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

function timelineAnimation(timeline: {
  readonly durationSeconds: number;
  readonly framesPerSecond: number;
  readonly loop: boolean;
  readonly loopMode?: 'wrap' | 'ping-pong';
}): LayeredAnimationDocument {
  return {
    version: 2,
    durationSeconds: timeline.durationSeconds,
    framesPerSecond: timeline.framesPerSecond,
    loop: timeline.loop,
    loopMode: timeline.loopMode ?? 'wrap',
    layers: [],
  };
}

function hydrateSharedAnimation(
  animationId: string | undefined,
  timeline: {
    readonly durationSeconds: number;
    readonly framesPerSecond: number;
    readonly loop: boolean;
    readonly loopMode?: 'wrap' | 'ping-pong';
  } | undefined,
  embedded: LayeredAnimationDocument | undefined,
  loop: boolean,
): LayeredAnimationDocument {
  const shared = animationId ? getAnimationPackage(animationId)?.animation : undefined;
  return shared ? clone(shared) : timeline ? timelineAnimation(timeline) : embedded ? clone(embedded) : timelineAnimation({ durationSeconds: 1 / 12, framesPerSecond: 12, loop });
}

function hydrateSharedWeaponAnimations(source: LayeredWeaponDefinition): LayeredWeaponDefinition {
  const animations = source.animations as LayeredWeaponDefinition['animations'] & {
    readonly idle?: LayeredAnimationDocument;
  };
  const idle = hydrateSharedAnimation(
    animations.idleAnimationId,
    animations.idleTimeline,
    animations.idle,
    true,
  );
  const directionalAttacks = Object.fromEntries(
    Object.entries(source.directionalAttacks).map(([direction, attack]) => [direction, {
      ...attack,
      animation: hydrateSharedAnimation(
        attack.animationId,
        attack.animationTimeline,
        attack.animation,
        false,
      ),
    }]),
  ) as LayeredWeaponDefinition['directionalAttacks'];
  return {
    ...clone(source),
    animations: { ...source.animations, idle },
    directionalAttacks,
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
    directionalAttacks: { right: attack(), down: attack() },
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
    iconKey: '',
    iconFrame: 0,
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

function previewPlayerCharacter() {
  return characterPackages.find((entry) => entry.characterId === 'player-slime') ?? characterPackages[0];
}

function availableCharacterActions(): readonly string[] {
  const character = previewPlayerCharacter();
  if (!character) return [];
  return Object.entries(character.visualSet.clips)
    .filter(([, clip]) => clip.frames.length > 0)
    .map(([actionId]) => actionId)
    .sort((left, right) => left.localeCompare(right));
}

function characterSprite(state: StudioState): string {
  const character = previewPlayerCharacter();
  const asset = state.assets?.assets.find((entry) => entry.assetId === character?.visualSet.assetId);
  const resolvedAttack = state.scope === 'attack' && state.draft
    ? resolveWeaponAttack(state.draft, state.direction)
    : undefined;
  const actionId = state.scope === 'attack'
    ? resolvedAttack?.attack.characterActionId ?? state.draft?.characterActionId
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

function previewMirrorAxes(state: StudioState): { readonly mirrorX: boolean; readonly mirrorY: boolean } {
  if (state.scope === 'attack' && state.draft) {
    const resolved = resolveWeaponAttack(state.draft, state.direction);
    return { mirrorX: resolved?.mirrorX ?? false, mirrorY: resolved?.mirrorY ?? false };
  }
  if (state.scope === 'effect' && state.effectDraft) {
    const resolved = resolveEffectVariant(state.effectDraft, state.effectDirection);
    return { mirrorX: resolved?.mirrorX ?? false, mirrorY: resolved?.mirrorY ?? false };
  }
  return { mirrorX: false, mirrorY: false };
}

function layerPreviewSprite(
  state: StudioState,
  layer: AnimationVisualLayerDocument,
  block: AnimationVisualLayerDocument['blocks'][number],
  layerIndex: number,
  mirror: { readonly mirrorX: boolean; readonly mirrorY: boolean },
  presentationOffsetY: number,
): string {
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
  const authoredOffset = [
    (transform.offset?.[0] ?? 0) + (blockTransform.offset?.[0] ?? 0),
    (transform.offset?.[1] ?? 0) + (blockTransform.offset?.[1] ?? 0),
  ] as const;
  const offset = [
    mirror.mirrorX ? -authoredOffset[0] : authoredOffset[0],
    (mirror.mirrorY ? -authoredOffset[1] : authoredOffset[1]) + presentationOffsetY,
  ] as const;
  const column = block.sourceFrame % info.columns;
  const row = Math.floor(block.sourceFrame / info.columns);
  const flipX = Boolean(mirror.mirrorX) !== Boolean(blockTransform.flipX) !== Boolean(transform.flipX);
  const flipY = Boolean(mirror.mirrorY) !== Boolean(blockTransform.flipY) !== Boolean(transform.flipY);
  const rotation = (mirror.mirrorX !== mirror.mirrorY ? -1 : 1) * ((transform.rotationDeg ?? 0) + (blockTransform.rotationDeg ?? 0));
  return `<span class="stage-sprite stage-weapon-sprite${layer.layerId === state.selectedLayerId ? ' is-selected-layer' : ''}" data-preview-layer="${escapeHtml(layer.layerId)}" style="z-index:${3 + layerIndex};--sheet-url:url('${escapeHtml(info.url)}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:${column * info.width}px;--frame-y:${row * info.height}px;--preview-scale-x:${scale[0]};--preview-scale-y:${scale[1]};--origin-offset-x:${-origin[0] * info.width * scale[0]}px;--origin-offset-y:${-origin[1] * info.height * scale[1]}px;--offset-x:${offset[0] * 2.8}px;--offset-y:${offset[1] * 2.8}px;--weapon-rotation:${rotation}deg;--weapon-flip-x:${flipX ? -1 : 1};--weapon-flip-y:${flipY ? -1 : 1}"></span>`;
}

function renderPreviewHitboxes(state: StudioState, presentationOffsetY: number): string {
  if (state.scope !== 'attack') return '';
  const attack = selectedAttack(state);
  if (!attack) return '';
  return `<span class="weapon-hitbox-guides" data-weapon-hitbox-guides>${renderWeaponHitboxGuides({
    hitboxes: attack.hitboxes,
    track: attack.attackTrack,
    direction: state.direction,
    timelineFrame: state.playhead,
    selectedHitboxId: state.selectedHitboxId,
    presentationOffsetY,
  })}</span>`;
}

function weaponPresentationOffsetY(state: StudioState): number {
  if (state.scope !== 'attack' || !state.draft) return 0;
  const resolved = resolveWeaponAttack(state.draft, state.direction);
  return resolveWeaponPresentationOffsetY(resolved?.mirrorY ?? false);
}

function renderPreview(state: StudioState, animation: LayeredAnimationDocument): string {
  const duration = animation.durationSeconds;
  const activeLayers = resolvedLayerAt(animation, state.playhead);
  const effectOnly = state.scope === 'effect';
  const mirror = previewMirrorAxes(state);
  const presentationOffsetY = weaponPresentationOffsetY(state);
  return renderLayeredAnimationPreviewPanel({
    kicker: 'COMBINED PREVIEW',
    summaryHtml: `${state.scope.toUpperCase()}${state.scope === 'idle' ? '' : ` / ${(state.scope === 'effect' ? state.effectDirection : state.direction).toUpperCase()}`} · ${Number(state.playhead / animation.framesPerSecond).toFixed(2)}s / ${duration.toFixed(2)}s · ${activeLayers.length} active layer${activeLayers.length === 1 ? '' : 's'}`,
    previewZoom: state.previewZoom,
    playing: state.playing,
    sceneHtml: `<span class="stage-axis stage-axis-x"></span><span class="stage-axis stage-axis-y"></span><span class="stage-anchor">+</span><span class="stage-label">${effectOnly ? 'ENEMY CONTACT' : 'PLAYER ANCHOR'}</span>${effectOnly ? '' : characterSprite(state)}${activeLayers.map(({ layer, layerIndex, block }) => layerPreviewSprite(state, layer, block, layerIndex, mirror, presentationOffsetY)).join('')}${renderPreviewHitboxes(state, presentationOffsetY)}<span class="stage-caption"><b>${escapeHtml(state.scope === 'effect' ? state.effectDraft?.displayName : state.draft?.displayName)}</b><span>${activeLayers.map(({ layer, block }) => `${escapeHtml(layer.displayName)} · TILE ${block.sourceFrame}`).join('  / ') || 'NO VISUAL AT PLAYHEAD'}</span></span>`,
    footerHtml: '<span><i class="legend-dot legend-dot--cyan"></i> shared clock</span><span><i class="legend-dot legend-dot--amber"></i> selected visual layer</span><span><i class="legend-dot legend-dot--red"></i> hitbox active window</span><span>Wheel over preview to zoom · Effects spawn only after confirmed damage.</span>',
  });
}

function selectedAttack(state: StudioState) {
  if (!state.draft) return undefined;
  return resolveWeaponAttack(state.draft, state.direction)?.attack;
}

function renderDirectionalCommand(state: StudioState): string {
  if (state.scope === 'idle') return '';
  const direction = state.scope === 'attack' ? state.direction : state.effectDirection;
  const pairs = state.scope === 'attack'
    ? WEAPON_DIRECTIONAL_PAIRS
    : [
        { ...RIGHT_LEFT_INHERITANCE, enabled: state.effectDraft?.mirrorLeftFromRight === true },
        { ...DOWN_UP_INHERITANCE, enabled: state.effectDraft?.mirrorUpFromDown === true },
      ];
  const resolved = state.scope === 'attack' && state.draft
    ? resolveWeaponAttack(state.draft, direction)
    : state.scope === 'effect' && state.effectDraft
      ? resolveEffectDocumentVariant(state.effectDraft, direction)
      : undefined;
  const pair = pairs.find((candidate) => candidate.child === direction);
  const scopeAttribute = 'data-mirror-direction';
  const action = pair && pair.enabled && resolved && !resolved.authored
    ? `<button type="button" class="studio-button studio-button--accent" data-action="make-custom-direction" ${scopeAttribute}="${direction}">MAKE CUSTOM ${direction.toUpperCase()}</button>`
    : pair && pair.enabled && resolved?.authored
      ? `<button type="button" class="studio-button studio-button--quiet" data-action="restore-direction-mirror" ${scopeAttribute}="${direction}">RESTORE ${pair.master.toUpperCase()} MIRROR</button>`
      : '';
  return action ? `<div class="layered-direction-command">${action}</div>` : '';
}

function makeCustomWeaponDirection(
  weapon: LayeredWeaponDefinition,
  direction: WeaponAttackDirection,
): LayeredWeaponDefinition | undefined {
  if (direction !== 'left' && direction !== 'up') return undefined;
  const resolved = resolveWeaponAttack(weapon, direction);
  if (!resolved || resolved.authored) return undefined;
  const attack = clone(resolved.attack);
  return {
    ...weapon,
    directionalAttacks: {
      ...weapon.directionalAttacks,
      [direction]: {
        ...attack,
        animation: materializeDirectionalAnimation(attack.animation, {
          mirrorX: resolved.mirrorX,
          mirrorY: resolved.mirrorY,
        }),
      },
    },
  };
}

function makeCustomEffectDirection(effect: EffectDefinition, direction: EffectDirection): EffectDefinition | undefined {
  if (direction !== 'left' && direction !== 'up') return undefined;
  const resolved = resolveEffectDocumentVariant(effect, direction);
  if (!resolved || resolved.authored) return undefined;
  return {
    ...effect,
    directions: {
      ...(effect.directions ?? {}),
      [direction]: materializeDirectionalAnimation(resolved.value, {
        mirrorX: resolved.mirrorX,
        mirrorY: resolved.mirrorY,
      }),
    },
  };
}

function restoreWeaponDirection(weapon: LayeredWeaponDefinition, direction: WeaponAttackDirection): LayeredWeaponDefinition {
  if (direction !== 'left' && direction !== 'up') return weapon;
  const directionalAttacks = { ...weapon.directionalAttacks };
  delete directionalAttacks[direction];
  return { ...weapon, directionalAttacks };
}

function restoreEffectDirection(effect: EffectDefinition, direction: EffectDirection): EffectDefinition {
  if (direction !== 'left' && direction !== 'up') return effect;
  const directions = { ...(effect.directions ?? {}) };
  delete directions[direction];
  return { ...effect, directions };
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
  const locked = state.draft ? !(resolveWeaponAttack(state.draft, state.direction)?.authored ?? false) : false;
  const frameCount = layeredTimelineFrameCount(animation);
  const track = attack.attackTrack ?? { hitboxSpans: [], events: [] };
  return Object.keys(attack.hitboxes).map((hitboxId) => `<div class="timeline-track-row layered-host-row"><button type="button" class="timeline-track-label layered-track-label${hitboxId === state.selectedHitboxId ? ' is-selected' : ''}" data-select-hitbox="${escapeHtml(hitboxId)}">${escapeHtml(hitboxId)}</button>${Array.from({ length: frameCount }, (_, frame) => `<button type="button" class="timeline-cell${track.hitboxSpans.some((span) => span.hitboxId === hitboxId && span.from <= frame && frame <= span.through) ? ' is-hot' : ''}" data-toggle-hitbox-frame="${frame}" data-hitbox-id="${escapeHtml(hitboxId)}" aria-label="Toggle ${escapeHtml(hitboxId)} at frame ${frame}"${locked ? ' disabled' : ''}></button>`).join('')}</div>`).join('');
}

function renderBlock(state: StudioState, animation: LayeredAnimationDocument, layerId: string, blockIndex: number): string {
  const layer = animation.layers.find((candidate) => candidate.layerId === layerId)!;
  const block = layer.blocks[blockIndex];
  const asset = state.assets?.assets.find((entry) => entry.assetId === layer.assetId);
  const hold = block.through - block.from + 1;
  const selected = layerId === state.selectedLayerId && blockIndex === state.selectedBlockIndex;
  const startSeconds = Number(block.from / animation.framesPerSecond).toFixed(2);
  return `<article class="timeline-frame layered-timeline-block${selected ? ' is-selected' : ''}" style="grid-column:${block.from + 1} / span ${hold}" data-layer-block data-layer-id="${escapeHtml(layerId)}" data-block-index="${blockIndex}"><button type="button" class="timeline-frame-select" data-select-block data-layer-id="${escapeHtml(layerId)}" data-block-index="${blockIndex}" aria-label="Select tile from source frame ${block.sourceFrame}, starting at ${startSeconds} seconds. Drag horizontally to change its start time." title="Drag horizontally to change start time">${frameSprite(asset, block.sourceFrame, 'timeline-tile-preview')}<b class="timeline-frame-number">${String(block.from).padStart(2, '0')}</b><small class="timeline-frame-source">SRC ${block.sourceFrame}</small><span class="timeline-frame-hold">${Number(hold / animation.framesPerSecond).toFixed(2)}s / ${hold}F</span></button>${renderLayeredBlockHoldControls(layerId, blockIndex, hold)}<button type="button" class="layered-block-delete" data-delete-block data-layer-id="${escapeHtml(layerId)}" data-block-index="${blockIndex}" aria-label="Delete block">×</button>${renderLayeredBlockResizeHandle(layerId, blockIndex, hold)}</article>`;
}

function renderTimeline(state: StudioState, animation: LayeredAnimationDocument): string {
  return renderLayeredAnimationTimelinePanel({
    titleHtml: `Editing ${escapeHtml(state.scope)}${state.scope === 'idle' ? '' : ` / ${escapeHtml(state.scope === 'effect' ? state.effectDirection : state.direction)}`}`,
    hint: 'Click time to place the playhead · drag tile to move · drag edge to resize',
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

function renderCharacterActionOptions(selectedAction: string): string {
  const actions = availableCharacterActions();
  const resolvedSelection = actions.includes(selectedAction) ? selectedAction : actions[0] ?? selectedAction;
  return actions.map((actionId) => `<option value="${escapeHtml(actionId)}" ${actionId === resolvedSelection ? 'selected' : ''}>${escapeHtml(actionId.replaceAll('-', ' '))}</option>`).join('')
    || `<option value="${escapeHtml(selectedAction)}" selected>${escapeHtml(selectedAction)}</option>`;
}

function renderDirectionalCharacterAction(state: StudioState): string {
  if (state.scope !== 'attack' || !state.draft) return '';
  const resolved = resolveWeaponAttack(state.draft, state.direction);
  if (!resolved) return '';
  const locked = !resolved.authored;
  const selectedAction = resolved.attack.characterActionId ?? state.draft.characterActionId;
  return `<label class="studio-field studio-field--wide weapon-direction-action layered-direction-action"><span>${state.direction.toUpperCase()} character action<small>${locked ? 'inherited from its master direction' : 'body clip paired with this weapon direction'}</small></span><select data-weapon-field="directionalAttacks.${state.direction}.characterActionId" aria-label="${state.direction} character action"${locked ? ' disabled' : ''}>${renderCharacterActionOptions(selectedAction)}</select></label>`;
}

function renderIdentityInspector(state: StudioState): string {
  const weapon = state.draft!;
  return `<section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Identity</span><strong>Reusable weapon package</strong></div><div class="studio-field-grid">${inputField('Stable ID', 'weaponId', weapon.weaponId, { hint: 'lowercase kebab-case' })}${inputField('Display name', 'displayName', weapon.displayName)}</div><label class="studio-field studio-field--wide"><span>Category<small>combat family</small></span><select data-weapon-field="category"><option value="melee" ${weapon.category === 'melee' ? 'selected' : ''}>Melee</option><option value="ranged" ${weapon.category === 'ranged' ? 'selected' : ''}>Ranged</option></select></label><label class="studio-field studio-field--wide"><span>Default character action<small>fallback when a direction has no override</small></span><select data-weapon-field="characterActionId" aria-label="Default character action">${renderCharacterActionOptions(weapon.characterActionId)}</select></label>${inputField('Description', 'description', weapon.description)}</section>`;
}

function renderCombatInspector(state: StudioState): string {
  const weapon = state.draft!;
  const attack = selectedAttack(state);
  const attackIsInherited = !(resolveWeaponAttack(state.draft!, state.direction)?.authored ?? false);
  const hitboxes = attack?.hitboxes ?? {};
  const selectedId = state.selectedHitboxId && hitboxes[state.selectedHitboxId] ? state.selectedHitboxId : Object.keys(hitboxes)[0];
  const hitbox = selectedId ? hitboxes[selectedId] : undefined;
  return `<section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Combat profile</span><strong>Damage and timing</strong></div><div class="studio-field-grid">${inputField('Base damage', 'baseDamage', weapon.baseDamage, { type: 'number', step: '1' })}${inputField('Cooldown', 'cooldownMs', weapon.cooldownMs, { type: 'number', step: '1', hint: 'milliseconds' })}${inputField('Knockback', 'knockStrength', weapon.knockStrength, { type: 'number', step: '1' })}${inputField('Unlock level', 'unlockLevel', weapon.unlockLevel, { type: 'number', step: '1' })}</div></section><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Directional collision</span><strong>${state.direction.toUpperCase()} hitboxes</strong><button type="button" class="studio-icon-button" data-action="add-hitbox" aria-label="Add hitbox"${attackIsInherited ? ' disabled' : ''}>+</button></div><p class="studio-help">Select a hitbox here or click its label in the preview. Geometry updates in the preview while you edit it; active time remains in the attack track.</p><div class="layered-hitbox-tabs">${Object.keys(hitboxes).map((id) => `<button type="button" class="studio-pill${id === selectedId ? ' is-active' : ''}" data-select-hitbox="${escapeHtml(id)}">${escapeHtml(id)}</button>`).join('')}</div>${hitbox && selectedId ? renderLayeredWeaponHitboxControls(selectedId, hitbox, attackIsInherited) : '<p class="studio-empty-note">Add a hitbox for this direction.</p>'}</section>`;
}

function renderLayerInspector(state: StudioState, animation: LayeredAnimationDocument): string {
  const layer = selectedLayer(state, animation);
  if (!layer) return `<section class="studio-inspector-section"><p class="studio-empty-note">Add a visual layer to start this animation.</p></section>`;
  const allSourceSheets = spritesheetAssets(state.assets);
  const matchingSourceSheets = allSourceSheets.filter((asset) => sourceSheetMatches(asset, state.sourceSheetSearch));
  const selectedSourceSheet = allSourceSheets.find((asset) => asset.assetId === layer.assetId);
  const visibleSourceSheets = selectedSourceSheet && !matchingSourceSheets.includes(selectedSourceSheet)
    ? [selectedSourceSheet, ...matchingSourceSheets]
    : matchingSourceSheets;
  const options = visibleSourceSheets.map((asset) => `<option value="${escapeHtml(asset.assetId)}" ${asset.assetId === layer.assetId ? 'selected' : ''} title="${escapeHtml(`${asset.sourcePath} · ${asset.tags.join(' / ')}`)}">${escapeHtml(asset.assetId)}</option>`).join('')
    || `<option value="${escapeHtml(layer.assetId)}" selected>${escapeHtml(layer.assetId)} (unavailable)</option>`;
  const matchSummary = state.sourceSheetSearch.trim()
    ? `${matchingSourceSheets.length} match${matchingSourceSheets.length === 1 ? '' : 'es'}${selectedSourceSheet && !matchingSourceSheets.includes(selectedSourceSheet) ? ' · current retained' : ''}`
    : `${allSourceSheets.length} sheets`;
  const transform = layer.transform ?? {};
  const block = state.selectedBlockIndex === undefined ? undefined : layer.blocks[state.selectedBlockIndex];
  const blockInspector = block ? renderLayeredAnimationBlockInspector({
    block,
    framesPerSecond: animation.framesPerSecond,
    timelineFrames: layeredTimelineFrameCount(animation),
  }) : `<p class="studio-empty-note layered-block-inspector-note">Select a tile to edit its timing and visual transform.</p>`;
  return `<section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Visual layer</span><strong>${escapeHtml(layer.displayName)}</strong></div>${inputField('Layer name', 'layer:displayName', layer.displayName)}<div class="layered-source-sheet-control"><label class="studio-field studio-field--wide layered-source-sheet-search"><span>Find source sheet<small role="status" aria-live="polite">${escapeHtml(matchSummary)}</small></span><span class="layered-source-sheet-search-box"><i aria-hidden="true">⌕</i><input type="search" value="${escapeHtml(state.sourceSheetSearch)}" placeholder="Search ID, path, or tag" autocomplete="off" spellcheck="false" data-source-sheet-search /></span></label><label class="studio-field studio-field--wide"><span>Source sheet<small>one source per layer</small></span><select id="layer-source-sheet-select" data-layer-field="assetId">${options}</select></label></div><div class="studio-field-grid">${inputField('Depth', 'layer:depthOffset', layer.depthOffset, { type: 'number', step: '0.1' })}${inputField('Layer offset X', 'layer:offsetX', transform.offset?.[0] ?? 0, { type: 'number', step: '0.1' })}${inputField('Layer offset Y', 'layer:offsetY', transform.offset?.[1] ?? 0, { type: 'number', step: '0.1' })}${inputField('Layer scale X', 'layer:scaleX', transform.scale?.[0] ?? 1, { type: 'number', step: '0.01' })}${inputField('Layer scale Y', 'layer:scaleY', transform.scale?.[1] ?? 1, { type: 'number', step: '0.01' })}${inputField('Layer rotation', 'layer:rotationDeg', transform.rotationDeg ?? 0, { type: 'number', step: '1', hint: 'degrees' })}</div>${blockInspector}<div class="layered-layer-actions"><button type="button" class="studio-button studio-button--quiet" data-action="layer-up">↑ FRONT</button><button type="button" class="studio-button studio-button--quiet" data-action="layer-down">↓ BACK</button><button type="button" class="studio-button studio-button--danger" data-action="delete-layer">DELETE LAYER</button></div></section>`;
}

function renderOnHitInspector(state: StudioState): string {
  const effectId = state.draft?.onHitEffectId ?? '';
  return `<section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Confirmed contact</span><strong>On-hit effect</strong></div><p class="studio-help">This effect spawns at the enemy contact edge only after positive damage is accepted.</p><label class="studio-field studio-field--wide"><span>Effect package<small>reusable library asset</small></span><select data-weapon-field="onHitEffectId"><option value="">No effect</option>${state.effects.map((effect) => `<option value="${escapeHtml(effect.effectId)}" ${effect.effectId === effectId ? 'selected' : ''}>${escapeHtml(effect.displayName)}</option>`).join('')}${state.effectDraft && !state.effects.some((effect) => effect.effectId === state.effectDraft?.effectId) ? `<option value="${escapeHtml(state.effectDraft.effectId)}" selected>${escapeHtml(state.effectDraft.displayName)} (new)</option>` : ''}</select></label><button type="button" class="studio-button studio-button--accent" data-action="create-effect-from-current">CREATE EFFECT FROM CURRENT ART</button>${state.effectDraft ? `<div class="studio-callout"><strong>${escapeHtml(state.effectDraft.displayName)}</strong><span>${escapeHtml(state.effectDraft.effectId)} · directional variants share this editor</span></div>` : ''}</section>`;
}

function renderInspector(state: StudioState, animation: LayeredAnimationDocument): string {
  return `<aside class="studio-inspector layered-weapon-inspector"><div class="studio-inspector-heading"><span class="studio-kicker">Inspector</span><h2>Weapon controls</h2><p>One animation model, specialized weapon tracks.</p></div><nav class="weapon-inspector-tabs layered-inspector-tabs">${WEAPON_STUDIO_INSPECTOR_TABS.map(({ id, label, hint }) => `<button type="button" class="weapon-inspector-tab${state.inspectorTab === id ? ' is-active' : ''}" data-inspector-tab="${id}"><strong>${label}</strong><small>${hint}</small></button>`).join('')}</nav><div class="studio-inspector-scroll">${state.inspectorTab === 'identity' ? renderIdentityInspector(state) : state.inspectorTab === 'combat' ? renderCombatInspector(state) : state.inspectorTab === 'targeting' ? renderWeaponTargetingInspector(state.draft!) : state.inspectorTab === 'layer' ? renderLayerInspector(state, animation) : renderOnHitInspector(state)}</div></aside>`;
}

function weaponIconAssets(state: StudioState): readonly CharacterStudioAssetEntry[] {
  return state.assets?.assets.filter((asset) => asset.status === 'ready' && asset.tags.includes('weapon')) ?? [];
}

function renderWeaponIconPreview(state: StudioState): string {
  const iconKey = state.draft?.iconKey ?? '';
  const iconFrame = state.draft?.iconFrame ?? 0;
  const asset = weaponIconAssets(state).find((candidate) => candidate.textureKey === iconKey);
  if (asset) return frameSprite(asset, iconFrame, 'weapon-icon-preview-sprite');
  if (proceduralWeaponIconChoices.some((choice) => choice.textureKey === iconKey)) {
    return `<span class="weapon-icon-procedural-mark" aria-hidden="true">✦</span>`;
  }
  return `<span class="weapon-icon-empty-mark" aria-hidden="true">＋</span>`;
}

function renderWeaponIconControl(state: StudioState): string {
  const iconKey = state.draft?.iconKey ?? '';
  const iconFrame = state.draft?.iconFrame ?? 0;
  const asset = weaponIconAssets(state).find((candidate) => candidate.textureKey === iconKey);
  const procedural = proceduralWeaponIconChoices.find((choice) => choice.textureKey === iconKey);
  const title = asset?.assetId ?? procedural?.id.replaceAll('-', ' ') ?? 'No icon selected';
  const detail = iconKey ? `${iconKey} · frame ${iconFrame}` : 'Required before save';
  return `<div class="weapon-icon-cartridge${iconKey ? '' : ' is-empty'}"><button type="button" class="weapon-icon-cartridge-main" data-action="open-icon-picker" aria-label="Choose weapon icon"><span class="weapon-icon-cartridge-preview">${renderWeaponIconPreview(state)}</span><span class="weapon-icon-cartridge-copy"><small>UI ICON</small><strong>${escapeHtml(title)}</strong><em>${escapeHtml(detail)}</em></span></button><button type="button" class="weapon-icon-cartridge-clear" data-action="clear-icon" aria-label="Clear weapon icon" ${iconKey ? '' : 'disabled'}>×</button></div>`;
}

function renderScopeControls(state: StudioState, animation: LayeredAnimationDocument): string {
  const effectReady = Boolean(state.effectDraft);
  const attackTabs = DIRECTIONS.map((direction) => {
    const resolved = state.draft ? resolveWeaponAttack(state.draft, direction) : undefined;
    const status = directionalStatusLabel(direction, resolved, WEAPON_DIRECTIONAL_PAIRS);
    return `<button type="button" class="studio-pill${state.direction === direction ? ' is-active' : ''}" data-direction="${direction}">${direction.toUpperCase()}<small>${status}</small></button>`;
  }).join('');
  const effectTabs = EFFECT_DIRECTIONS.map((direction) => {
    const resolved = state.effectDraft ? resolveEffectDocumentVariant(state.effectDraft, direction) : undefined;
    const pairs = [
      { ...RIGHT_LEFT_INHERITANCE, enabled: state.effectDraft?.mirrorLeftFromRight === true },
      { ...DOWN_UP_INHERITANCE, enabled: state.effectDraft?.mirrorUpFromDown === true },
    ];
    const status = directionalStatusLabel(direction, resolved, pairs);
    return `<button type="button" class="studio-pill${state.effectDirection === direction ? ' is-active' : ''}" data-effect-direction="${direction}">${direction.toUpperCase()}<small>${status}</small></button>`;
  }).join('');
  return `<section class="layered-scope-strip">${renderWeaponIconControl(state)}<div class="studio-clip-tabs"><button type="button" class="studio-clip-tab${state.scope === 'idle' ? ' is-active' : ''}" data-scope="idle"><span>IDLE</span><small>${state.draft?.animations.idle.layers.length ?? 0} layers</small></button><button type="button" class="studio-clip-tab${state.scope === 'attack' ? ' is-active' : ''}" data-scope="attack"><span>ATTACK</span><small>directional</small></button><button type="button" class="studio-clip-tab${state.scope === 'effect' ? ' is-active' : ''}" data-scope="effect" ${effectReady ? '' : 'disabled'}><span>ON-HIT EFFECT</span><small>${effectReady ? 'contact' : 'none assigned'}</small></button></div>${state.scope === 'attack' ? `<div class="layered-direction-tabs">${attackTabs}</div>${renderDirectionalCharacterAction(state)}` : state.scope === 'effect' ? `<div class="layered-direction-tabs">${effectTabs}</div>` : ''}${renderDirectionalCommand(state)}<div class="layered-clock-controls"><label>FPS <input type="number" min="1" max="240" step="1" value="${animation.framesPerSecond}" data-animation-field="fps" /></label><label>DURATION <input type="number" min="0.01" max="60" step="0.01" value="${animation.durationSeconds}" data-animation-field="duration" /><span>s</span></label></div></section>`;
}

function renderPicker(state: StudioState, animation: LayeredAnimationDocument): string {
  if (!state.pickerOpen) return '';
  const layer = selectedLayer(state, animation);
  const asset = state.assets?.assets.find((candidate) => candidate.assetId === layer?.assetId);
  const info = assetInfo(asset);
  return `<div class="studio-asset-shelf-backdrop layered-tile-picker-backdrop" data-picker-backdrop><section class="studio-asset-shelf weapon-tile-picker" role="dialog" aria-modal="true" aria-labelledby="layered-tile-picker-title"><header class="studio-asset-shelf-heading"><div><span class="studio-kicker">${escapeHtml(layer?.displayName ?? 'Layer')} source</span><h2 id="layered-tile-picker-title">Add tiles to animation</h2><p>Source tiles stay in this popup. The timeline only shows authored blocks and their hold time.</p></div><button type="button" class="studio-icon-button" data-action="close-picker" aria-label="Close">×</button></header><div class="studio-sheet-grid projectile-frame-grid weapon-picker-grid">${Array.from({ length: info.count }, (_, frame) => `<button type="button" class="projectile-frame-option${state.pickerFrames.includes(frame) ? ' is-selected' : ''}" data-picker-frame="${frame}" aria-pressed="${state.pickerFrames.includes(frame)}">${frameSprite(asset, frame, 'projectile-frame-preview')}<span>${String(frame).padStart(2, '0')}</span></button>`).join('')}</div><footer class="weapon-tile-picker-footer"><span>${state.pickerFrames.length} selected · inserted at playhead ${state.playhead}</span><div><button type="button" class="studio-button studio-button--quiet" data-action="close-picker">CANCEL</button><button type="button" class="studio-button studio-button--accent" data-action="confirm-picker" ${state.pickerFrames.length ? '' : 'disabled'}>ADD TO LAYER</button></div></footer></section></div>`;
}

function renderIconPicker(state: StudioState): string {
  if (!state.iconPickerOpen) return '';
  const assets = weaponIconAssets(state);
  const selectedAsset = assets.find((asset) => asset.assetId === state.iconPickerAssetId)
    ?? assets.find((asset) => asset.textureKey === state.draft?.iconKey)
    ?? assets[0];
  const info = assetInfo(selectedAsset);
  const selectedKey = state.draft?.iconKey ?? '';
  const selectedFrame = state.draft?.iconFrame ?? 0;
  const assetTabs = assets.map((asset) => `<button type="button" class="weapon-icon-asset-tab${asset.assetId === selectedAsset?.assetId ? ' is-active' : ''}" data-icon-picker-asset="${escapeHtml(asset.assetId)}"><strong>${escapeHtml(asset.assetId)}</strong><small>${asset.kind === 'image' ? 'single image' : `${asset.frame?.count ?? 0} frames`}</small></button>`).join('');
  const frames = selectedAsset
    ? Array.from({ length: info.count }, (_, frame) => `<button type="button" class="projectile-frame-option${selectedAsset.textureKey === selectedKey && frame === selectedFrame ? ' is-selected' : ''}" data-icon-picker-frame="${frame}" aria-label="Use ${escapeHtml(selectedAsset.assetId)} frame ${frame}">${frameSprite(selectedAsset, frame, 'projectile-frame-preview')}<span>${String(frame).padStart(2, '0')}</span></button>`).join('')
    : `<p class="studio-empty-note">No weapon-tagged manifest icons are available.</p>`;
  const procedural = proceduralWeaponIconChoices.map((choice) => `<button type="button" class="weapon-icon-procedural-choice${choice.textureKey === selectedKey && selectedFrame === 0 ? ' is-selected' : ''}" data-icon-picker-procedural="${escapeHtml(choice.textureKey)}"><span aria-hidden="true">✦</span><strong>${escapeHtml(choice.id.replaceAll('-', ' '))}</strong><small>${escapeHtml(choice.textureKey)}</small></button>`).join('');
  return `<div class="studio-asset-shelf-backdrop weapon-icon-picker-backdrop" data-icon-picker-backdrop><section class="studio-asset-shelf weapon-icon-picker" role="dialog" aria-modal="true" aria-labelledby="weapon-icon-picker-title"><header class="studio-asset-shelf-heading"><div><span class="studio-kicker">Runtime thumbnail source</span><h2 id="weapon-icon-picker-title">Choose weapon UI icon</h2><p>Every inventory, hotbar, and crafting thumbnail uses this exact texture and frame.</p></div><button type="button" class="studio-icon-button" data-action="close-icon-picker" aria-label="Close">×</button></header><div class="weapon-icon-picker-body"><nav class="weapon-icon-asset-list" aria-label="Weapon icon assets">${assetTabs || '<span class="studio-empty-note">No manifest choices</span>'}</nav><div class="weapon-icon-picker-frames"><span class="studio-kicker">${escapeHtml(selectedAsset?.assetId ?? 'Manifest frames')}</span><div class="studio-sheet-grid projectile-frame-grid weapon-icon-frame-grid">${frames}</div><div class="weapon-icon-procedural-heading"><span class="studio-kicker">Procedural textures</span><small>Generated by BootScene · frame 0</small></div><div class="weapon-icon-procedural-grid">${procedural}</div></div></div><footer class="weapon-tile-picker-footer"><span>${selectedKey ? `${escapeHtml(selectedKey)} · frame ${selectedFrame}` : 'No icon selected'}</span><div><button type="button" class="studio-button studio-button--quiet" data-action="clear-icon" ${selectedKey ? '' : 'disabled'}>CLEAR ICON</button><button type="button" class="studio-button studio-button--accent" data-action="close-icon-picker">DONE</button></div></footer></section></div>`;
}

function renderWeaponLibrary(state: StudioState, returnEditor: string): string {
  return renderStudioLibraryTree({
    weapons: state.weapons,
    animations: state.animationPackages,
    search: state.librarySearch,
    expandedFolders: state.expandedFolders,
    selectedWeaponId: state.selectedId,
    footerHtml: `<button type="button" class="studio-button studio-button--outline" data-action="new-weapon">NEW WEAPON</button><a class="studio-button studio-button--outline studio-button--navigation" href="?studio=characters&amp;editor=${encodeURIComponent(returnEditor)}">↗ CHARACTER STUDIO</a>`,
  });
}

function renderStudio(state: StudioState, returnEditor: string): string {
  const animation = animationFor(state);
  if (!state.draft || !animation) {
    return `<main class="character-studio weapon-studio layered-weapon-studio"><header class="studio-topbar"><a class="studio-brand" href="?"><span class="brand-mark">✦</span><span><small>FIELD CARTOGRAPHER</small><strong>WEAPON STUDIO</strong></span></a><div class="studio-topbar-actions"><span class="studio-save-state"><i></i>${escapeHtml(state.notice ?? 'Loading layered weapon library…')}</span></div></header><section class="studio-empty-state"><span class="studio-loading-orb">✦</span><h2>${escapeHtml(state.notice ?? 'Loading weapons')}</h2></section></main>`;
  }
  const isNew = !state.revision;
  return `<main class="character-studio weapon-studio layered-weapon-studio${state.dirty || state.effectDirty ? ' is-dirty' : ''}"><header class="studio-topbar"><a class="studio-brand" href="?" aria-label="Back to game"><span class="brand-mark">✦</span><span><small>FIELD CARTOGRAPHER</small><strong>WEAPON STUDIO</strong></span></a><div class="studio-topbar-actions"><span class="studio-save-state${state.notice ? ' is-error' : ''}"><i></i>${escapeHtml(state.notice ?? (state.dirty || state.effectDirty ? 'Unsaved layered package' : 'Saved library'))}</span><button type="button" class="studio-button studio-button--save" data-action="save" ${(!state.dirty && !state.effectDirty) || state.saving ? 'disabled' : ''}>${state.saving ? 'SAVING…' : isNew ? 'CREATE WEAPON' : 'SAVE WEAPON'}</button></div></header><div class="studio-layout">${renderWeaponLibrary(state, returnEditor)}<section class="studio-workbench" style="--preview-split:${state.previewSplit}fr;--controls-split:${100 - state.previewSplit}fr"><div class="studio-workbench-heading"><div><span class="studio-kicker">Layered animation package</span><h2>${escapeHtml(state.draft.displayName)} <span>V2</span></h2></div><div class="studio-workbench-meta"><span>WEAPON <b>${escapeHtml(state.draft.weaponId)}</b></span><span>PLAYHEAD <b>${Number(state.playhead / animation.framesPerSecond).toFixed(2)}s</b></span><span>LAYERS <b>${animation.layers.length}</b></span></div></div>${renderPreview(state, animation)}<button type="button" class="layered-workbench-splitter" data-workbench-splitter aria-label="Resize preview and timeline" aria-valuemin="25" aria-valuemax="75" aria-valuenow="${state.previewSplit}" title="Drag to resize preview and timeline"><span></span></button><div class="layered-workbench-bottom layered-workbench-bottom--with-scope">${renderScopeControls(state, animation)}${renderTimeline(state, animation)}</div></section>${renderInspector(state, animation)}</div>${renderPicker(state, animation)}${renderIconPicker(state)}</main>`;
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
  const directionalActionMatch = field.match(/^directionalAttacks\.(right|left|up|down)\.characterActionId$/);
  if (directionalActionMatch) {
    const direction = directionalActionMatch[1] as WeaponAttackDirection;
    const resolved = resolveWeaponAttack(state.draft, direction);
    const attack = state.draft.directionalAttacks[direction];
    if (!resolved || !attack) return state;
    if (!resolved.authored) return { ...state, notice: `${direction.toUpperCase()} is inherited. Make it custom before editing.` };
    const actions = availableCharacterActions();
    const requested = value.trim().toLowerCase();
    const characterActionId = actions.includes(requested) ? requested : actions[0] ?? state.draft.characterActionId;
    return {
      ...state,
      draft: {
        ...state.draft,
        directionalAttacks: {
          ...state.draft.directionalAttacks,
          [direction]: { ...attack, characterActionId },
        },
      },
      dirty: true,
      notice: undefined,
    };
  }
  if (field.startsWith('hitbox:')) {
    const [, hitboxId, hitboxField] = field.split(':');
    const resolved = resolveWeaponAttack(state.draft, state.direction);
    if (!resolved?.authored || !hitboxId || !hitboxField) return resolved ? { ...state, notice: `${state.direction.toUpperCase()} is inherited. Make it custom before editing.` } : state;
    const hitbox = resolved.attack.hitboxes[hitboxId];
    if (!hitbox) return state;
    const nextHitbox = updateWeaponHitboxControl(hitbox, hitboxField, value);
    if (nextHitbox === hitbox) return state;
    return {
      ...state,
      draft: {
        ...state.draft,
        directionalAttacks: {
          ...state.draft.directionalAttacks,
          [state.direction]: { ...resolved.attack, hitboxes: { ...resolved.attack.hitboxes, [hitboxId]: nextHitbox } },
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

function stripSharedAnimationCopies(weapon: LayeredWeaponDefinition): LayeredWeaponDefinition {
  const animations = { ...weapon.animations } as Record<string, unknown>;
  if (animations.idleAnimationId) delete animations.idle;
  const directionalAttacks = Object.fromEntries(
    Object.entries(weapon.directionalAttacks).map(([direction, attack]) => {
      const next = { ...attack } as Record<string, unknown>;
      if (next.animationId) delete next.animation;
      return [direction, next];
    }),
  ) as unknown as LayeredWeaponDefinition['directionalAttacks'];
  return { ...weapon, animations: animations as unknown as LayeredWeaponDefinition['animations'], directionalAttacks };
}

interface SharedAnimationEdit {
  readonly animationId: string;
  readonly animation: LayeredAnimationDocument;
}

function sharedAnimationEdits(weapon: LayeredWeaponDefinition): readonly SharedAnimationEdit[] {
  const edits: SharedAnimationEdit[] = [];
  const seen = new Set<string>();
  const add = (animationId: string | undefined, animation: LayeredAnimationDocument | undefined): void => {
    if (!animationId || !animation || seen.has(animationId)) return;
    seen.add(animationId);
    edits.push({ animationId, animation });
  };
  add(weapon.animations.idleAnimationId, weapon.animations.idle);
  for (const attack of Object.values(weapon.directionalAttacks)) add(attack.animationId, attack.animation);
  return edits;
}

async function saveSharedAnimationEdits(weapon: LayeredWeaponDefinition): Promise<void> {
  const edits = sharedAnimationEdits(weapon);
  if (edits.length === 0) return;
  const catalog = await loadJson<AnimationPackageCatalog>('/__animation-library/catalog');
  const writes = edits.map((edit) => {
    const entry = catalog.packages.find((candidate) => candidate.animationId === edit.animationId) as AnimationPackageCatalogEntry | undefined;
    if (!entry) throw new Error(`Shared animation package '${edit.animationId}' was not found`);
    return {
      packagePath: entry.packagePath,
      expectedRevision: entry.revision,
      operation: 'update' as const,
      package: {
        $schema: entry.$schema,
        version: entry.version,
        animationId: entry.animationId,
        displayName: entry.displayName,
        description: entry.description,
        animation: edit.animation,
      },
    };
  });
  const response = await fetch('/__animation-library/transaction', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ expectedCatalogRevision: catalog.revision, writes }),
  });
  const payload = await response.json() as { ok?: boolean; error?: { message?: string } };
  if (!response.ok || !payload.ok) throw new Error(payload.error?.message ?? 'Shared animations could not be saved');
}

async function savePackage(state: StudioState): Promise<Partial<StudioState>> {
  if (!state.draft) throw new Error('No weapon is open');
  const weaponIssues = validateWeaponDefinitionForStudioSave(state.draft);
  if (weaponIssues.length) throw new Error(weaponIssues[0]);
  const iconIssues = validateWeaponIconAgainstCatalog(state.draft, weaponIconCatalogFromStudio(state.assets?.assets ?? []));
  if (iconIssues.length) throw new Error(iconIssues[0]);
  const weaponForSave = stripSharedAnimationCopies(state.draft);
  const saveIssues = validateWeaponDefinitionForStudioSave(weaponForSave);
  if (saveIssues.length) throw new Error(saveIssues[0]);
  if (state.effectDraft) {
    const effectIssues = validateEffectDefinition(state.effectDraft, {
      assetLookup: (assetId) => {
        const asset = state.assets?.assets.find((candidate) => candidate.assetId === assetId);
        return asset ? { kind: asset.kind, frameCount: asset.frame?.count ?? 1 } : undefined;
      },
    });
    if (effectIssues.length) throw new Error(effectIssues[0]);
  }
  await saveSharedAnimationEdits(state.draft);
  const response = await fetch('/__character-studio/weapon/save-package', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      weapon: weaponForSave,
      weaponOperation: state.revision ? 'update' : 'create',
      ...(state.revision ? { expectedWeaponRevision: state.revision } : {}),
      ...(state.effectDraft && state.effectDirty ? {
        effect: state.effectDraft,
        effectOperation: state.effectIsNew ? 'create' : 'update',
        ...(state.effectIsNew ? {} : { expectedEffectRevision: state.effectRevision }),
      } : {}),
    }),
  });
  const payload = await response.json() as {
    ok?: boolean;
    data?: { weaponRevision: string; effectRevision?: string };
    error?: { message?: string; issues?: readonly { path: string; message: string }[] };
  };
  if (!response.ok || !payload.ok || !payload.data) {
    throw new Error(payload.error?.issues?.[0]?.message ?? payload.error?.message ?? 'Weapon package save failed');
  }
  return { revision: payload.data.weaponRevision, effectRevision: payload.data.effectRevision ?? state.effectRevision, effectIsNew: false, effectDirty: false, dirty: false, notice: 'Saved. Reload the game to use changed content.' };
}

export function mountLayeredWeaponStudio(container: HTMLDivElement, options: LayeredWeaponStudioOptions = {}): () => void {
  container.classList.add('is-character-studio-host');
  const returnEditor = new URLSearchParams(window.location.search).get('editor') ?? 'level-1';
  let state: StudioState = {
    weapons: [], effects: [], animationPackages: [], librarySearch: '', sourceSheetSearch: '', expandedFolders: new Set(options.expandedFolders ?? ['weapons', 'animations']), selectedId: '', scope: 'attack', direction: 'right', effectDirection: 'right',
    effectIsNew: false, effectDirty: false, playhead: 0, previewZoom: 1, previewSplit: 55, inspectorTab: 'layer', pickerOpen: false,
    pickerFrames: [], iconPickerOpen: false, dirty: false, saving: false, playing: false,
  };
  let resize: ResizeDrag | undefined;
  let move: MoveDrag | undefined;
  let splitDrag: WorkbenchSplitDrag | undefined;
  let suppressedBlockClick: string | undefined;
  let playbackTimer: number | undefined;
  let playbackGeneration = 0;
  let playbackStep = 0;
  let history: WeaponStudioHistory = { undo: [], redo: [] };

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
    history = { undo: [], redo: [] };
    const prepared = prepareWeapon(entry, state.effects);
    const animation = prepared.draft.directionalAttacks.right.animation;
    state = selectionForAnimation({
      ...state, ...prepared, selectedId: entry.weaponId, revision: entry.revision, scope: 'attack', direction: 'right',
      effectDirection: 'right', playhead: 0, previewZoom: 1, dirty: entry.version === 1, inspectorTab: 'layer', pickerOpen: false,
      iconPickerOpen: false, iconPickerAssetId: undefined,
      notice: entry.version === 1 ? 'Legacy weapon migrated in memory. Save to commit version 2.' : undefined,
    }, animation);
    render();
  };
  const mutate = (next: StudioState): void => {
    const result = commitWeaponStudioMutation(state, next, history);
    state = result.state;
    history = result.history;
    render();
  };
  const mutateAnimation = (operation: (document: LayeredAnimationDocumentState) => boolean, failureNotice?: string): void => mutate(transformAnimationState(state, operation, failureNotice));
  const applyHistory = (redo: boolean): boolean => {
    const result = applyWeaponStudioHistory(state, history, redo);
    if (!result) return false;
    state = result.state;
    history = result.history;
    stopPlayback();
    render();
    return true;
  };
  const updateAttack = (update: (attack: NonNullable<ReturnType<typeof selectedAttack>>) => NonNullable<ReturnType<typeof selectedAttack>>): void => {
    if (!state.draft) return;
    const resolved = resolveWeaponAttack(state.draft, state.direction);
    if (!resolved) return;
    if (!resolved.authored) {
      mutate({ ...state, notice: `${state.direction.toUpperCase()} is inherited. Make it custom before editing.` });
      return;
    }
    mutate({ ...state, draft: { ...state.draft, directionalAttacks: { ...state.draft.directionalAttacks, [state.direction]: update(resolved.attack) } }, dirty: true });
  };
  const refreshHitboxPreview = (): void => {
    const guides = container.querySelector<HTMLElement>('[data-weapon-hitbox-guides]');
    const attack = selectedAttack(state);
    if (!guides || !attack) return;
    guides.innerHTML = renderWeaponHitboxGuides({
      hitboxes: attack.hitboxes,
      track: attack.attackTrack,
      direction: state.direction,
      timelineFrame: state.playhead,
      selectedHitboxId: state.selectedHitboxId,
      presentationOffsetY: weaponPresentationOffsetY(state),
    });
    container.querySelector<HTMLElement>('.layered-weapon-studio')?.classList.add('is-dirty');
    const saveButton = container.querySelector<HTMLButtonElement>('[data-action="save"]');
    if (saveButton) saveButton.disabled = false;
    const saveState = container.querySelector<HTMLElement>('.studio-save-state');
    if (saveState) {
      saveState.classList.remove('is-error');
      saveState.innerHTML = '<i></i>Unsaved layered package';
    }
  };

  const handleClick = (event: MouseEvent): void => {
    const target = event.target instanceof Element ? event.target : undefined;
    if (!target) return;
    if (target === target.closest('[data-icon-picker-backdrop]')) { mutate({ ...state, iconPickerOpen: false, iconPickerAssetId: undefined }); return; }
    if (target === target.closest('[data-picker-backdrop]')) { mutate({ ...state, pickerOpen: false, pickerFrames: [] }); return; }
    const weaponButton = target.closest<HTMLElement>('[data-weapon-id]');
    if (weaponButton) { const entry = state.weapons.find((weapon) => weapon.weaponId === weaponButton.dataset.weaponId); if (entry) { options.onSelectWeapon?.(entry.weaponId); selectCatalogWeapon(entry); } return; }
    const animationButton = target.closest<HTMLElement>('[data-animation-id]');
    if (animationButton?.dataset.animationId) {
      if ((state.dirty || state.effectDirty) && !window.confirm('Discard unsaved weapon changes?')) return;
      const animationId = animationButton.dataset.animationId;
      queueMicrotask(() => options.onSelectAnimation?.(animationId));
      return;
    }
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
      const blockKey = `${layerId}:${blockIndex}`;
      if (suppressedBlockClick === blockKey) { suppressedBlockClick = undefined; return; }
      const block = animationFor(state)?.layers.find((layer) => layer.layerId === layerId)?.blocks[blockIndex];
      mutate({ ...state, selectedLayerId: layerId, selectedBlockIndex: blockIndex, playhead: block?.from ?? state.playhead, inspectorTab: 'layer' }); return;
    }
    const ruler = target.closest<HTMLElement>('[data-layered-playhead-frame]');
    if (ruler) { mutate({ ...state, playhead: Number(ruler.dataset.layeredPlayheadFrame) }); return; }
    const hold = target.closest<HTMLElement>('[data-block-hold-delta]');
    if (hold) { mutateAnimation((document) => document.adjustBlockHold(hold.dataset.layerId!, Number(hold.dataset.blockIndex), Number(hold.dataset.blockHoldDelta))); return; }
    const deleteBlock = target.closest<HTMLElement>('[data-delete-block]');
    if (deleteBlock) { mutateAnimation((document) => document.deleteBlock(deleteBlock.dataset.layerId!, Number(deleteBlock.dataset.blockIndex))); return; }
    const emptyLane = target.closest<HTMLElement>('.layered-timeline-blocks');
    if (emptyLane && target === emptyLane) {
      const animation = animationFor(state);
      const layerId = emptyLane.closest<HTMLElement>('[data-layer-id]')?.dataset.layerId;
      if (!animation || !layerId) return;
      const bounds = emptyLane.getBoundingClientRect();
      const frameCount = layeredTimelineFrameCount(animation);
      const frame = Math.max(0, Math.min(frameCount - 1, Math.floor((event.clientX - bounds.left) / (bounds.width / frameCount))));
      mutate({ ...state, selectedLayerId: layerId, selectedBlockIndex: undefined, playhead: frame, inspectorTab: 'layer' }); return;
    }
    const pickerFrame = target.closest<HTMLElement>('[data-picker-frame]');
    if (pickerFrame) { const frame = Number(pickerFrame.dataset.pickerFrame); mutate({ ...state, pickerFrames: state.pickerFrames.includes(frame) ? state.pickerFrames.filter((value) => value !== frame) : [...state.pickerFrames, frame] }); return; }
    const iconPickerAsset = target.closest<HTMLElement>('[data-icon-picker-asset]');
    if (iconPickerAsset?.dataset.iconPickerAsset) { mutate({ ...state, iconPickerAssetId: iconPickerAsset.dataset.iconPickerAsset }); return; }
    const iconPickerFrame = target.closest<HTMLElement>('[data-icon-picker-frame]');
    if (iconPickerFrame) {
      const asset = weaponIconAssets(state).find((candidate) => candidate.assetId === state.iconPickerAssetId)
        ?? weaponIconAssets(state).find((candidate) => candidate.textureKey === state.draft?.iconKey)
        ?? weaponIconAssets(state)[0];
      if (asset) mutate(reduceWeaponIconAction(state, { type: 'select', selection: weaponIconSelection(asset, Number(iconPickerFrame.dataset.iconPickerFrame)) }));
      return;
    }
    const proceduralIcon = target.closest<HTMLElement>('[data-icon-picker-procedural]')?.dataset.iconPickerProcedural;
    if (proceduralIcon && isProceduralWeaponIconKey(proceduralIcon)) { mutate(reduceWeaponIconAction(state, { type: 'select', selection: weaponIconSelection({ textureKey: proceduralIcon }, 0) })); return; }
    const hitboxSelect = target.closest<HTMLElement>('[data-select-hitbox]');
    if (hitboxSelect) { mutate({ ...state, selectedHitboxId: hitboxSelect.dataset.selectHitbox, inspectorTab: 'combat' }); return; }
    const hitboxCell = target.closest<HTMLElement>('[data-toggle-hitbox-frame]');
    if (hitboxCell) { updateAttack((attack) => ({ ...attack, attackTrack: toggleSpan(attack.attackTrack ?? { hitboxSpans: [], events: [] }, hitboxCell.dataset.hitboxId!, Number(hitboxCell.dataset.toggleHitboxFrame)) })); return; }
    const action = target.closest<HTMLElement>('[data-action]')?.dataset.action;
    if (!action) return;
    if (action === 'add-target-modifier') { mutate(reduceWeaponTargetingAction(state, { type: 'add-modifier' })); return; }
    if (action === 'remove-target-modifier') {
      const index = Number(target.closest<HTMLElement>('[data-target-modifier-index]')?.dataset.targetModifierIndex);
      if (Number.isInteger(index)) mutate(reduceWeaponTargetingAction(state, { type: 'remove-modifier', index }));
      return;
    }
    if (action === 'add-harvest-capability') { mutate(reduceWeaponTargetingAction(state, { type: 'add-capability' })); return; }
    if (action === 'remove-harvest-capability') {
      const targetTag = target.closest<HTMLElement>('[data-harvest-capability-tag]')?.dataset.harvestCapabilityTag;
      if (targetTag) mutate(reduceWeaponTargetingAction(state, { type: 'remove-capability', targetTag }));
      return;
    }
    if (action === 'make-custom-direction') {
      const rawDirection = target.closest<HTMLElement>('[data-mirror-direction]')?.dataset.mirrorDirection;
      if (!rawDirection) return;
      if (state.scope === 'attack' && state.draft) {
        const direction = rawDirection as WeaponAttackDirection;
        const draft = makeCustomWeaponDirection(state.draft, direction);
        if (!draft) return;
        const next = { ...state, draft, dirty: true, notice: `Custom ${direction.toUpperCase()} direction created.` };
        const animation = animationFor(next);
        mutate(animation ? selectionForAnimation(next, animation) : next);
      } else if (state.scope === 'effect' && state.effectDraft) {
        const direction = rawDirection as EffectDirection;
        const effectDraft = makeCustomEffectDirection(state.effectDraft, direction);
        if (!effectDraft) return;
        const next = { ...state, effectDraft, effectDirty: true, notice: `Custom ${direction.toUpperCase()} effect direction created.` };
        const animation = animationFor(next);
        mutate(animation ? selectionForAnimation(next, animation) : next);
      }
      return;
    }
    if (action === 'restore-direction-mirror') {
      const rawDirection = target.closest<HTMLElement>('[data-mirror-direction]')?.dataset.mirrorDirection;
      if (!rawDirection) return;
      if (state.scope === 'attack' && state.draft) {
        const direction = rawDirection as WeaponAttackDirection;
        const draft = restoreWeaponDirection(state.draft, direction);
        const next = { ...state, draft, dirty: true, selectedLayerId: undefined, selectedBlockIndex: undefined, selectedHitboxId: undefined, notice: `Restored ${direction.toUpperCase()} mirror.` };
        const animation = animationFor(next);
        mutate(animation ? selectionForAnimation(next, animation) : next);
      } else if (state.scope === 'effect' && state.effectDraft) {
        const direction = rawDirection as EffectDirection;
        const effectDraft = restoreEffectDirection(state.effectDraft, direction);
        const next = { ...state, effectDraft, effectDirty: true, selectedLayerId: undefined, selectedBlockIndex: undefined, notice: `Restored ${direction.toUpperCase()} mirror.` };
        const animation = animationFor(next);
        mutate(animation ? selectionForAnimation(next, animation) : next);
      }
      return;
    }
    if (action === 'preview-zoom-in') { mutate({ ...state, previewZoom: adjustPreviewZoom(state.previewZoom, -1) }); return; }
    if (action === 'preview-zoom-out') { mutate({ ...state, previewZoom: adjustPreviewZoom(state.previewZoom, 1) }); return; }
    if (action === 'preview-zoom-reset') { mutate({ ...state, previewZoom: 1 }); return; }
    if (action === 'open-icon-picker') {
      const assets = weaponIconAssets(state);
      const current = assets.find((asset) => asset.textureKey === state.draft?.iconKey);
      mutate({ ...state, iconPickerOpen: true, iconPickerAssetId: current?.assetId ?? assets[0]?.assetId }); return;
    }
    if (action === 'close-icon-picker') { mutate({ ...state, iconPickerOpen: false, iconPickerAssetId: undefined }); return; }
    if (action === 'clear-icon') { mutate(reduceWeaponIconAction(state, { type: 'clear' })); return; }
    if (action === 'add-layer') {
      const animation = animationFor(state); const fallbackAsset = spritesheetAssets(state.assets)[0]?.assetId;
      if (!animation || !fallbackAsset) return;
      let index = animation.layers.length + 1; while (animation.layers.some((layer) => layer.layerId === `layer-${index}`)) index += 1;
      mutateAnimation((document) => document.addLayer({ layerId: `layer-${index}`, displayName: `Layer ${index}`, assetId: fallbackAsset, depthOffset: index - 1, blocks: [] })); return;
    }
    if (action === 'add-layer-tiles') { mutate({ ...state, pickerOpen: true, pickerFrames: [] }); return; }
    if (action === 'close-picker') { mutate({ ...state, pickerOpen: false, pickerFrames: [] }); return; }
    if (action === 'confirm-picker') { const frames = [...state.pickerFrames]; state = { ...state, pickerOpen: false, pickerFrames: [] }; mutateAnimation((document) => Boolean(state.selectedLayerId && document.placeTiles(state.selectedLayerId, frames, state.playhead)), 'Those tiles could not be placed inside the animation duration.'); return; }
    if (action === 'delete-layer' && state.selectedLayerId) { mutateAnimation((document) => document.deleteLayer(state.selectedLayerId!)); return; }
    if (action === 'layer-up' && state.selectedLayerId) { mutateAnimation((document) => document.moveLayer(state.selectedLayerId!, 1)); return; }
    if (action === 'layer-down' && state.selectedLayerId) { mutateAnimation((document) => document.moveLayer(state.selectedLayerId!, -1)); return; }
    if (action === 'reset-block-transform' && state.selectedLayerId && state.selectedBlockIndex !== undefined) {
      const layerId = state.selectedLayerId;
      const blockIndex = state.selectedBlockIndex;
      mutateAnimation((document) => document.setBlockTransform(layerId, blockIndex)); return;
    }
    if (action === 'duplicate-block' && state.selectedLayerId && state.selectedBlockIndex !== undefined) {
      const layerId = state.selectedLayerId;
      const blockIndex = state.selectedBlockIndex;
      mutateAnimation((document) => document.duplicateBlock(layerId, blockIndex), 'There is not enough room for a duplicate tile. Increase the animation duration first.'); return;
    }
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
      const effect: EffectDefinition = { version: 1, effectId, displayName: `${state.draft.displayName} impact`, mirrorLeftFromRight: true, mirrorUpFromDown: true, directions: { right: { ...clone(animation), loop: false }, down: { ...clone(animation), loop: false } } };
      mutate({ ...state, draft: { ...state.draft, onHitEffectId: effectId }, effectDraft: effect, effectRevision: undefined, effectIsNew: true, effectDirty: true, dirty: true, scope: 'effect', effectDirection: 'right', playhead: 0 }); return;
    }
    if (action === 'new-weapon') {
      const assetId = spritesheetAssets(state.assets).find((asset) => asset.tags.includes('weapon'))?.assetId ?? spritesheetAssets(state.assets)[0]?.assetId ?? '';
      const draft = createWeaponDraft(assetId);
      options.onSelectWeapon?.(draft.weaponId);
      mutate(selectionForAnimation({ ...state, selectedId: '', draft, revision: undefined, effectDraft: undefined, effectRevision: undefined, effectIsNew: false, effectDirty: false, dirty: true, scope: 'attack', direction: 'right', playhead: 0, iconPickerOpen: false, iconPickerAssetId: undefined, notice: undefined }, draft.directionalAttacks.right.animation)); return;
    }
    if (action === 'play-preview') {
      if (state.playing) { stopPlayback(); render(); return; }
      const animation = animationFor(state); if (!animation) return;
      if (playbackTimer !== undefined) window.clearInterval(playbackTimer);
      playbackTimer = undefined;
      const generation = ++playbackGeneration;
      playbackStep = 0;
      state = { ...state, playing: true, playhead: 0 }; render();
      playbackTimer = window.setInterval(() => {
        if (generation !== playbackGeneration || !state.playing) return;
        const current = animationFor(state);
        if (!current) { stopPlayback(); render(); return; }
        const frames = layeredTimelineFrameCount(current);
        const nextStep = playbackStep + 1;
        if (nextStep >= frames && !current.loop) { stopPlayback(); state = { ...state, playhead: frames - 1 }; render(); return; }
        playbackStep = nextStep;
        const next = layeredAnimationFrameAtStep(current, playbackStep);
        state = { ...state, playhead: next };
        updateLayeredAnimationPreviewPlayback(container, renderPreview(state, current), next, next / current.framesPerSecond);
      }, 1000 / animation.framesPerSecond); return;
    }
    if (action === 'save') {
      if (state.draft) options.onSelectWeapon?.(state.draft.weaponId);
      state = { ...state, saving: true, notice: undefined }; render();
      void savePackage(state).then((saved) => { state = { ...state, ...saved, saving: false }; render(); }).catch((error: unknown) => { state = { ...state, saving: false, notice: error instanceof Error ? error.message : String(error) }; render(); });
    }
  };

  const handleChange = (event: Event): void => {
    const target = event.target;
    if (!(target instanceof HTMLInputElement || target instanceof HTMLSelectElement)) return;
    if (target.dataset.targetModifierTag !== undefined) {
      mutate(reduceWeaponTargetingAction(state, { type: 'set-modifier-tag', index: Number(target.dataset.targetModifierTag), targetTag: target.value }));
      return;
    }
    if (target.dataset.targetModifierValue !== undefined) {
      mutate(reduceWeaponTargetingAction(state, { type: 'set-modifier-value', index: Number(target.dataset.targetModifierValue), modifier: target.value }));
      return;
    }
    if (target.dataset.harvestCapabilityTier !== undefined) {
      mutate(reduceWeaponTargetingAction(state, { type: 'set-capability-tier', targetTag: target.dataset.harvestCapabilityTier, tier: target.value }));
      return;
    }
    if (target.dataset.harvestCapabilityTag !== undefined) {
      mutate(reduceWeaponTargetingAction(state, { type: 'rename-capability', targetTag: target.dataset.harvestCapabilityTag, nextTargetTag: target.value }));
      return;
    }
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
    const blockTimingField = target.dataset.blockTimingField;
    if (blockTimingField === 'startSeconds' && state.selectedLayerId && state.selectedBlockIndex !== undefined) {
      const animation = animationFor(state);
      const seconds = Number(target.value);
      if (animation && Number.isFinite(seconds)) mutateAnimation((document) => document.moveBlock(state.selectedLayerId!, state.selectedBlockIndex!, seconds * animation.framesPerSecond));
      return;
    }
    const blockTransformField = target.dataset.blockTransformField;
    if (blockTransformField && state.selectedLayerId && state.selectedBlockIndex !== undefined) {
      const animation = animationFor(state);
      const block = animation?.layers.find((layer) => layer.layerId === state.selectedLayerId)?.blocks[state.selectedBlockIndex];
      const numericValue = Number(target.value);
      const isFlipField = blockTransformField === 'flipX' || blockTransformField === 'flipY';
      if (!block || (!isFlipField && !Number.isFinite(numericValue))) return;
      const transform = normalizeAnimationBlockTransform(block.transform);
      const offset = [...transform.offset] as [number, number];
      const scale = [...transform.scale] as [number, number];
      if (blockTransformField === 'offsetX') offset[0] = numericValue;
      else if (blockTransformField === 'offsetY') offset[1] = numericValue;
      else if (blockTransformField === 'scaleX') scale[0] = numericValue;
      else if (blockTransformField === 'scaleY') scale[1] = numericValue;
      const rotationDeg = blockTransformField === 'rotationDeg' ? numericValue : transform.rotationDeg;
      mutateAnimation((document) => document.setBlockTransform(state.selectedLayerId!, state.selectedBlockIndex!, {
        offset,
        scale,
        rotationDeg,
        flipX: blockTransformField === 'flipX' && target instanceof HTMLInputElement ? target.checked : transform.flipX,
        flipY: blockTransformField === 'flipY' && target instanceof HTMLInputElement ? target.checked : transform.flipY,
      }));
      return;
    }
    const animationField = target.dataset.animationField;
    if (animationField) {
      const value = Number(target.value);
      mutateAnimation((document) => animationField === 'fps' ? document.setFramesPerSecond(value) : document.setDurationSeconds(value));
    }
  };

  const handleInput = (event: Event): void => {
    const target = event.target;
    if (!(target instanceof HTMLInputElement)) return;
    if (target.dataset.studioLibrarySearch !== undefined) {
      state = { ...state, librarySearch: target.value };
      render();
      container.querySelector<HTMLInputElement>('[data-studio-library-search]')?.focus();
      return;
    }
    if (target.dataset.sourceSheetSearch !== undefined) {
      const selectionStart = target.selectionStart ?? target.value.length;
      state = { ...state, sourceSheetSearch: target.value };
      render();
      const search = container.querySelector<HTMLInputElement>('[data-source-sheet-search]');
      search?.focus();
      search?.setSelectionRange(selectionStart, selectionStart);
      return;
    }
    const field = target.dataset.weaponField;
    if (!field?.startsWith('hitbox:') || target.value.trim() === '') return;
    const next = updateWeaponField(state, field, target.value);
    if (next === state) return;
    state = next;
    refreshHitboxPreview();
  };

  const handleWheel = (event: WheelEvent): void => {
    const target = event.target instanceof Element ? event.target.closest<HTMLElement>('.layered-preview') : undefined;
    if (!target) return;
    event.preventDefault();
    const previewZoom = adjustPreviewZoom(state.previewZoom, event.deltaY);
    if (previewZoom !== state.previewZoom) mutate({ ...state, previewZoom });
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
      const animation = animationFor(state); const lane = resizeHandle.closest<HTMLElement>('.layered-timeline-blocks');
      if (!animation || !lane) return;
      const layerId = resizeHandle.dataset.layerId!; const blockIndex = Number(resizeHandle.dataset.blockIndex);
      const block = animation.layers.find((layer) => layer.layerId === layerId)?.blocks[blockIndex];
      if (!block) return;
      event.preventDefault(); event.stopPropagation();
      resize = { pointerId: event.pointerId, layerId, blockIndex, originalThrough: block.through, startX: event.clientX, frameWidth: lane.getBoundingClientRect().width / layeredTimelineFrameCount(animation) };
      resizeHandle.setPointerCapture(event.pointerId);
      return;
    }
    const moveHandle = event.target.closest<HTMLElement>('[data-select-block]');
    const lane = moveHandle?.closest<HTMLElement>('.layered-timeline-blocks');
    const blockElement = moveHandle?.closest<HTMLElement>('[data-layer-block]');
    const animation = animationFor(state);
    if (!moveHandle || !lane || !blockElement || !animation) return;
    const layerId = moveHandle.dataset.layerId!; const blockIndex = Number(moveHandle.dataset.blockIndex);
    const block = animation.layers.find((layer) => layer.layerId === layerId)?.blocks[blockIndex];
    if (!block) return;
    move = {
      pointerId: event.pointerId,
      layerId,
      blockIndex,
      originalFrom: block.from,
      startX: event.clientX,
      frameWidth: lane.getBoundingClientRect().width / layeredTimelineFrameCount(animation),
      blockElement,
      previewDelta: 0,
    };
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
    const animation = animationFor(state);
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
    if (resize && resize.pointerId === event.pointerId) {
      event.preventDefault();
      const delta = Math.round((event.clientX - resize.startX) / resize.frameWidth);
      const current = resize; resize = undefined;
      if (delta !== 0) mutateAnimation((document) => document.resizeBlock(current.layerId, current.blockIndex, current.originalThrough + delta));
      return;
    }
    if (!move || move.pointerId !== event.pointerId) return;
    const current = move; move = undefined;
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
    if (move?.pointerId !== event.pointerId) return;
    const current = move; move = undefined; clearMovePreview(current);
    const animation = animationFor(state);
    const startLabel = current.blockElement.querySelector<HTMLElement>('.timeline-frame-number');
    if (animation && startLabel) startLabel.textContent = String(current.originalFrom).padStart(2, '0');
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
    const animation = animationFor(state);
    const layerId = blockButton.dataset.layerId!; const blockIndex = Number(blockButton.dataset.blockIndex);
    const block = animation?.layers.find((layer) => layer.layerId === layerId)?.blocks[blockIndex];
    if (!animation || !block) return;
    event.preventDefault();
    const hold = block.through - block.from + 1;
    const requestedFrom = event.key === 'Home' ? 0
      : event.key === 'End' ? layeredTimelineFrameCount(animation) - hold
        : block.from + (event.key === 'ArrowLeft' ? -1 : 1);
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
  container.addEventListener('change', handleChange);
  container.addEventListener('input', handleInput);
  container.addEventListener('wheel', handleWheel, { passive: false });
  container.addEventListener('pointerdown', handlePointerDown);
  container.addEventListener('pointermove', handlePointerMove);
  container.addEventListener('pointerup', handlePointerUp);
  container.addEventListener('pointercancel', handlePointerCancel);
  container.addEventListener('keydown', handleKeyDown);
  container.addEventListener('toggle', handleToggle, true);
  render();
  void Promise.all([
    loadJson<WeaponCatalogResponse>('/__character-studio/weapons'),
    loadJson<EffectCatalogResponse>('/__character-studio/effects'),
    loadJson<CharacterStudioAssetCatalog>('/__character-studio/assets'),
    loadJson<AnimationPackageCatalog>('/__animation-library/catalog'),
  ]).then(([weaponCatalog, effectCatalog, assets, animationCatalog]) => {
    state = { ...state, weapons: weaponCatalog.weapons, effects: effectCatalog.effects, assets, animationPackages: animationCatalog.packages };
    const requestedWeaponId = options.initialWeaponId ?? new URLSearchParams(window.location.search).get('weapon') ?? undefined;
    const selected = weaponCatalog.weapons.find((weapon) => weapon.weaponId === requestedWeaponId) ?? weaponCatalog.weapons[0];
    if (selected) selectCatalogWeapon(selected); else { state = { ...state, notice: 'No weapon packages found.' }; render(); }
  }).catch((error: unknown) => { state = { ...state, notice: error instanceof Error ? error.message : String(error) }; render(); });

  return () => {
    stopPlayback();
    container.removeEventListener('click', handleClick);
    container.removeEventListener('change', handleChange);
    container.removeEventListener('input', handleInput);
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
