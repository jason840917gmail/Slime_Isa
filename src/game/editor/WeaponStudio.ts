import './character-studio.css';

import { characterPackages } from 'virtual-character-content';
import type { CharacterStudioAssetCatalog, CharacterStudioAssetEntry } from '../content/characters/characterAssetCatalog';
import type {
  NormalizedWeaponAnimationDocument,
  WeaponAnimationDocument,
  WeaponAnimationSet,
  WeaponAttackDirection,
  WeaponAuthoredAttackDirection,
  WeaponAttackTrackDocument,
  WeaponDefinition,
  WeaponDirectionalAttackDocument,
  WeaponFrameTransformDocument,
  WeaponHitboxDocument,
  WeaponHitboxShape,
} from '../content/weapons/types';
import { resolveAssetUrl } from '../infrastructure/assets/assetUrls';
import {
  deleteKeyframes,
  duplicateKeyframe,
  evenKeyframeTimes,
  expandAnimationClip,
  holdLengthAtKeyframe,
  normalizeAnimationClip,
  rescaleKeyframeTimes,
  resizeKeyframeHold,
  timelineFrameCount,
} from '../shared/animation';
import type { AnimationJsonValue } from '../shared/animation';
import { ensureStudioModeTabs } from './StudioModeTabs';
import { createAnimationTimelineView, formatAnimationTimelineSeconds, previewTargetAtKeyframe, renderTimelineHoldControls, renderTimelineKeyframeTimingLabels, renderTimelineResizeHandle, toggleTimelineSelection, type AnimationTimelineKeyframeView } from './AnimationTimelineView';
import { renderAnimationTimelinePanel, renderAnimationTimelineRuler } from './AnimationTimelinePanel';
import { TimelineHoldResizeController } from './AnimationTimelineResize';
import {
  resolveWeaponHitboxPreview,
  resolveWeaponHitboxPreviewGeometry,
  weaponAttackTrackScopeLabel,
  weaponHitboxIsActive,
  WEAPON_HITBOX_PREVIEW_SCALE,
} from './WeaponHitboxPreview';

type WeaponAnimationId = 'idle' | 'attack' | 'impact';
type WeaponInspectorTab = 'identity' | 'combat' | 'visual';
type WeaponTransformTool = 'move' | 'scale' | 'rotate';

const WEAPON_ATTACK_DIRECTIONS = ['right', 'left', 'up', 'down'] as const satisfies readonly WeaponAttackDirection[];

const WEAPON_INSPECTOR_TABS: readonly { readonly id: WeaponInspectorTab; readonly label: string; readonly hint: string }[] = [
  { id: 'identity', label: 'IDENTITY', hint: 'source + action' },
  { id: 'combat', label: 'COMBAT', hint: 'stats + hitboxes' },
  { id: 'visual', label: 'VISUAL', hint: 'scale + offset' },
];

interface WeaponCatalogEntry extends WeaponDefinition {
  readonly revision: string;
}

interface WeaponCatalogResponse {
  readonly version: 1;
  readonly revision: string;
  readonly weapons: readonly WeaponCatalogEntry[];
}

interface WeaponStudioState {
  readonly assets?: CharacterStudioAssetCatalog;
  readonly weapons: readonly WeaponCatalogEntry[];
  readonly selectedId: string;
  readonly selectedAnimation: WeaponAnimationId;
  readonly selectedAttackDirection: WeaponAttackDirection;
  readonly selectedHitboxId: string;
  readonly selectedAnimationPositions: readonly number[];
  readonly transformTool: WeaponTransformTool;
  readonly onionSkin: boolean;
  readonly selectedInspectorTab: WeaponInspectorTab;
  readonly selectedPreviewFrame: number;
  readonly selectedCharacterId: string;
  readonly previewStep: number;
  readonly previewPlaying: boolean;
  readonly draft?: WeaponDefinition;
  readonly revision?: string;
  readonly dirty: boolean;
  readonly saving: boolean;
  readonly assetShelfOpen: boolean;
  readonly sourceTilePickerOpen: boolean;
  readonly selectedPickerFrames: readonly number[];
  readonly importing: boolean;
  readonly importForm: { readonly assetId: string; readonly frameWidth: string; readonly frameHeight: string; readonly populatedCount: string };
  readonly notice?: string;
}

interface MutableWeaponScalingGroup {
  strength?: number;
  vitality?: number;
  agility?: number;
  intellect?: number;
}

interface MutableWeaponScaling {
  damage?: MutableWeaponScalingGroup;
  cooldown?: MutableWeaponScalingGroup;
  knockback?: MutableWeaponScalingGroup;
}

type MutableWeaponHitbox = { -readonly [Key in keyof WeaponHitboxDocument]: WeaponHitboxDocument[Key] };
type MutableWeaponTrack = { hitboxSpans: Array<{ hitboxId: string; from: number; through: number }>; events: Array<{ at: number; eventId: string; payload?: AnimationJsonValue }> };
type Mutable<T> = { -readonly [Key in keyof T]: T[Key] };
type MutableWeaponAnimation = Omit<Mutable<WeaponAnimationDocument>, 'frames' | 'frameTransforms'> & { frames: number[]; frameTransforms?: Record<string, WeaponFrameTransformDocument> };
type MutableDirectionalAttack = Omit<Mutable<WeaponDirectionalAttackDocument>, 'animation' | 'attackTrack' | 'hitboxes'> & { animation: MutableWeaponAnimation; attackTrack?: MutableWeaponTrack; hitboxes?: Record<string, MutableWeaponHitbox> };
type MutableWeaponDraft = Omit<Mutable<WeaponDefinition>, 'scaling' | 'hitboxes' | 'attackTrack' | 'directionalAttacks'> & {
  scaling?: MutableWeaponScaling;
  hitboxes?: Record<string, MutableWeaponHitbox>;
  attackTrack?: MutableWeaponTrack;
  directionalAttacks?: Partial<Record<WeaponAuthoredAttackDirection, MutableDirectionalAttack>>;
};

type StudioCharacterPackage = (typeof characterPackages)[number];

function escapeHtml(value: unknown): string {
  return String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function integerValue(value: unknown, fallback = 0): number {
  const numeric = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(numeric) ? Math.round(numeric) : fallback;
}

function authoredDirectionalAttack(
  weapon: WeaponDefinition,
  direction: WeaponAttackDirection,
): WeaponDirectionalAttackDocument | undefined {
  if (direction === 'right') return weapon.directionalAttacks?.right ?? weapon.directionalAttacks?.side;
  if (direction === 'left') return weapon.directionalAttacks?.left ?? weapon.directionalAttacks?.right ?? weapon.directionalAttacks?.side;
  return weapon.directionalAttacks?.[direction];
}

function isMirroredLeft(weapon: WeaponDefinition): boolean {
  return weapon.directionalAttacks?.left === undefined;
}

function weaponHitboxes(weapon: WeaponDefinition, direction?: WeaponAttackDirection): Readonly<Record<string, WeaponHitboxDocument>> {
  return (direction ? authoredDirectionalAttack(weapon, direction)?.hitboxes : undefined) ?? weapon.hitboxes ?? {
    primary: {
      shape: 'sector',
      width: weapon.hitboxWidth,
      height: weapon.hitboxHeight,
      offsetX: weapon.hitboxOffset,
      offsetY: 0,
      innerRadius: 0,
      outerRadius: weapon.hitboxOffset + weapon.hitboxWidth / 2,
    },
  };
}

function weaponTrack(weapon: WeaponDefinition, animation: WeaponAnimationDocument, direction?: WeaponAttackDirection): WeaponAttackTrackDocument {
  const timelineFrames = animation.keyframeTimes !== undefined && animation.durationSeconds !== undefined
    ? timelineFrameCount(animation)
    : Math.max(1, animation.frames.length);
  return (direction ? authoredDirectionalAttack(weapon, direction)?.attackTrack : undefined) ?? weapon.attackTrack ?? {
    hitboxSpans: [{ hitboxId: Object.keys(weaponHitboxes(weapon, direction))[0] ?? 'primary', from: 0, through: Math.max(0, timelineFrames - 1) }],
    events: [],
  };
}

function resolvedSelectedHitboxId(
  hitboxes: Readonly<Record<string, WeaponHitboxDocument>>,
  requestedId: string,
): string {
  return hitboxes[requestedId] ? requestedId : Object.keys(hitboxes)[0] ?? '';
}

function selectedCharacter(): StudioCharacterPackage | undefined {
  return characterPackages.find((entry) => entry.character.kind === 'player') ?? characterPackages[0];
}

function transformValue(value: number): number {
  return Math.round(value * 100) / 100;
}

function previewCharacter(characterId: string): StudioCharacterPackage | undefined {
  return characterPackages.find((entry) => entry.characterId === characterId) ?? selectedCharacter();
}

function characterActions(character: StudioCharacterPackage | undefined): readonly string[] {
  if (!character) return [];
  return Object.entries(character.visualSet.clips)
    .filter(([, clip]) => clip.frames.length > 0)
    .map(([actionId]) => actionId)
    .sort((left, right) => left.localeCompare(right));
}

function resolvedCharacterAction(character: StudioCharacterPackage | undefined, weapon: WeaponDefinition, direction?: WeaponAttackDirection): string {
  const requested = (direction ? authoredDirectionalAttack(weapon, direction)?.characterActionId : undefined)
    ?? weapon.characterActionId
    ?? weapon.animKey?.replace(/^slime-/, '')
    ?? '';
  const actions = characterActions(character);
  return actions.includes(requested) ? requested : actions[0] ?? 'trick';
}

function characterClip(character: StudioCharacterPackage | undefined, actionId: string): { readonly id: string; readonly frames: readonly number[]; readonly framesPerSecond: number } | undefined {
  if (!character) return undefined;
  const clips = character.visualSet.clips;
  const id = clips[actionId] ? actionId : clips.trick ? 'trick' : clips.idle ? 'idle' : Object.keys(clips)[0];
  const clip = id ? clips[id] : undefined;
  return clip ? { id: id ?? 'idle', frames: clip.frames, framesPerSecond: clip.framesPerSecond } : undefined;
}

function assetInfo(entry: CharacterStudioAssetEntry | undefined): { readonly url: string; readonly width: number; readonly height: number; readonly columns: number; readonly rows: number; readonly count: number } {
  if (!entry) return { url: '', width: 1, height: 1, columns: 1, rows: 1, count: 1 };
  if (!entry.frame) return { url: resolveAssetUrl(entry.sourcePath), width: entry.dimensions.width, height: entry.dimensions.height, columns: 1, rows: 1, count: 1 };
  return { url: resolveAssetUrl(entry.sourcePath), width: entry.frame.width, height: entry.frame.height, columns: entry.frame.columns, rows: entry.frame.rows, count: entry.frame.count };
}

function isWeaponAsset(entry: CharacterStudioAssetEntry): boolean {
  return entry.tags.includes('weapon');
}

function renderCharacterActionField(state: WeaponStudioState): string {
  const character = previewCharacter(state.selectedCharacterId);
  const selected = resolvedCharacterAction(character, state.draft ?? makeNewWeapon());
  const options = characterActions(character).map((actionId) => `<option value="${escapeHtml(actionId)}" ${actionId === selected ? 'selected' : ''}>${escapeHtml(actionId.replaceAll('-', ' '))}</option>`).join('');
  return `<label class="studio-field"><span>Character action<small>available on preview character</small></span><select data-weapon-field="characterActionId" aria-label="Character action">${options || `<option value="trick" selected>trick</option>`}</select></label>`;
}

function renderPreviewCharacterField(state: WeaponStudioState): string {
  const options = characterPackages.map((entry) => `<option value="${escapeHtml(entry.characterId)}" ${entry.characterId === state.selectedCharacterId ? 'selected' : ''}>${escapeHtml(entry.character.displayName)} · ${escapeHtml(entry.characterId)}</option>`).join('');
  return `<label class="studio-field studio-field--wide"><span>Preview character<small>anchor + available actions</small></span><select data-weapon-character-id aria-label="Preview character">${options}</select></label>`;
}

function renderWeaponInspectorTabs(state: WeaponStudioState): string {
  return `<nav class="weapon-inspector-tabs" data-weapon-inspector-tabs role="tablist" aria-label="Weapon inspector sections">${WEAPON_INSPECTOR_TABS.map((tab) => `<button type="button" class="weapon-inspector-tab${tab.id === state.selectedInspectorTab ? ' is-active' : ''}" data-weapon-inspector-tab="${tab.id}" role="tab" aria-selected="${tab.id === state.selectedInspectorTab}"><strong>${tab.label}</strong><small>${tab.hint}</small></button>`).join('')}</nav>`;
}

function syncWeaponInspectorTabs(container: HTMLDivElement, state: WeaponStudioState): void {
  const inspector = container.querySelector<HTMLElement>('.weapon-inspector');
  if (!inspector) return;
  if (!inspector.querySelector('[data-weapon-inspector-tabs]')) {
    const heading = inspector.querySelector<HTMLElement>('.studio-inspector-heading');
    if (heading) heading.insertAdjacentHTML('afterend', renderWeaponInspectorTabs(state));
    else inspector.insertAdjacentHTML('afterbegin', renderWeaponInspectorTabs(state));
  }
  inspector.querySelectorAll<HTMLElement>('[data-weapon-inspector-tab]').forEach((tab) => {
    const active = tab.dataset.weaponInspectorTab === state.selectedInspectorTab;
    tab.classList.toggle('is-active', active);
    tab.setAttribute('aria-selected', String(active));
  });
  inspector.querySelectorAll<HTMLElement>('[data-weapon-inspector-group]').forEach((section) => {
    section.hidden = section.dataset.weaponInspectorGroup !== state.selectedInspectorTab;
  });
}

function defaultWeaponAnimations(info: ReturnType<typeof assetInfo>): WeaponAnimationSet {
  const attackFrames = Array.from({ length: Math.min(info.count, 4) }, (_, index) => index);
  return {
    idle: { frames: [0], keyframeTimes: [0], durationSeconds: 0.125, framesPerSecond: 8, loop: true, loopMode: 'wrap' },
    attack: { frames: attackFrames.length > 0 ? attackFrames : [0], keyframeTimes: attackFrames.length > 0 ? attackFrames : [0], durationSeconds: Math.max(1, attackFrames.length) / 12, framesPerSecond: 12, loop: false, loopMode: 'wrap' },
    impact: { frames: [Math.max(info.count - 1, 0)], keyframeTimes: [0], durationSeconds: 1 / 12, framesPerSecond: 12, loop: false, loopMode: 'wrap' },
  };
}

function normalizedWeaponAnimation(clip: WeaponAnimationDocument): NormalizedWeaponAnimationDocument {
  const sourceFrames = clip.frames.length > 0 ? clip.frames : [0];
  const normalized = normalizeAnimationClip({ ...clip, frames: sourceFrames });
  const frameTransforms = Object.fromEntries(Object.entries(clip.frameTransforms ?? {}).filter(([position]) => Number(position) >= 0 && Number(position) < normalized.frames.length));
  return {
    ...normalized,
    ...(Object.keys(frameTransforms).length > 0 ? { frameTransforms } : {}),
  };
}

function weaponAnimations(weapon: WeaponDefinition | undefined, info: ReturnType<typeof assetInfo>): WeaponAnimationSet {
  const current = weapon?.animations;
  const fallback = defaultWeaponAnimations(info);
  const clamp = (clip: WeaponAnimationDocument): WeaponAnimationDocument => {
    const frames = clip.frames.map((frame) => Math.max(0, Math.min(integerValue(frame), info.count - 1))).filter((frame) => Number.isInteger(frame));
    return normalizedWeaponAnimation({ ...clip, frames: frames.length > 0 ? frames : [0] });
  };
  return {
    idle: clamp(current?.idle ?? fallback.idle),
    attack: clamp(current?.attack ?? fallback.attack),
    impact: clamp(current?.impact ?? fallback.impact),
  };
}

function directionalAttack(
  weapon: WeaponDefinition,
  info: ReturnType<typeof assetInfo>,
  direction: WeaponAttackDirection,
): WeaponDirectionalAttackDocument {
  const authored = authoredDirectionalAttack(weapon, direction);
  const fallback = weaponAnimations(weapon, info).attack;
  const animation = authored?.animation ?? fallback;
  const frames = animation.frames
    .map((frame) => Math.max(0, Math.min(integerValue(frame), info.count - 1)))
    .filter((frame) => Number.isInteger(frame));
  return {
    animation: normalizedWeaponAnimation({ ...animation, frames: frames.length > 0 ? frames : [0] }),
    characterActionId: authored?.characterActionId ?? weapon.characterActionId ?? weapon.animKey?.replace(/^slime-/, '') ?? 'trick',
    hitboxes: authored?.hitboxes ?? weaponHitboxes(weapon),
    ...((authored?.attackTrack ?? weapon.attackTrack) ? { attackTrack: authored?.attackTrack ?? weapon.attackTrack } : {}),
  };
}

function selectedWeaponAnimation(
  weapon: WeaponDefinition,
  info: ReturnType<typeof assetInfo>,
  state: Pick<WeaponStudioState, 'selectedAnimation' | 'selectedAttackDirection'>,
): NormalizedWeaponAnimationDocument {
  return state.selectedAnimation === 'attack'
    ? normalizedWeaponAnimation(directionalAttack(weapon, info, state.selectedAttackDirection).animation)
    : normalizedWeaponAnimation(weaponAnimations(weapon, info)[state.selectedAnimation]);
}

function selectedAnimationFieldPath(state: Pick<WeaponStudioState, 'selectedAnimation' | 'selectedAttackDirection'>): string {
  return state.selectedAnimation === 'attack'
    ? `directionalAttacks.${state.selectedAttackDirection}.animation`
    : `animations.${state.selectedAnimation}`;
}

function frameTransformAt(animation: WeaponAnimationDocument, position: number): Required<WeaponFrameTransformDocument> {
  const transform = animation.frameTransforms?.[String(position)];
  return {
    offset: transform?.offset ?? [0, 0],
    scale: transform?.scale ?? [1, 1],
    rotationDeg: transform?.rotationDeg ?? 0,
  };
}

function ensureDirectionalAttackDraft(
  draft: MutableWeaponDraft,
  info: ReturnType<typeof assetInfo>,
  direction: WeaponAttackDirection,
): MutableDirectionalAttack {
  draft.directionalAttacks ??= {};
  if (direction === 'right' && !draft.directionalAttacks.right && draft.directionalAttacks.side) {
    draft.directionalAttacks.right = clone(draft.directionalAttacks.side);
    delete draft.directionalAttacks.side;
  }
  const existing = draft.directionalAttacks[direction];
  if (existing) return existing;
  const resolved = directionalAttack(draft, info, direction);
  const created = clone(resolved) as MutableDirectionalAttack;
  draft.directionalAttacks[direction] = created;
  return created;
}

function writeSelectedAnimation(
  draft: MutableWeaponDraft,
  info: ReturnType<typeof assetInfo>,
  state: Pick<WeaponStudioState, 'selectedAnimation' | 'selectedAttackDirection'>,
  animation: WeaponAnimationDocument,
): void {
  if (state.selectedAnimation === 'attack') {
    ensureDirectionalAttackDraft(draft, info, state.selectedAttackDirection).animation = clone(animation) as MutableWeaponAnimation;
    return;
  }
  const animations = weaponAnimations(draft, info);
  draft.animations = { ...animations, [state.selectedAnimation]: animation };
}

function remapFrameTransforms(
  transforms: WeaponAnimationDocument['frameTransforms'],
  newToOldPositions: readonly number[],
): WeaponAnimationDocument['frameTransforms'] {
  const remapped = Object.fromEntries(newToOldPositions.flatMap((oldPosition, newPosition) => {
    const transform = oldPosition >= 0 ? transforms?.[String(oldPosition)] : undefined;
    return transform ? [[String(newPosition), clone(transform)] as const] : [];
  }));
  return Object.keys(remapped).length > 0 ? remapped : undefined;
}

function weaponPreviewTransformStyle(
  weapon: WeaponDefinition,
  info: ReturnType<typeof assetInfo>,
  animationId: WeaponAnimationId,
  position: number,
  direction: WeaponAttackDirection,
): string {
  const animation = selectedWeaponAnimation(weapon, info, { selectedAnimation: animationId, selectedAttackDirection: direction });
  const transform = frameTransformAt(animation, position);
  const mirroredLeft = animationId === 'attack' && direction === 'left' && isMirroredLeft(weapon);
  const baseScale = weapon.visual?.scale ?? [1, 1];
  const scale = [baseScale[0] * transform.scale[0], baseScale[1] * transform.scale[1]] as const;
  const origin = weapon.visual?.origin ?? [0.5, 0.5];
  const animationOffsetKey = animationId === 'attack' ? `attack-${mirroredLeft ? 'right' : direction}` : animationId;
  const baseOffset = weapon.visual?.animationOffsets?.[animationOffsetKey]
    ?? (animationId === 'attack' ? weapon.visual?.animationOffsets?.attack : undefined)
    ?? weapon.visual?.sourceOffset
    ?? [0, 0];
  const offset = [baseOffset[0] + transform.offset[0], baseOffset[1] + transform.offset[1]] as const;
  const previewScaleX = scale[0] * 2.8;
  const previewScaleY = scale[1] * 2.8;
  return `--preview-scale-x:${previewScaleX};--preview-scale-y:${previewScaleY};--origin-offset-x:${-origin[0] * info.width * previewScaleX}px;--origin-offset-y:${-origin[1] * info.height * previewScaleY}px;--offset-x:${offset[0] * baseScale[0] * 2.8 * (mirroredLeft ? -1 : 1)}px;--offset-y:${offset[1] * baseScale[1] * 2.8}px;--weapon-rotation:${transform.rotationDeg}deg;--weapon-flip-x:${mirroredLeft ? -1 : 1}`;
}

function renderWeaponFrameTile(entry: CharacterStudioAssetEntry | undefined, frame: number, inAnimation: boolean, disabled = false): string {
  const info = assetInfo(entry);
  const column = frame % info.columns;
  const row = Math.floor(frame / info.columns);
  return `<button type="button" class="studio-frame-tile${inAnimation ? ' is-in-clip' : ''}" data-weapon-source-frame="${frame}" title="${disabled ? 'LEFT is mirroring RIGHT' : `Add source tile ${frame} to the animation`}" ${disabled ? 'disabled' : ''}><span class="studio-frame-image" style="--thumb-w:${info.width}px;--thumb-h:${info.height}px;--sheet-thumb-w:${info.width * info.columns}px;--sheet-thumb-h:${info.height * info.rows}px;--sheet-offset-x:${-column * info.width}px;--sheet-offset-y:${-row * info.height}px"><img src="${escapeHtml(info.url)}" alt="" aria-hidden="true" draggable="false" /></span><small>${frame}</small></button>`;
}

function renderAnimationTile(
  entry: CharacterStudioAssetEntry | undefined,
  keyframe: AnimationTimelineKeyframeView,
  selected: boolean,
  transformed: boolean,
  disabled = false,
): string {
  const frame = keyframe.sourceFrame;
  const position = keyframe.index;
  const info = assetInfo(entry);
  const column = frame % info.columns;
  const row = Math.floor(frame / info.columns);
  return `<div draggable="${!disabled}" class="timeline-frame${selected ? ' is-selected' : ''}${transformed ? ' is-transformed' : ''}" style="grid-column:${keyframe.gridColumnStart} / span ${keyframe.gridColumnSpan}" data-weapon-animation-position="${position}" data-timeline-index="${position}" title="${escapeHtml(keyframe.tooltip)}${disabled ? ' Mirrored from RIGHT.' : ' Ctrl-click for multi-select; drag to reorder.'}" aria-disabled="${disabled}"><button type="button" class="timeline-frame-select" aria-label="Select keyframe ${keyframe.indexLabel}" ${disabled ? 'disabled' : ''}>${renderTimelineKeyframeTimingLabels(keyframe)}<span class="timeline-frame-source">SRC ${frame}</span><span class="studio-frame-image" style="--thumb-w:${info.width}px;--thumb-h:${info.height}px;--sheet-thumb-w:${info.width * info.columns}px;--sheet-thumb-h:${info.height * info.rows}px;--sheet-offset-x:${-column * info.width}px;--sheet-offset-y:${-row * info.height}px"><img src="${escapeHtml(info.url)}" alt="" aria-hidden="true" draggable="false" /></span></button>${renderTimelineHoldControls(position, keyframe.hold, disabled)}${renderTimelineResizeHandle(keyframe, disabled)}<i aria-hidden="true"></i></div>`;
}

function renderDirectionTabs(weapon: WeaponDefinition, info: ReturnType<typeof assetInfo>, state: WeaponStudioState): string {
  if (state.selectedAnimation !== 'attack') return '';
  const renderTab = (direction: WeaponAttackDirection): string => {
    const attack = directionalAttack(weapon, info, direction);
    const authored = direction === 'right'
      ? weapon.directionalAttacks?.right !== undefined || weapon.directionalAttacks?.side !== undefined
      : weapon.directionalAttacks?.[direction] !== undefined;
    const status = direction === 'left' && isMirroredLeft(weapon) ? 'MIRROR RIGHT' : authored ? 'CUSTOM' : 'FALLBACK';
    return `<button type="button" role="tab" aria-selected="${direction === state.selectedAttackDirection}" class="weapon-direction-tab${direction === state.selectedAttackDirection ? ' is-active' : ''}${direction === 'left' && isMirroredLeft(weapon) ? ' is-mirrored' : ''}" data-weapon-attack-direction="${direction}"><span>${direction.toUpperCase()}</span><small>${attack.animation.frames.length}F · ${status}</small></button>`;
  };
  return `<div class="weapon-direction-tabs" role="tablist" aria-label="Attack direction"><section><div class="weapon-direction-group-label"><b>SIDE</b><small>RIGHT master + LEFT mirror/custom</small></div><div>${renderTab('right')}${renderTab('left')}</div></section><section><div class="weapon-direction-group-label"><b>VERTICAL</b><small>independent authored views</small></div><div>${renderTab('up')}${renderTab('down')}</div></section></div>`;
}

function renderLeftMirrorControl(weapon: WeaponDefinition, state: WeaponStudioState): string {
  if (state.selectedAnimation !== 'attack' || state.selectedAttackDirection !== 'left') return '';
  const mirrored = isMirroredLeft(weapon);
  return `<section class="weapon-left-mode${mirrored ? ' is-mirrored' : ' is-custom'}"><span class="weapon-left-mode-icon">${mirrored ? '⇄' : '◇'}</span><span><strong>${mirrored ? 'LEFT mirrors RIGHT' : 'Custom LEFT package'}</strong><small>${mirrored ? 'Artwork, tile transforms, action, timing, and hitboxes are derived safely from RIGHT.' : 'LEFT now owns independent tiles, transforms, character action, timing, and hitboxes.'}</small></span><button type="button" class="studio-button ${mirrored ? 'studio-button--save' : 'studio-button--quiet'}" data-action="${mirrored ? 'create-custom-left' : 'restore-mirrored-left'}">${mirrored ? 'MAKE CUSTOM LEFT' : 'RESTORE RIGHT MIRROR'}</button></section>`;
}

function renderDirectionalCharacterActionField(state: WeaponStudioState): string {
  const weapon = state.draft ?? makeNewWeapon();
  const character = previewCharacter(state.selectedCharacterId);
  const selected = resolvedCharacterAction(character, weapon, state.selectedAttackDirection);
  const options = characterActions(character).map((actionId) => `<option value="${escapeHtml(actionId)}" ${actionId === selected ? 'selected' : ''}>${escapeHtml(actionId.replaceAll('-', ' '))}</option>`).join('');
  const locked = state.selectedAttackDirection === 'left' && isMirroredLeft(weapon);
  return `<label class="studio-field weapon-direction-action"><span>${state.selectedAttackDirection.toUpperCase()} character action<small>${locked ? 'inherited from RIGHT while mirror is active' : 'body clip paired with this weapon direction'}</small></span><select data-weapon-field="directionalAttacks.${state.selectedAttackDirection}.characterActionId" ${locked ? 'disabled' : ''}>${options || '<option value="trick">trick</option>'}</select></label>`;
}

function renderFrameTransformEditor(weapon: WeaponDefinition, animation: WeaponAnimationDocument, state: WeaponStudioState): string {
  const positions = state.selectedAnimationPositions.filter((position) => position >= 0 && position < animation.frames.length);
  const selected = positions.length > 0 ? positions : [Math.min(state.previewStep, Math.max(0, animation.frames.length - 1))];
  const primary = selected[selected.length - 1] ?? 0;
  const transform = frameTransformAt(animation, primary);
  const locked = state.selectedAnimation === 'attack' && state.selectedAttackDirection === 'left' && isMirroredLeft(weapon);
  const selectionLabel = selected.length === 1 ? `POSITION ${primary + 1}` : `${selected.length} POSITIONS`;
  const transformField = (label: string, property: string, value: number, unit: string, step: string): string => `<label class="studio-field"><span>${label}<small>${unit}</small></span><input type="number" step="${step}" inputmode="decimal" value="${escapeHtml(value)}" data-weapon-transform-field="${property}" ${locked ? 'disabled' : ''}/></label>`;
  return `<section class="weapon-frame-transform${locked ? ' is-locked' : ''}"><div class="studio-section-bar"><div><span class="studio-kicker">Tile transform</span><strong>${selectionLabel}</strong></div><span class="studio-muted">${locked ? 'Mirrored from RIGHT' : 'Edits apply only to selected animation occurrences'}</span></div><div class="weapon-transform-toolbar" role="toolbar" aria-label="Direct manipulation tool">${(['move', 'scale', 'rotate'] as const).map((tool) => `<button type="button" class="studio-button studio-button--quiet${state.transformTool === tool ? ' is-active' : ''}" data-weapon-transform-tool="${tool}" ${locked ? 'disabled' : ''}>${tool.toUpperCase()}</button>`).join('')}<label class="weapon-onion-toggle"><input type="checkbox" data-weapon-onion-skin ${state.onionSkin ? 'checked' : ''}/><span>ONION SKIN</span></label><button type="button" class="studio-button studio-button--quiet" data-action="reset-weapon-tile-transform" ${locked ? 'disabled' : ''}>RESET TILE</button><button type="button" class="studio-link-button" data-action="show-weapon-visual-controls">GLOBAL SCALE →</button></div><div class="studio-field-grid weapon-transform-fields">${transformField('Offset X', 'offset.0', transform.offset[0], 'source pixels', '0.25')}${transformField('Offset Y', 'offset.1', transform.offset[1], 'source pixels', '0.25')}${transformField('Scale X', 'scale.0', transform.scale[0], 'tile multiplier', '0.05')}${transformField('Scale Y', 'scale.1', transform.scale[1], 'tile multiplier', '0.05')}${transformField('Rotation', 'rotationDeg', transform.rotationDeg, 'degrees', '1')}</div><p class="studio-help">${locked ? 'Create a Custom LEFT package before moving, scaling, or rotating these tiles.' : 'Drag the weapon in the preview using the active tool.'} Global weapon scale remains in <b>Inspector → Visual</b>.</p></section>`;
}

function field(label: string, path: string, value: unknown, unit: string, step = '1', constraints = ''): string {
  const displayValue = step === '1' ? integerValue(value) : (Number.isFinite(Number(value)) ? Number(value) : 1);
  const resolvedConstraints = path.startsWith('visual.scale.') ? 'min="0.05" max="8"' : constraints;
  return `<label class="studio-field"><span>${label}<small>${unit}</small></span><input type="number" step="${step}" inputmode="decimal" value="${escapeHtml(displayValue)}" ${resolvedConstraints} data-weapon-field="${path}" /></label>`;
}

function compactScalingField(label: string, path: string, value: unknown): string {
  const displayValue = Number.isFinite(Number(value)) ? Number(value) : 0;
  return `<label class="studio-field weapon-scaling-field"><span>${label}<small>coefficient</small></span><input type="number" step="0.05" inputmode="decimal" value="${escapeHtml(displayValue)}" data-weapon-field="${path}" /></label>`;
}

function arcWidthField(path: string, radians: number): string {
  const degrees = Math.round(radians * 1800 / Math.PI) / 10;
  return field('Arc width', path, degrees, 'degrees', '1', 'min="0" max="360"')
    .replace('class="studio-field"', 'class="studio-field weapon-hitbox-arc-field"');
}

function applyWeaponHitboxShape(hitbox: MutableWeaponHitbox, shape: WeaponHitboxShape): void {
  hitbox.shape = shape;
  if (shape === 'circle') {
    hitbox.radius ??= Math.max(1, Math.min(hitbox.width, hitbox.height) / 2);
    delete hitbox.radiusX;
    delete hitbox.radiusY;
    return;
  }
  if (shape === 'ellipse') {
    hitbox.radiusX ??= Math.max(1, hitbox.radius ?? hitbox.width / 2);
    hitbox.radiusY ??= Math.max(1, hitbox.radius ?? hitbox.height / 2);
    delete hitbox.radius;
    return;
  }
  if (shape === 'sector') {
    hitbox.innerRadius ??= 0;
    hitbox.outerRadius ??= Math.max(1, hitbox.offsetX + hitbox.width / 2);
    hitbox.arcWidthRad ??= 1.35;
  }
}

function renderWeaponCombatProfile(weapon: WeaponDefinition): string {
  return `<section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Combat profile</span><strong>Base behavior</strong></div><div class="studio-field-grid">${field('Base damage', 'baseDamage', weapon.baseDamage, 'points')}${field('Cooldown', 'cooldownMs', weapon.cooldownMs, 'milliseconds')}${field('Knockback', 'knockStrength', weapon.knockStrength, 'world units/s')}${field('Unlock level', 'unlockLevel', weapon.unlockLevel, 'level', '1')}</div><div class="weapon-combat-ownership"><strong>Collision is directional</strong><span>Shape and position live in Hitboxes. Active time lives in the attack event track.</span></div></section>`;
}

function renderWeaponScaling(scaling: WeaponDefinition['scaling']): string {
  return `<section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Attribute scaling</span><strong>Final value modifiers</strong></div><p class="studio-help">Coefficients resolve around attribute 10.</p><div class="weapon-scaling-compact"><div class="weapon-scaling-group weapon-scaling-group--damage"><strong>Damage</strong><div class="weapon-scaling-fields">${compactScalingField('STR', 'scaling.damage.strength', scaling?.damage?.strength ?? 0)}${compactScalingField('AGI', 'scaling.damage.agility', scaling?.damage?.agility ?? 0)}${compactScalingField('INT', 'scaling.damage.intellect', scaling?.damage?.intellect ?? 0)}</div></div><div class="weapon-scaling-secondary"><div class="weapon-scaling-group"><strong>Cooldown</strong><div class="weapon-scaling-fields">${compactScalingField('AGI', 'scaling.cooldown.agility', scaling?.cooldown?.agility ?? 0)}</div></div><div class="weapon-scaling-group"><strong>Knockback</strong><div class="weapon-scaling-fields">${compactScalingField('STR', 'scaling.knockback.strength', scaling?.knockback?.strength ?? 0)}</div></div></div></div></section>`;
}

function makeNewWeapon(): WeaponDefinition {
  const animations = defaultWeaponAnimations(assetInfo(undefined));
  const attackTrack = { hitboxSpans: [{ hitboxId: 'primary', from: 0, through: 0 }], events: [] } as const;
  return {
    version: 1,
    weaponId: 'new-weapon',
    displayName: 'New Weapon',
    category: 'melee',
    characterActionId: 'trick',
    animations,
    directionalAttacks: {
      right: { animation: animations.attack, characterActionId: 'trick', attackTrack },
      up: { animation: animations.attack, characterActionId: 'trick', attackTrack },
      down: { animation: animations.attack, characterActionId: 'trick', attackTrack },
    },
    visual: { sourceOffset: [0, 0] },
    hitboxes: {
      primary: { shape: 'sector', width: 32, height: 18, offsetX: 24, offsetY: 0, outerRadius: 33, arcWidthRad: 1.35 },
    },
    attackTrack,
    baseDamage: 10,
    cooldownMs: 500,
    hitboxWidth: 32,
    hitboxHeight: 18,
    hitboxOffset: 24,
    hitboxDurationMs: 120,
    knockStrength: 120,
    scaling: { damage: { strength: 0.5 }, cooldown: { agility: 0.25 }, knockback: { strength: 0.25 } },
    vfxColor: 0x86f0c3,
    unlockLevel: 1,
    iconKey: 'weapon-generic',
    description: 'A reusable weapon definition.',
  };
}

function renderWeaponVisualFieldsBase(weapon: WeaponDefinition): string {
  const offset = weapon.visual?.sourceOffset ?? [0, 0];
  const animationOffset = weapon.visual?.animationOffsets?.attack ?? [0, 0];
  const scale = weapon.visual?.scale ?? [1, 1];
  return `<section class="studio-inspector-section" data-weapon-visual><div class="studio-section-heading"><span class="studio-kicker">Visual</span><strong>Attachment alignment</strong></div><p class="studio-help">The weapon layer follows the character’s existing anchor. Offsets are art alignment only; hitboxes stay in their own authored coordinates.</p><div class="studio-field-grid">${field('Default X', 'visual.sourceOffset.0', offset[0], 'source pixels')}${field('Default Y', 'visual.sourceOffset.1', offset[1], 'source pixels')}${field('Scale X', 'visual.scale.0', scale[0], 'multiplier', '0.05')}${field('Scale Y', 'visual.scale.1', scale[1], 'multiplier', '0.05')}</div><div class="studio-subheading">Attack clip override</div><div class="studio-field-grid">${field('Attack X', 'visual.animationOffsets.attack.0', animationOffset[0], 'source pixels')}${field('Attack Y', 'visual.animationOffsets.attack.1', animationOffset[1], 'source pixels')}</div><label class="studio-field studio-field--wide"><span>Facing mode<small>attachment rotation</small></span><select data-weapon-field="visual.facingMode"><option value="vector" ${(weapon.visual?.facingMode ?? 'vector') === 'vector' ? 'selected' : ''}>Vector rotate</option><option value="horizontal-flip" ${weapon.visual?.facingMode === 'horizontal-flip' ? 'selected' : ''}>Horizontal flip</option></select></label></section>`;
}

function renderWeaponVisualFields(weapon: WeaponDefinition): string {
  return renderWeaponVisualFieldsBase(weapon)
    .replace('data-weapon-visual', 'data-weapon-inspector-group="visual" data-weapon-visual')
    .replace('Attachment alignment', 'Weapon layer transform')
    .replace('Offsets are art alignment only;', 'Weapon offsets move artwork from the player anchor;')
    .replace('Default X', 'Weapon offset X')
    .replace('Default Y', 'Weapon offset Y')
    .replace('Scale X', 'Weapon scale X')
    .replace('Scale Y', 'Weapon scale Y')
    .replace('Attack X', 'Attack offset X')
    .replace('Attack Y', 'Attack offset Y')
    .replace('<label class="studio-field studio-field--wide"><span>Facing mode', '<div class="studio-transform-note"><span class="studio-transform-note-mark">+</span><span><strong>Offset origin: player anchor</strong><small>Positive X follows the facing direction. The character body and hitboxes stay fixed.</small></span></div><label class="studio-field studio-field--wide"><span>Facing mode');
}

function renderWeaponHitboxEditor(weapon: WeaponDefinition, state: WeaponStudioState): string {
  const direction = state.selectedAnimation === 'attack' ? state.selectedAttackDirection : undefined;
  const locked = direction === 'left' && isMirroredLeft(weapon);
  const hitboxes = weaponHitboxes(weapon, direction);
  const pathPrefix = direction ? `directionalAttacks.${direction}.hitboxes` : 'hitboxes';
  const selectedHitboxId = resolvedSelectedHitboxId(hitboxes, state.selectedHitboxId);
  const selector = Object.entries(hitboxes).map(([hitboxId, hitbox]) => `<button type="button" role="tab" aria-selected="${hitboxId === selectedHitboxId}" class="weapon-hitbox-selector-tab${hitboxId === selectedHitboxId ? ' is-active' : ''}" data-select-weapon-hitbox="${escapeHtml(hitboxId)}"><strong>${escapeHtml(hitboxId)}</strong><small>${hitbox.shape.toUpperCase()}</small></button>`).join('');
  const selectedEntry = selectedHitboxId ? [selectedHitboxId, hitboxes[selectedHitboxId]] as const : undefined;
  const rows = selectedEntry ? [selectedEntry].map(([hitboxId, hitbox]) => {
    const shape = hitbox.shape;
    const geometryFields = shape === 'sector'
      ? `${field('Inner radius', `${pathPrefix}.${hitboxId}.innerRadius`, hitbox.innerRadius ?? 0, 'near edge', '1', 'min="0"')}${field('Outer radius', `${pathPrefix}.${hitboxId}.outerRadius`, hitbox.outerRadius ?? hitbox.offsetX + hitbox.width / 2, 'reach', '1', 'min="1"')}${arcWidthField(`${pathPrefix}.${hitboxId}.arcWidthRad`, hitbox.arcWidthRad ?? 1.35)}${field('Offset X', `${pathPrefix}.${hitboxId}.offsetX`, hitbox.offsetX, 'forward')}${field('Offset Y', `${pathPrefix}.${hitboxId}.offsetY`, hitbox.offsetY, 'side axis')}<p class="weapon-hitbox-geometry-note">Offset moves the sector origin from the player anchor. Direction aims the sector; inner radius leaves a safe gap near the body.</p>`
      : shape === 'circle'
        ? `${field('Radius', `${pathPrefix}.${hitboxId}.radius`, hitbox.radius ?? hitbox.width / 2, 'world units', '1', 'min="1"')}${field('Offset X', `${pathPrefix}.${hitboxId}.offsetX`, hitbox.offsetX, 'forward')}${field('Offset Y', `${pathPrefix}.${hitboxId}.offsetY`, hitbox.offsetY, 'side axis')}`
        : shape === 'ellipse'
          ? `${field('Radius X', `${pathPrefix}.${hitboxId}.radiusX`, hitbox.radiusX ?? hitbox.width / 2, 'world units', '1', 'min="1"')}${field('Radius Y', `${pathPrefix}.${hitboxId}.radiusY`, hitbox.radiusY ?? hitbox.height / 2, 'world units', '1', 'min="1"')}${field('Offset X', `${pathPrefix}.${hitboxId}.offsetX`, hitbox.offsetX, 'forward')}${field('Offset Y', `${pathPrefix}.${hitboxId}.offsetY`, hitbox.offsetY, 'side axis')}`
          : `${field('Width', `${pathPrefix}.${hitboxId}.width`, hitbox.width, 'world units', '1', 'min="1"')}${field('Height', `${pathPrefix}.${hitboxId}.height`, hitbox.height, 'world units', '1', 'min="1"')}${field('Offset X', `${pathPrefix}.${hitboxId}.offsetX`, hitbox.offsetX, 'forward')}${field('Offset Y', `${pathPrefix}.${hitboxId}.offsetY`, hitbox.offsetY, 'side axis')}`;
    return `<fieldset class="studio-hitbox-row studio-hitbox-row--expanded weapon-hitbox-card" data-weapon-hitbox-editor-id="${escapeHtml(hitboxId)}" ${locked ? 'disabled' : ''}><div class="studio-hitbox-row-heading"><span class="hitbox-chip">Editing ${escapeHtml(hitboxId)}</span><button type="button" class="studio-icon-button is-danger" data-remove-weapon-hitbox="${escapeHtml(hitboxId)}" aria-label="Delete ${escapeHtml(hitboxId)}">×</button></div><div class="weapon-hitbox-geometry-grid is-${shape}"><label class="studio-field studio-field--shape"><span>Shape<small>collision primitive</small></span><select data-weapon-field="${pathPrefix}.${hitboxId}.shape"><option value="rectangle" ${shape === 'rectangle' ? 'selected' : ''}>Rectangle</option><option value="circle" ${shape === 'circle' ? 'selected' : ''}>Circle</option><option value="ellipse" ${shape === 'ellipse' ? 'selected' : ''}>Ellipse</option><option value="sector" ${shape === 'sector' ? 'selected' : ''}>Sector</option></select></label>${geometryFields}</div><div class="weapon-hitbox-effects-grid">${field('Damage ×', `${pathPrefix}.${hitboxId}.damageMultiplier`, hitbox.damageMultiplier ?? 1, 'multiplier', '0.05')}${field('Knockback ×', `${pathPrefix}.${hitboxId}.knockbackMultiplier`, hitbox.knockbackMultiplier ?? 1, 'multiplier', '0.05')}</div></fieldset>`;
  }).join('') : '';
  return `<section class="studio-inspector-section studio-weapon-hitbox-section${locked ? ' is-locked' : ''}"><div class="studio-section-heading"><span class="studio-kicker">Hitboxes</span><strong>${direction ? `${direction.toUpperCase()} attack geometry` : 'Named attack geometry'}</strong><button type="button" class="studio-icon-button" data-action="add-weapon-hitbox" aria-label="Add hitbox" ${locked ? 'disabled' : ''}>+</button></div><p class="studio-help">${locked ? 'LEFT hitboxes are mirrored from RIGHT. Create Custom LEFT to edit them independently.' : 'Select a hitbox here or click its label in the preview. Active time is authored in the attack event track.'}</p>${selector ? `<div class="weapon-hitbox-selector" role="tablist" aria-label="Weapon hitboxes">${selector}</div>` : ''}${rows || '<p class="studio-empty-note">Add a named hitbox to author weapon contact geometry.</p>'}</section>`;
}

function renderWeaponTrackEditor(weapon: WeaponDefinition, direction: WeaponAttackDirection, locked = false): string {
  const preview = resolveWeaponHitboxPreview(weapon, direction);
  const hitboxes = preview.attack.hitboxes;
  const track = preview.track;
  const timelineView = createAnimationTimelineView({
    frames: [0],
    keyframeTimes: [0],
    durationSeconds: preview.attack.animation.durationSeconds,
    framesPerSecond: preview.attack.animation.framesPerSecond,
    loop: false,
    loopMode: 'wrap',
  });
  const timelineFrames = timelineView.timelineFrames;
  const timeline = Array.from({ length: timelineFrames }, (_, index) => index);
  const cells = (hitboxId: string): string => timeline.map((index) => `<button type="button" class="timeline-cell${track.hitboxSpans.some((span) => span.hitboxId === hitboxId && span.from <= index && index <= span.through) ? ' is-hot' : ''}" data-weapon-span-toggle="${escapeHtml(hitboxId)}" data-weapon-span-frame="${index}" aria-label="${escapeHtml(hitboxId)} timeline frame ${index}" ${locked ? 'disabled' : ''}></button>`).join('');
  const eventInputs = timeline.map((index) => {
    const event = track.events?.find((candidate) => candidate.at === index);
    const timeLabel = `${formatAnimationTimelineSeconds(index / timelineView.framesPerSecond, timelineView.framesPerSecond)}s`;
    return `<label class="weapon-event-cell" title="Time ${timeLabel}, frame ${index}"><span>@${timeLabel}</span><input type="text" value="${escapeHtml(event?.eventId ?? '')}" placeholder="event" data-weapon-event-frame="${index}" ${locked ? 'disabled' : ''}/></label>`;
  }).join('');
  return `<section class="studio-timeline-panel studio-track-editor" data-weapon-attack-scope="${direction}"><div class="studio-section-bar"><div><span class="studio-kicker">${weaponAttackTrackScopeLabel(direction)}</span><strong>Hitbox activation windows</strong></div><span class="studio-muted">${timelineView.effectiveDurationSeconds.toFixed(timelineView.secondsPrecision)}s / ${timelineFrames}F · click cells to toggle inclusive windows</span></div><div class="studio-timeline" style="--timeline-frame-count:${timelineFrames}">${renderAnimationTimelineRuler(timelineView)}${Object.keys(hitboxes).map((hitboxId) => `<div class="timeline-track-row"><span class="timeline-track-label" title="${escapeHtml(hitboxId)}">${escapeHtml(hitboxId)}</span>${cells(hitboxId)}</div>`).join('')}<div class="timeline-track-row timeline-event-row"><span class="timeline-track-label">EVENTS</span>${eventInputs}</div></div><p class="studio-help">Events are stable IDs such as <code>weapon.impact</code>. The runtime receives them at the exact timeline time.</p></section>`;
}

function renderWeaponPreview(
  weapon: WeaponDefinition,
  info: ReturnType<typeof assetInfo>,
  state: WeaponStudioState,
  character: StudioCharacterPackage | undefined,
  characterInfo: ReturnType<typeof assetInfo>,
): string {
  const animationId = state.selectedAnimation;
  const animation = selectedWeaponAnimation(weapon, info, state);
  const expanded = normalizeAnimationClip(animation);
  const position = Math.min(state.previewStep, Math.max(0, timelineFrameCount(expanded) - 1));
  if (!character) return renderWeaponPreviewLegacy(weapon, info, animationId, position, state.selectedAttackDirection);
  const expandedPlayback = expandAnimationClip(expanded);
  const weaponFrame = expandedPlayback.sourceFrames[position] ?? 0;
  const weaponColumn = weaponFrame % info.columns;
  const weaponRow = Math.floor(weaponFrame / info.columns);
  const actionDirection = animationId === 'attack' ? state.selectedAttackDirection : undefined;
  const lockedMirror = actionDirection === 'left' && isMirroredLeft(weapon);
  const characterAction = characterClip(character, resolvedCharacterAction(character, weapon, actionDirection));
  const characterFrame = characterAction?.frames[position % Math.max(1, characterAction.frames.length)] ?? 0;
  const characterColumn = characterFrame % characterInfo.columns;
  const characterRow = Math.floor(characterFrame / characterInfo.columns);
  const characterVisual = character?.visualSet;
  const characterFrameVisual = characterVisual?.frameVisuals?.[String(characterFrame)] ?? {};
  const characterSourceOffset = characterFrameVisual.sourceOffset ?? characterVisual?.defaults.sourceOffset ?? [0, 0];
  const characterScale = (characterFrameVisual.scale ?? characterVisual?.defaults.scale ?? [1, 1])[0] * 2.8;
  const characterOrigin = characterFrameVisual.origin ?? characterVisual?.defaults.origin ?? [0.5, 0.5];
  const characterSprite = characterInfo.url ? `<span class="stage-sprite stage-character-sprite" style="--sheet-url:url('${escapeHtml(characterInfo.url)}');--frame-w:${characterInfo.width}px;--frame-h:${characterInfo.height}px;--sheet-w:${characterInfo.width * characterInfo.columns}px;--sheet-h:${characterInfo.height * characterInfo.rows}px;--frame-x:${characterColumn * characterInfo.width}px;--frame-y:${characterRow * characterInfo.height}px;--preview-scale:${characterScale};--origin-offset-x:${-characterOrigin[0] * characterInfo.width * characterScale}px;--origin-offset-y:${-characterOrigin[1] * characterInfo.height * characterScale}px;--offset-x:${characterSourceOffset[0] * characterScale}px;--offset-y:${characterSourceOffset[1] * characterScale}px"></span>` : '<span class="stage-character-fallback">CHARACTER</span>';
  const spriteStyle = `--sheet-url:url('${escapeHtml(info.url)}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:${weaponColumn * info.width}px;--frame-y:${weaponRow * info.height}px;${weaponPreviewTransformStyle(weapon, info, animationId, expandedPlayback.occurrenceIndices[position] ?? 0, state.selectedAttackDirection)}`;
  const weaponSprite = info.url ? `<span class="stage-sprite stage-weapon-sprite is-tool-${state.transformTool}${lockedMirror ? ' is-mirror-locked' : ''}" ${lockedMirror ? '' : 'data-weapon-preview-transform'} style="${spriteStyle}"></span>` : '<span class="weapon-preview-effect"></span>';
  const previousPosition = Math.max(0, position - 1);
  const previousFrame = expandedPlayback.sourceFrames[previousPosition] ?? weaponFrame;
  const onionSprite = state.onionSkin && info.url && position > 0
    ? `<span class="stage-sprite stage-weapon-sprite weapon-onion-sprite" aria-hidden="true" style="--sheet-url:url('${escapeHtml(info.url)}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:${(previousFrame % info.columns) * info.width}px;--frame-y:${Math.floor(previousFrame / info.columns) * info.height}px;${weaponPreviewTransformStyle(weapon, info, animationId, expandedPlayback.occurrenceIndices[previousPosition] ?? 0, state.selectedAttackDirection)}"></span>`
    : '';
  const length = expandedPlayback.timelineFrameCount;
  const timeLabel = `${formatAnimationTimelineSeconds(position / expanded.framesPerSecond, expanded.framesPerSecond)}s`;
  const durationLabel = `${formatAnimationTimelineSeconds(length / expanded.framesPerSecond, expanded.framesPerSecond)}s`;
  const hitboxGuides = actionDirection
    ? `<span class="weapon-hitbox-guides" data-weapon-hitbox-guides>${renderWeaponHitboxGuides(weapon, position, actionDirection, state.selectedHitboxId)}</span>`
    : '';
  return `<section class="studio-preview-card weapon-preview-card"><div class="studio-preview-toolbar"><span class="studio-kicker">COMBINED PREVIEW</span><span class="studio-muted">${animationId.toUpperCase()}${animationId === 'attack' ? ` / ${state.selectedAttackDirection.toUpperCase()}` : ''} · time ${timeLabel}/${durationLabel} · ${escapeHtml(character?.character.displayName ?? 'character')} + weapon</span><button type="button" class="studio-button studio-button--quiet" data-action="play-weapon-preview">${state.previewPlaying ? '■ STOP' : '▶ PLAY'}</button></div><div class="studio-stage weapon-stage is-transform-${state.transformTool}"><span class="stage-axis stage-axis-x"></span><span class="stage-axis stage-axis-y"></span><span class="stage-anchor">+</span><span class="stage-label">PLAYER ANCHOR</span>${characterSprite}${onionSprite}${weaponSprite}${hitboxGuides}<span class="stage-caption"><b>${escapeHtml(weapon.displayName)}</b><span>CHARACTER ACTION ${escapeHtml(characterAction?.id ?? weapon.characterActionId ?? 'trick')} · WEAPON TILE ${weaponFrame} · ${lockedMirror ? 'MIRROR RIGHT' : `${state.transformTool.toUpperCase()} TOOL`}</span></span></div><div class="studio-preview-footer"><span><i class="legend-dot legend-dot--cyan"></i> character layer</span><span><i class="legend-dot legend-dot--amber"></i> selected weapon tile</span><span><i class="legend-dot legend-dot--red"></i> named hitboxes</span><span>${lockedMirror ? 'LEFT is linked to RIGHT' : `Drag artwork to ${state.transformTool}`}</span></div></section>`;
}

function renderWeaponHitboxGuides(weapon: WeaponDefinition, position: number, direction: WeaponAttackDirection, requestedHitboxId: string): string {
  const preview = resolveWeaponHitboxPreview(weapon, direction);
  const selectedHitboxId = resolvedSelectedHitboxId(preview.attack.hitboxes, requestedHitboxId);
  return Object.entries(preview.attack.hitboxes).map(([hitboxId, hitbox], hitboxIndex) => {
    const geometry = resolveWeaponHitboxPreviewGeometry(hitbox, direction);
    const isActive = weaponHitboxIsActive(preview, hitboxId, position);
    const title = geometry.valid ? hitboxId : `${hitboxId}: ${geometry.invalidReason ?? 'Invalid geometry'}`;
    const classes = `stage-hitbox stage-hitbox--${geometry.shape}${isActive ? ' is-hot' : ''}${hitboxId === selectedHitboxId ? ' is-selected' : ''}${geometry.valid ? '' : ' is-invalid'}`;
    const selectButton = `<button type="button" class="stage-hitbox-select" style="--hitbox-label-index:${hitboxIndex}" data-select-weapon-hitbox="${escapeHtml(hitboxId)}" aria-label="Edit ${escapeHtml(hitboxId)}">${escapeHtml(hitboxId)}</button>`;
    if (!geometry.valid) {
      return `<span class="${classes}" data-weapon-hitbox-id="${escapeHtml(hitboxId)}" data-weapon-hitbox-invalid style="transform:translate(-50%,-50%)" title="${escapeHtml(title)}">${selectButton}</span>`;
    }
    const width = geometry.width * WEAPON_HITBOX_PREVIEW_SCALE;
    const height = geometry.height * WEAPON_HITBOX_PREVIEW_SCALE;
    const offsetX = geometry.centerX * WEAPON_HITBOX_PREVIEW_SCALE;
    const offsetY = geometry.centerY * WEAPON_HITBOX_PREVIEW_SCALE;
    const style = `width:${width}px;height:${height}px;transform:translate(-50%,-50%) translate(${offsetX}px,${offsetY}px)`;
    const shape = geometry.shape === 'sector'
      ? `<svg class="weapon-hitbox-sector" viewBox="${geometry.sectorViewBox}" aria-hidden="true"><path class="weapon-hitbox-sector-area" fill-rule="evenodd" d="${geometry.sectorAreaPath ?? ''}"></path>${geometry.sectorBoundaryPath ? `<path class="weapon-hitbox-sector-boundary" d="${geometry.sectorBoundaryPath}"></path>` : ''}</svg>`
      : '';
    return `<span class="${classes}" data-weapon-hitbox-id="${escapeHtml(hitboxId)}" style="${style}" title="${escapeHtml(title)}">${shape}${selectButton}</span>`;
  }).join('');
}

function renderWeaponPreviewLegacy(weapon: WeaponDefinition, info: ReturnType<typeof assetInfo>, animationId: WeaponAnimationId, position: number, direction: WeaponAttackDirection): string {
  const frame = selectedWeaponAnimation(weapon, info, { selectedAnimation: animationId, selectedAttackDirection: direction }).frames[position] ?? 0;
  const column = frame % info.columns;
  const row = Math.floor(frame / info.columns);
  const sprite = info.url ? `<span class="stage-sprite" style="--sheet-url:url('${escapeHtml(info.url)}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:${column * info.width}px;--frame-y:${row * info.height}px;${weaponPreviewTransformStyle(weapon, info, animationId, position, direction)}"></span>` : '<span class="weapon-preview-effect"></span>';
  return `<section class="studio-preview-card weapon-preview-card"><div class="studio-preview-toolbar"><span class="studio-kicker">WEAPON PREVIEW</span><span class="studio-muted">${animationId.toUpperCase()} · frame ${frame} · ${info.width} x ${info.height} px</span></div><div class="studio-stage weapon-stage"><span class="stage-axis stage-axis-x"></span><span class="stage-axis stage-axis-y"></span><span class="stage-anchor">+</span><span class="stage-label">CHARACTER ANCHOR</span><span class="stage-body" style="width:${weapon.hitboxWidth * 2}px;height:${weapon.hitboxHeight * 2}px;transform:translate(-50%,-50%) translate(${weapon.hitboxOffset * 2}px,0)" ></span>${sprite}<span class="stage-caption"><b>${escapeHtml(weapon.displayName)}</b><span>${weapon.hitboxWidth} WORLD UNITS · ${weapon.hitboxDurationMs} MS ACTIVE</span></span></div><div class="studio-preview-footer"><span><i class="legend-dot legend-dot--amber"></i> weapon artwork</span><span><i class="legend-dot legend-dot--red"></i> gameplay hitbox</span></div></section>`;
}

function renderWeaponAnimationPanel(weapon: WeaponDefinition, source: CharacterStudioAssetEntry | undefined, state: WeaponStudioState): string {
  const info = assetInfo(source);
  const animations = weaponAnimations(weapon, info);
  const animation = selectedWeaponAnimation(weapon, info, state);
  const timelineView = createAnimationTimelineView(animation);
  const fieldPath = selectedAnimationFieldPath(state);
  const selected = new Set(state.selectedAnimationPositions);
  const locked = state.selectedAnimation === 'attack' && state.selectedAttackDirection === 'left' && isMirroredLeft(weapon);
  const directionControls = state.selectedAnimation === 'attack'
    ? `${renderDirectionTabs(weapon, info, state)}${renderLeftMirrorControl(weapon, state)}${renderDirectionalCharacterActionField(state)}`
    : '';
  const trackEditor = state.selectedAnimation === 'attack'
    ? renderWeaponTrackEditor(weapon, state.selectedAttackDirection, locked)
    : '';
  const selectedPosition = state.selectedAnimationPositions.at(-1) ?? state.previewStep;
  const selectedKeyframe = timelineView.keyframes[selectedPosition] ?? timelineView.keyframes[0];
  const selectedSummary = selectedKeyframe
    ? `TIME ${selectedKeyframe.startTimeLabel} / START ${selectedKeyframe.startFrameLabel} / KEYFRAME ${selectedKeyframe.indexLabel} / SOURCE ${selectedKeyframe.sourceFrame}`
    : 'NO KEYFRAME SELECTED';
  const animationPanel = renderAnimationTimelinePanel({
    panelClassName: 'weapon-animation-panel',
    titleHtml: `Editing ${state.selectedAnimation}${state.selectedAnimation === 'attack' ? ` / ${state.selectedAttackDirection}` : ''}`,
    hint: 'Blocks show hold length · drag to reorder · source tiles via Add Tiles',
    addTilesAction: 'open-weapon-tile-picker',
    addTilesDisabled: locked,
    headerActionsHtml: `<button type="button" class="studio-button studio-button--quiet" data-action="distribute-weapon-tiles" ${locked ? 'disabled' : ''}>DISTRIBUTE EVENLY</button>`,
    clipTabsHtml: (['idle', 'attack', 'impact'] as const).map((id) => { const clip = id === 'attack' ? directionalAttack(weapon, info, state.selectedAttackDirection).animation : animations[id]; return `<button type="button" class="studio-clip-tab${id === state.selectedAnimation ? ' is-active' : ''}" data-weapon-animation-id="${id}"><span>${id.toUpperCase()}</span><small>${clip.frames.length}K · ${Number(clip.durationSeconds).toFixed(2)}s</small></button>`; }).join(''),
    contextControlsHtml: directionControls,
    timelineView,
    renderKeyframe: (keyframe) => renderAnimationTile(
      source,
      keyframe,
      selected.has(keyframe.index),
      animation.frameTransforms?.[String(keyframe.index)] !== undefined,
      locked,
    ),
    timelineLocked: locked,
    selectionHtml: `<div class="studio-timeline-selection"><span><b>${selectedSummary}</b></span><span><strong>SELECTED</strong> <span>${selected.size || 1}</span></span><span><strong>TIMELINE</strong> <span>${timelineView.effectiveDurationSeconds.toFixed(timelineView.secondsPrecision)}s / ${timelineView.timelineFrames}F</span></span></div>`,
    toolbarHtml: `<div class="weapon-sequence-toolbar"><button type="button" class="studio-button studio-button--quiet" data-action="move-weapon-tiles-left" ${locked ? 'disabled' : ''}>← LEFT</button><button type="button" class="studio-button studio-button--quiet" data-action="move-weapon-tiles-right" ${locked ? 'disabled' : ''}>RIGHT →</button><button type="button" class="studio-button studio-button--quiet" data-action="duplicate-weapon-tiles" ${locked ? 'disabled' : ''}>DUPLICATE</button><button type="button" class="studio-button studio-button--quiet is-danger" data-action="delete-weapon-tiles" ${animation.frames.length <= 1 || locked ? 'disabled' : ''}>DELETE KEYFRAME</button></div>`,
    playbackHtml: `<div class="studio-playback"><button type="button" class="studio-button studio-button--play${state.previewPlaying ? ' is-playing' : ''}" data-action="play-weapon-preview" aria-pressed="${state.previewPlaying}" title="${state.previewPlaying ? 'Stop animation playback' : 'Play animation'}">${state.previewPlaying ? '■ STOP ANIMATION' : '▶ PLAY ANIMATION'}</button><button type="button" class="studio-button studio-button--quiet" data-action="previous-weapon-frame" aria-label="Previous animation frame">‹</button><button type="button" class="studio-button studio-button--quiet" data-action="next-weapon-frame" aria-label="Next animation frame">›</button><label class="studio-inline-field">FPS <input type="number" min="1" max="240" step="1" inputmode="numeric" value="${integerValue(animation.framesPerSecond, 12)}" data-weapon-field="${fieldPath}.framesPerSecond" ${locked ? 'disabled' : ''}/></label><label class="studio-inline-field">DURATION <input type="number" min="0.01" max="60" step="0.01" inputmode="decimal" value="${Number(animation.durationSeconds).toFixed(2)}" data-weapon-field="${fieldPath}.durationSeconds" ${locked ? 'disabled' : ''}/></label><label class="studio-switch"><input type="checkbox" ${animation.loop ? 'checked' : ''} data-weapon-field="${fieldPath}.loop" ${locked ? 'disabled' : ''}/><span></span> LOOP</label></div>`,
  });
  return `${animationPanel}${renderFrameTransformEditor(weapon, animation, state)}${trackEditor}`;
}

function updateCombinedPreviewDom(
  container: HTMLDivElement,
  weapon: WeaponDefinition,
  state: WeaponStudioState,
  refreshHitboxGeometry = false,
): void {
  const source = state.assets?.assets.find((entry) => entry.assetId === weapon.assetId && isWeaponAsset(entry));
  const info = assetInfo(source);
  const animation = selectedWeaponAnimation(weapon, info, state);
  const expanded = expandAnimationClip(animation);
  const position = Math.min(Math.max(state.previewStep, 0), Math.max(0, expanded.timelineFrameCount - 1));
  const weaponFrame = expanded.sourceFrames[position] ?? 0;
  const weaponSprite = container.querySelector<HTMLElement>('.stage-weapon-sprite:not(.weapon-onion-sprite)');
  if (weaponSprite) {
    weaponSprite.style.setProperty('--frame-x', `${(weaponFrame % info.columns) * info.width}px`);
    weaponSprite.style.setProperty('--frame-y', `${Math.floor(weaponFrame / info.columns) * info.height}px`);
    const transform = frameTransformAt(animation, expanded.occurrenceIndices[position] ?? 0);
    const mirroredLeft = state.selectedAnimation === 'attack' && state.selectedAttackDirection === 'left' && isMirroredLeft(weapon);
    const baseScale = weapon.visual?.scale ?? [1, 1];
    const scale = [baseScale[0] * transform.scale[0], baseScale[1] * transform.scale[1]] as const;
    const origin = weapon.visual?.origin ?? [0.5, 0.5];
    const animationOffsetKey = state.selectedAnimation === 'attack' ? `attack-${mirroredLeft ? 'right' : state.selectedAttackDirection}` : state.selectedAnimation;
    const baseOffset = weapon.visual?.animationOffsets?.[animationOffsetKey]
      ?? (state.selectedAnimation === 'attack' ? weapon.visual?.animationOffsets?.attack : undefined)
      ?? weapon.visual?.sourceOffset
      ?? [0, 0];
    const offset = [baseOffset[0] + transform.offset[0], baseOffset[1] + transform.offset[1]] as const;
    const previewScaleX = scale[0] * 2.8;
    const previewScaleY = scale[1] * 2.8;
    weaponSprite.style.setProperty('--preview-scale-x', String(previewScaleX));
    weaponSprite.style.setProperty('--preview-scale-y', String(previewScaleY));
    weaponSprite.style.setProperty('--origin-offset-x', `${-origin[0] * info.width * previewScaleX}px`);
    weaponSprite.style.setProperty('--origin-offset-y', `${-origin[1] * info.height * previewScaleY}px`);
    weaponSprite.style.setProperty('--offset-x', `${offset[0] * baseScale[0] * 2.8 * (mirroredLeft ? -1 : 1)}px`);
    weaponSprite.style.setProperty('--offset-y', `${offset[1] * baseScale[1] * 2.8}px`);
    weaponSprite.style.setProperty('--weapon-rotation', `${transform.rotationDeg}deg`);
    weaponSprite.style.setProperty('--weapon-flip-x', mirroredLeft ? '-1' : '1');
  }
  const character = characterPackages.find((entry) => entry.characterId === state.selectedCharacterId) ?? selectedCharacter();
  const characterSource = state.assets?.assets.find((entry) => entry.assetId === character?.visualSet.assetId);
  const characterInfo = assetInfo(characterSource);
  const direction = state.selectedAnimation === 'attack' ? state.selectedAttackDirection : undefined;
  const action = characterClip(character, resolvedCharacterAction(character, weapon, direction));
  const characterFrame = action?.frames[position % Math.max(1, action.frames.length)] ?? 0;
  const characterSprite = container.querySelector<HTMLElement>('.stage-character-sprite');
  if (characterSprite) {
    characterSprite.style.setProperty('--frame-x', `${(characterFrame % characterInfo.columns) * characterInfo.width}px`);
    characterSprite.style.setProperty('--frame-y', `${Math.floor(characterFrame / characterInfo.columns) * characterInfo.height}px`);
    const visual = character?.visualSet;
    const frameVisual = visual?.frameVisuals?.[String(characterFrame)] ?? {};
    const offset = frameVisual.sourceOffset ?? visual?.defaults.sourceOffset ?? [0, 0];
    const scale = (frameVisual.scale ?? visual?.defaults.scale ?? [1, 1])[0] * 2.8;
    const origin = frameVisual.origin ?? visual?.defaults.origin ?? [0.5, 0.5];
    characterSprite.style.setProperty('--preview-scale', String(scale));
    characterSprite.style.setProperty('--origin-offset-x', `${-origin[0] * characterInfo.width * scale}px`);
    characterSprite.style.setProperty('--origin-offset-y', `${-origin[1] * characterInfo.height * scale}px`);
    characterSprite.style.setProperty('--offset-x', `${offset[0] * scale}px`);
    characterSprite.style.setProperty('--offset-y', `${offset[1] * scale}px`);
  }
  if (direction) {
    const hitboxGuides = container.querySelector<HTMLElement>('[data-weapon-hitbox-guides]');
    if (hitboxGuides && refreshHitboxGeometry) hitboxGuides.innerHTML = renderWeaponHitboxGuides(weapon, position, direction, state.selectedHitboxId);
    const preview = resolveWeaponHitboxPreview(weapon, direction);
    hitboxGuides?.querySelectorAll<HTMLElement>('[data-weapon-hitbox-id]').forEach((guide) => {
      const hitboxId = guide.dataset.weaponHitboxId ?? '';
      guide.classList.toggle('is-hot', weaponHitboxIsActive(preview, hitboxId, position));
      guide.classList.toggle('is-selected', hitboxId === resolvedSelectedHitboxId(preview.attack.hitboxes, state.selectedHitboxId));
    });
  }
  const caption = container.querySelector<HTMLElement>('.weapon-preview-card .stage-caption span');
  const lockedMirror = direction === 'left' && isMirroredLeft(weapon);
  if (caption) caption.textContent = `CHARACTER ACTION ${action?.id ?? weapon.characterActionId ?? 'trick'} · WEAPON TILE ${weaponFrame} · ${lockedMirror ? 'MIRROR RIGHT' : `${state.transformTool.toUpperCase()} TOOL`}`;
  const toolbar = container.querySelector<HTMLElement>('.weapon-preview-card .studio-preview-toolbar .studio-muted');
  if (toolbar) {
    const timeLabel = `${formatAnimationTimelineSeconds(position / animation.framesPerSecond, animation.framesPerSecond)}s`;
    const durationLabel = `${formatAnimationTimelineSeconds(expanded.timelineFrameCount / animation.framesPerSecond, animation.framesPerSecond)}s`;
    toolbar.textContent = `${state.selectedAnimation.toUpperCase()}${direction ? ` / ${direction.toUpperCase()}` : ''} · time ${timeLabel}/${durationLabel} · ${character?.character.displayName ?? 'character'} + weapon`;
  }
}

function reflowWeaponStudio(container: HTMLDivElement, weapon: WeaponDefinition, state: WeaponStudioState): void {
  const layout = container.querySelector<HTMLElement>('.studio-layout');
  const workbench = container.querySelector<HTMLElement>('.weapon-studio .studio-workbench');
  const inspector = container.querySelector<HTMLElement>('.weapon-inspector');
  const heading = workbench?.querySelector<HTMLElement>('.studio-workbench-heading');
  if (!layout || !workbench || !inspector || !heading) return;
  const source = state.assets?.assets.find((entry) => entry.assetId === weapon.assetId && isWeaponAsset(entry));
  const info = assetInfo(source);
  const character = characterPackages.find((entry) => entry.characterId === state.selectedCharacterId) ?? selectedCharacter();
  const characterSource = state.assets?.assets.find((entry) => entry.assetId === character?.visualSet.assetId);
  if (!workbench.querySelector('.weapon-preview-card')) heading.insertAdjacentHTML('afterend', renderWeaponPreview(weapon, info, state, character, assetInfo(characterSource)));
  if (!workbench.querySelector('.weapon-animation-panel')) workbench.querySelector('.weapon-preview-card')?.insertAdjacentHTML('afterend', renderWeaponAnimationPanel(weapon, source, state));
  const presentation = inspector.querySelector<HTMLElement>('[data-weapon-presentation]');
  if (presentation) {
    presentation.querySelector('.studio-section-heading strong')!.textContent = 'Animation';
    workbench.append(presentation);
  }
  if (!inspector.querySelector('.studio-inspector-heading')) inspector.insertAdjacentHTML('afterbegin', '<div class="studio-inspector-heading"><span class="studio-kicker">Inspector</span><h2>Weapon controls</h2><p>Identity, combat behavior, and visual alignment</p></div>');
  layout.append(inspector);
  syncWeaponInspectorTabs(container, state);
  updateCombinedPreviewDom(container, weapon, state);
}

function renderWeaponAssetCard(entry: CharacterStudioAssetEntry, selected: boolean): string {
  const info = assetInfo(entry);
  const preview = entry.frame ? `--sheet-url:url('${escapeHtml(info.url)}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:0px;--frame-y:0px` : `--sheet-url:url('${escapeHtml(info.url)}')`;
  return `<button type="button" class="studio-asset-card${selected ? ' is-selected' : ''}" data-action="select-weapon-asset" data-weapon-asset-id="${escapeHtml(entry.assetId)}" aria-pressed="${selected}"><span class="studio-asset-card-preview${entry.frame ? ' is-sheet' : ''}" style="${preview}"></span><span class="studio-asset-card-copy"><strong>${escapeHtml(entry.assetId)}</strong><small>WEAPON SOURCE</small><em>${info.columns} x ${info.rows} x ${info.count} FRAMES</em></span></button>`;
}

function renderWeaponAssetShelf(state: WeaponStudioState): string {
  if (!state.assetShelfOpen) return '';
  const assets = state.assets?.assets.filter(isWeaponAsset) ?? [];
  const current = state.draft?.assetId ?? '';
  return `<div class="studio-asset-shelf-backdrop" data-weapon-shelf-backdrop><section class="studio-asset-shelf" role="dialog" aria-modal="true" aria-labelledby="weapon-source-library-title"><header class="studio-asset-shelf-heading"><div><span class="studio-kicker">Weapon source library</span><h2 id="weapon-source-library-title">Select or import a sheet</h2><p>Use the same spritesheet workflow as Character Studio.</p></div><button type="button" class="studio-icon-button" data-action="close-weapon-source-library" aria-label="Close source library">X</button></header><div class="studio-asset-shelf-grid">${assets.map((entry) => renderWeaponAssetCard(entry, entry.assetId === current)).join('') || '<p class="studio-empty-note">No weapon-tagged source sheets are registered yet.</p>'}</div><section class="studio-asset-create-panel"><div class="studio-asset-create-heading"><span><span class="studio-kicker">Import source</span><strong>PNG spritesheet</strong></span><span class="studio-asset-create-status">${escapeHtml(state.notice ?? 'Frame dimensions must divide the PNG evenly.')}</span></div><div class="studio-asset-create-fields"><label class="studio-create-field"><span>Asset ID</span><input type="text" value="${escapeHtml(state.importForm.assetId)}" data-weapon-import-field="assetId" placeholder="weapon.player.sword" /></label><label class="studio-create-field"><span>Frame width</span><input type="number" min="1" step="1" inputmode="numeric" value="${escapeHtml(state.importForm.frameWidth)}" data-weapon-import-field="frameWidth" /></label><label class="studio-create-field"><span>Frame height</span><input type="number" min="1" step="1" inputmode="numeric" value="${escapeHtml(state.importForm.frameHeight)}" data-weapon-import-field="frameHeight" /></label><label class="studio-create-field"><span>Populated frames</span><input type="number" min="1" step="1" inputmode="numeric" value="${escapeHtml(state.importForm.populatedCount)}" data-weapon-import-field="populatedCount" placeholder="Full grid" /></label></div><div class="studio-asset-create-actions"><input type="file" accept="image/png" data-weapon-upload hidden /><button type="button" class="studio-button studio-button--save" data-action="upload-weapon-source" ${state.importing ? 'disabled' : ''}>${state.importing ? 'IMPORTING...' : 'IMPORT PNG + USE'}</button><button type="button" class="studio-button studio-button--quiet" data-action="close-weapon-source-library">CANCEL</button></div></section></section></div>`;
}

function renderWeaponAssetField(state: WeaponStudioState): string {
  const selected = state.draft?.assetId ?? '';
  const options = state.assets?.assets.filter(isWeaponAsset).map((entry) => `<option value="${escapeHtml(entry.assetId)}" ${entry.assetId === selected ? 'selected' : ''}>${escapeHtml(entry.assetId)}</option>`).join('') ?? '';
  return `<label class="studio-field studio-field--wide"><span>Source sheet<small>weapon-tagged spritesheet</small></span><div class="studio-source-picker"><select data-weapon-field="assetId"><option value="">Choose weapon source</option>${options}</select><button type="button" class="studio-button studio-button--quiet" data-action="open-weapon-source-library">SOURCE LIBRARY</button></div></label>`;
}

function renderWeaponTilePicker(state: WeaponStudioState): string {
  if (!state.sourceTilePickerOpen || !state.draft) return '';
  const source = state.assets?.assets.find((entry) => entry.assetId === state.draft?.assetId && isWeaponAsset(entry));
  const info = assetInfo(source);
  const animation = selectedWeaponAnimation(state.draft, info, state);
  const locked = state.selectedAnimation === 'attack' && state.selectedAttackDirection === 'left' && isMirroredLeft(state.draft);
  return `<div class="studio-asset-shelf-backdrop weapon-tile-picker-backdrop" data-weapon-tile-picker-backdrop><section class="studio-asset-shelf weapon-tile-picker" role="dialog" aria-modal="true" aria-labelledby="weapon-tile-picker-title"><header class="studio-asset-shelf-heading"><div><span class="studio-kicker">Animation keyframe picker</span><h2 id="weapon-tile-picker-title">Add source tiles</h2><p>Select one or more source tiles, then add them to this animation. Existing keyframes stay independent.</p></div><button type="button" class="studio-icon-button" data-action="close-weapon-tile-picker" aria-label="Close animation keyframe picker">X</button></header><div class="studio-sheet-grid projectile-frame-grid weapon-picker-grid">${Array.from({ length: info.count }, (_, frame) => renderWeaponFrameTile(source, frame, state.selectedPickerFrames.includes(frame), locked)).join('')}</div><footer class="weapon-tile-picker-footer"><span>${state.selectedPickerFrames.length} source tiles selected · ${animation.frames.length} keyframes · ${timelineFrameCount(animation)} timeline frames</span><div><button type="button" class="studio-button studio-button--quiet" data-action="close-weapon-tile-picker">CANCEL</button><button type="button" class="studio-button studio-button--accent" data-action="add-selected-weapon-tiles" ${state.selectedPickerFrames.length === 0 || locked ? 'disabled' : ''}>ADD TO ANIMATION</button></div></footer></section></div>`;
}

interface WeaponStudioViewportSnapshot {
  readonly workbench?: { readonly top: number; readonly left: number };
  readonly inspector?: { readonly top: number; readonly left: number };
  readonly window: { readonly x: number; readonly y: number };
  readonly focusedField?: string;
}

function captureWeaponStudioViewport(container: HTMLDivElement): WeaponStudioViewportSnapshot {
  const active = document.activeElement as HTMLElement | null;
  const workbench = container.querySelector<HTMLElement>('.studio-workbench');
  const inspector = container.querySelector<HTMLElement>('.studio-inspector-scroll');
  return {
    workbench: workbench ? { top: workbench.scrollTop, left: workbench.scrollLeft } : undefined,
    inspector: inspector ? { top: inspector.scrollTop, left: inspector.scrollLeft } : undefined,
    window: { x: window.scrollX, y: window.scrollY },
    focusedField: active?.dataset.weaponField,
  };
}

function restoreWeaponStudioViewport(container: HTMLDivElement, snapshot: WeaponStudioViewportSnapshot): void {
  const workbench = container.querySelector<HTMLElement>('.studio-workbench');
  const inspector = container.querySelector<HTMLElement>('.studio-inspector-scroll');
  if (workbench && snapshot.workbench) { workbench.scrollTop = snapshot.workbench.top; workbench.scrollLeft = snapshot.workbench.left; }
  if (inspector && snapshot.inspector) { inspector.scrollTop = snapshot.inspector.top; inspector.scrollLeft = snapshot.inspector.left; }
  window.scrollTo(snapshot.window.x, snapshot.window.y);
  if (snapshot.focusedField) {
    const field = [...container.querySelectorAll<HTMLElement>('[data-weapon-field]')].find((entry) => entry.dataset.weaponField === snapshot.focusedField);
    field?.focus({ preventScroll: true });
  }
}

function renderStudio(state: WeaponStudioState, returnEditor: string): string {
  const weapon = state.draft;
  const scaling = weapon?.scaling ?? {};
  return `<main class="character-studio weapon-studio" data-weapon-studio>
    <header class="studio-topbar"><a class="studio-brand" href="?" aria-label="Back to game"><span class="brand-mark">✦</span><span><small>FIELD CARTOGRAPHER</small><strong>WEAPON STUDIO</strong></span></a><div class="studio-topbar-actions"><span class="studio-save-state${state.notice ? ' is-error' : ''}"><i></i>${escapeHtml(state.notice ?? (state.dirty ? 'Unsaved weapon' : 'Saved library'))}</span><button type="button" class="studio-button studio-button--save" data-action="save-weapon" ${!weapon || !state.dirty || state.saving ? 'disabled' : ''}>${state.saving ? 'SAVING…' : 'SAVE WEAPON'}</button></div></header>
    <div class="studio-layout"><aside class="studio-library"><div class="studio-panel-title"><div><span class="studio-kicker">Equipment library</span><h1>Weapons</h1></div><span class="studio-count">${String(state.weapons.length).padStart(2, '0')}</span></div><div class="studio-roster">${state.weapons.map((entry) => `<button type="button" class="studio-roster-item${entry.weaponId === state.selectedId ? ' is-active' : ''}" data-weapon-id="${escapeHtml(entry.weaponId)}"><span class="roster-glyph player">◆</span><span><strong>${escapeHtml(entry.displayName)}</strong><small>${entry.category.toUpperCase()} · ${escapeHtml(entry.weaponId)}</small></span><em>${entry.weaponId === state.selectedId ? 'OPEN' : ''}</em></button>`).join('')}</div><div class="studio-library-footer"><button type="button" class="studio-button studio-button--outline studio-button--create" data-action="new-weapon">NEW WEAPON</button><a class="studio-button studio-button--outline studio-button--navigation" href="?studio=characters&editor=${encodeURIComponent(returnEditor)}">↗ CHARACTER STUDIO</a></div></aside>
      <section class="studio-workbench">${weapon ? `<div class="studio-workbench-heading"><div><span class="studio-kicker">Reusable combat definition</span><h2>${escapeHtml(weapon.displayName)}</h2></div><div class="studio-workbench-meta"><span>WEAPON <b>${escapeHtml(weapon.weaponId)}</b></span><span>CATEGORY <b>${weapon.category.toUpperCase()}</b></span><span>BASE DAMAGE <b>${weapon.baseDamage}</b></span></div></div><section class="studio-inspector weapon-inspector"><div class="studio-inspector-scroll"><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Identity</span><strong>Equipment profile</strong></div><div class="studio-field-grid"><label class="studio-field"><span>Stable ID<small>lowercase</small></span><input type="text" value="${escapeHtml(weapon.weaponId)}" data-weapon-field="weaponId" /></label><label class="studio-field"><span>Display name<small>library label</small></span><input type="text" value="${escapeHtml(weapon.displayName)}" data-weapon-field="displayName" /></label></div><div class="studio-field-grid"><label class="studio-field"><span>Category<small>combat family</small></span><select data-weapon-field="category"><option value="melee" ${weapon.category === 'melee' ? 'selected' : ''}>Melee</option><option value="ranged" ${weapon.category === 'ranged' ? 'selected' : ''}>Ranged</option></select></label><label class="studio-field"><span>Character action<small>animation key</small></span><input type="text" value="${escapeHtml(weapon.animKey)}" data-weapon-field="animKey" /></label></div><label class="studio-field studio-field--wide"><span>Description<small>authoring note</small></span><input type="text" value="${escapeHtml(weapon.description)}" data-weapon-field="description" /></label></section>${renderWeaponCombatProfile(weapon)}${renderWeaponScaling(scaling)}<section class="studio-inspector-section" data-weapon-presentation><div class="studio-section-heading"><span class="studio-kicker">Presentation</span><strong>Weapon layer foundation</strong></div><p class="studio-help">Weapon art will render as a separate layer attached to the character. This keeps one character compatible with many weapons.</p><div class="studio-callout"><strong>Character action: ${escapeHtml(weapon.animKey)}</strong><span>Next layer: import weapon art, define attachment offsets, and author the weapon timeline independently.</span></div></section></div></section>` : '<section class="studio-empty-state"><span class="studio-loading-orb">✦</span><h2>Select or create a weapon</h2><p>Weapons are reusable definitions. Characters and loadouts select them without duplicating character art.</p></section>'}</section></div>${renderWeaponAssetShelf(state)}
  </main>`;
}

async function loadCatalog(): Promise<WeaponCatalogResponse> {
  const response = await fetch('/__character-studio/weapons');
  const payload = await response.json() as { ok: boolean; data?: WeaponCatalogResponse; error?: { message?: string } };
  if (!response.ok || !payload.ok || !payload.data) throw new Error(payload.error?.message ?? 'Weapon catalog failed to load');
  return payload.data;
}

async function loadAssets(): Promise<CharacterStudioAssetCatalog> {
  const response = await fetch('/__character-studio/assets');
  const payload = await response.json() as { ok: boolean; data?: CharacterStudioAssetCatalog; error?: { message?: string } };
  if (!response.ok || !payload.ok || !payload.data) throw new Error(payload.error?.message ?? 'Weapon assets failed to load');
  return payload.data;
}

export function mountWeaponStudio(container: HTMLDivElement): () => void {
  container.classList.add('is-character-studio-host');
  const returnEditor = new URLSearchParams(window.location.search).get('editor') ?? 'meadow-crossing';
  let state: WeaponStudioState = { weapons: [], selectedId: '', selectedAnimation: 'attack', selectedAttackDirection: 'right', selectedHitboxId: 'primary', selectedAnimationPositions: [0], transformTool: 'move', onionSkin: false, selectedInspectorTab: 'visual', selectedPreviewFrame: 0, selectedCharacterId: selectedCharacter()?.characterId ?? '', previewStep: 0, previewPlaying: false, dirty: false, saving: false, assetShelfOpen: false, sourceTilePickerOpen: false, selectedPickerFrames: [], importing: false, importForm: { assetId: 'weapon.player.new', frameWidth: '16', frameHeight: '16', populatedCount: '' } };
  let previewTimer: number | undefined;
  let history: WeaponDefinition[] = [];
  let future: WeaponDefinition[] = [];
  let draggedAnimationPosition: number | undefined;
  let resizeController: TimelineHoldResizeController | undefined;
  let transformDrag: {
    readonly baseDraft: WeaponDefinition;
    readonly startX: number;
    readonly startY: number;
    readonly centerX: number;
    readonly centerY: number;
    readonly startAngle: number;
  } | undefined;
  const leftMirrorLocked = (): boolean => state.selectedAnimation === 'attack'
    && state.selectedAttackDirection === 'left'
    && state.draft !== undefined
    && isMirroredLeft(state.draft);
  const rememberDraft = (): void => {
    if (!state.draft) return;
    history = [...history.slice(-59), clone(state.draft)];
    future = [];
  };
  const undo = (): void => {
    const previous = history.at(-1);
    if (!previous || !state.draft) return;
    future = [clone(state.draft), ...future.slice(0, 59)];
    history = history.slice(0, -1);
    stopPreview();
    state = { ...state, draft: previous, dirty: true, notice: 'Undid weapon edit' };
    render();
  };
  const redo = (): void => {
    const next = future[0];
    if (!next || !state.draft) return;
    history = [...history.slice(-59), clone(state.draft)];
    future = future.slice(1);
    stopPreview();
    state = { ...state, draft: next, dirty: true, notice: 'Redid weapon edit' };
    render();
  };
  const stopPreview = (): void => {
    if (previewTimer !== undefined) window.clearInterval(previewTimer);
    previewTimer = undefined;
    state = { ...state, previewPlaying: false };
  };
  const render = (): void => {
    resizeController?.cancel();
    const viewport = captureWeaponStudioViewport(container);
    container.innerHTML = renderStudio(state, returnEditor);
    if (state.sourceTilePickerOpen) container.insertAdjacentHTML('beforeend', renderWeaponTilePicker(state));
    ensureStudioModeTabs(container, returnEditor, 'weapons');
    if (state.draft) {
      const presentation = container.querySelector<HTMLElement>('[data-weapon-presentation]');
      if (presentation) {
        presentation.insertAdjacentHTML('beforebegin', renderWeaponHitboxEditor(state.draft, state));
        presentation.insertAdjacentHTML('beforebegin', renderWeaponVisualFields(state.draft));
        presentation.querySelector<HTMLElement>('.studio-section-heading strong')!.textContent = 'Visual + attack timing';
        presentation.querySelector<HTMLElement>('.studio-help')!.textContent = 'Preview the character action and weapon frames together, then align the weapon to the player anchor.';
        const callout = presentation.querySelector<HTMLElement>('.studio-callout');
        if (callout) {
          callout.innerHTML = `<strong>Character action: ${escapeHtml(state.draft.characterActionId ?? state.draft.animKey?.replace(/^slime-/, '') ?? 'trick')}</strong><span>Weapon hitboxes activate from the attack-frame event track and can be authored independently.</span>`;
        }
      }
      const identity = container.querySelector<HTMLElement>('.weapon-inspector .studio-inspector-section');
      const description = identity?.querySelector<HTMLElement>('.studio-field--wide');
      if (description) description.insertAdjacentHTML('beforebegin', renderWeaponAssetField(state));
      const legacyActionInput = identity?.querySelector<HTMLInputElement>('[data-weapon-field="animKey"]');
      if (legacyActionInput) {
        legacyActionInput.dataset.weaponField = 'characterActionId';
        legacyActionInput.value = state.draft.characterActionId ?? state.draft.animKey?.replace(/^slime-/, '') ?? 'trick';
        const labelText = legacyActionInput.closest('label')?.querySelector('span');
        if (labelText) labelText.firstChild!.textContent = 'Character action';
      }
      const actionInput = identity?.querySelector<HTMLInputElement>('[data-weapon-field="characterActionId"]');
      if (actionInput) actionInput.closest('label')?.replaceWith(document.createRange().createContextualFragment(renderCharacterActionField(state)).firstElementChild!);
      if (identity && !identity.querySelector('[data-weapon-character-id]')) identity.insertAdjacentHTML('beforeend', renderPreviewCharacterField(state));
      if (identity && !identity.querySelector('[data-weapon-character-id]')) {
        const options = characterPackages.map((entry) => `<option value="${escapeHtml(entry.characterId)}" ${entry.characterId === state.selectedCharacterId ? 'selected' : ''}>${escapeHtml(entry.character.displayName)} · ${escapeHtml(entry.characterId)}</option>`).join('');
        identity.insertAdjacentHTML('beforeend', `<label class="studio-field studio-field--wide"><span>Preview character<small>existing anchor + action</small></span><select data-weapon-character-id>${options}</select></label>`);
      }
      const inspectorScroll = identity?.parentElement;
      const sections = inspectorScroll ? Array.from(inspectorScroll.querySelectorAll<HTMLElement>(':scope > .studio-inspector-section')) : [];
      sections[0]?.setAttribute('data-weapon-inspector-group', 'identity');
      sections[1]?.setAttribute('data-weapon-inspector-group', 'combat');
      sections[2]?.setAttribute('data-weapon-inspector-group', 'combat');
      container.querySelector<HTMLElement>('.studio-weapon-hitbox-section')?.setAttribute('data-weapon-inspector-group', 'combat');
      reflowWeaponStudio(container, state.draft, state);
    }
    restoreWeaponStudioViewport(container, viewport);
    window.requestAnimationFrame(() => restoreWeaponStudioViewport(container, viewport));
  };
  const select = (weapon: WeaponDefinition, revision?: string): void => { stopPreview(); history = []; future = []; state = { ...state, selectedId: weapon.weaponId, selectedAnimation: 'attack', selectedAttackDirection: 'right', selectedHitboxId: Object.keys(weaponHitboxes(weapon, 'right'))[0] ?? '', selectedAnimationPositions: [0], transformTool: 'move', selectedInspectorTab: 'visual', selectedPreviewFrame: 0, previewStep: 0, previewPlaying: false, draft: clone(weapon), revision, dirty: false, assetShelfOpen: false, sourceTilePickerOpen: false, selectedPickerFrames: [], notice: undefined }; render(); };
  const revealHitboxControls = (hitboxId: string): void => {
    window.requestAnimationFrame(() => window.requestAnimationFrame(() => {
      const editor = [...container.querySelectorAll<HTMLElement>('[data-weapon-hitbox-editor-id]')]
        .find((entry) => entry.dataset.weaponHitboxEditorId === hitboxId);
      editor?.scrollIntoView({ block: 'nearest' });
      editor?.querySelector<HTMLElement>('select, input, button')?.focus({ preventScroll: true });
    }));
  };
  const selectWeaponHitbox = (hitboxId: string): void => {
    if (!state.draft) return;
    const direction = state.selectedAnimation === 'attack' ? state.selectedAttackDirection : undefined;
    if (!weaponHitboxes(state.draft, direction)[hitboxId]) return;
    stopPreview();
    state = { ...state, selectedHitboxId: hitboxId, selectedInspectorTab: 'combat' };
    render();
    revealHitboxControls(hitboxId);
  };
  const importSource = async (file: File): Promise<void> => {
    const assetId = state.importForm.assetId.trim().toLowerCase();
    const frameWidth = integerValue(state.importForm.frameWidth);
    const frameHeight = integerValue(state.importForm.frameHeight);
    const populatedCount = integerValue(state.importForm.populatedCount);
    if (!assetId || frameWidth < 1 || frameHeight < 1) { state = { ...state, notice: 'Enter an asset ID, frame width, and frame height first.' }; render(); return; }
    const metadata: Record<string, unknown> = { assetId, frameWidth, frameHeight, kind: 'player', tags: ['weapon'] };
    if (populatedCount > 0) metadata.populatedCount = populatedCount;
    const body = new FormData();
    body.append('metadata', JSON.stringify(metadata));
    body.append('file', file, file.name);
    state = { ...state, importing: true, notice: 'Registering weapon source...' };
    render();
    try {
      const response = await fetch('/__character-studio/asset/register', { method: 'POST', body });
      const payload = await response.json() as { ok: boolean; data?: { assetId: string }; error?: { message?: string } };
      if (!response.ok || !payload.ok || !payload.data) throw new Error(payload.error?.message ?? 'Weapon source import failed');
      const assets = await loadAssets();
      const selectedAsset = assets.assets.find((entry) => entry.assetId === payload.data?.assetId);
      const draft = state.draft ? { ...state.draft, assetId: payload.data.assetId, animations: weaponAnimations(state.draft, assetInfo(selectedAsset)) } : undefined;
      state = { ...state, assets, draft, assetShelfOpen: false, importing: false, dirty: draft !== undefined, notice: 'Weapon source imported and selected' };
      render();
    } catch (error) {
      state = { ...state, importing: false, notice: error instanceof Error ? error.message : String(error) };
      render();
    }
  };
  const load = async (): Promise<void> => {
    try {
      const [catalog, assets] = await Promise.all([loadCatalog(), loadAssets()]);
      state = { ...state, assets, weapons: catalog.weapons, selectedId: catalog.weapons[0]?.weaponId ?? '' };
      if (catalog.weapons[0]) select(catalog.weapons[0], catalog.weapons[0].revision); else render();
    } catch (error) { state = { ...state, notice: error instanceof Error ? error.message : String(error) }; render(); }
  };
  const updateDraft = (path: string, rawValue: string | boolean): void => {
    if (!state.draft) return;
    rememberDraft();
    const draft = clone(state.draft) as MutableWeaponDraft;
    const numericPaths = new Set(['baseDamage', 'cooldownMs', 'hitboxWidth', 'hitboxHeight', 'hitboxOffset', 'hitboxDurationMs', 'knockStrength', 'unlockLevel', 'scaling.damage.strength', 'scaling.damage.agility', 'scaling.damage.intellect', 'scaling.cooldown.agility', 'scaling.knockback.strength', 'visual.sourceOffset.0', 'visual.sourceOffset.1']);
    const value = numericPaths.has(path) ? integerValue(rawValue) : rawValue;
    const info = assetInfo(state.assets?.assets.find((entry) => entry.assetId === draft.assetId && isWeaponAsset(entry)));
    const directionalAnimationMatch = path.match(/^directionalAttacks\.(right|left|up|down)\.animation\.(frames|durationSeconds|framesPerSecond|loop|loopMode)$/);
    const animationMatch = path.match(/^animations\.(idle|attack|impact)\.(frames|durationSeconds|framesPerSecond|loop|loopMode)$/);
    if (directionalAnimationMatch) {
      const direction = directionalAnimationMatch[1] as WeaponAttackDirection;
      const fieldName = directionalAnimationMatch[2] as 'frames' | 'durationSeconds' | 'framesPerSecond' | 'loop' | 'loopMode';
      const attack = ensureDirectionalAttackDraft(draft, info, direction);
      const next = clone(attack.animation) as MutableWeaponAnimation;
      if (fieldName === 'frames') {
        const frames = String(rawValue).split(',').map((entry) => Number(entry.trim())).filter((entry) => Number.isInteger(entry) && entry >= 0);
        next.frames = frames.length > 0 ? frames : [0];
        const timelineFrames = Math.max(timelineFrameCount(next), next.frames.length);
        next.durationSeconds = timelineFrames / next.framesPerSecond;
        next.keyframeTimes = evenKeyframeTimes(timelineFrames, next.frames.length);
        next.frameTransforms = Object.fromEntries(Object.entries(next.frameTransforms ?? {}).filter(([position]) => Number(position) < next.frames.length));
      } else if (fieldName === 'durationSeconds' || fieldName === 'framesPerSecond') {
        const nextFramesPerSecond = fieldName === 'framesPerSecond' ? Math.min(240, Math.max(1, integerValue(rawValue, 12))) : next.framesPerSecond;
        const nextDurationSeconds = fieldName === 'durationSeconds' ? Math.max(0.01, Number.isFinite(Number(rawValue)) ? Number(rawValue) : (next.durationSeconds ?? 1 / next.framesPerSecond)) : next.durationSeconds ?? next.frames.length / next.framesPerSecond;
        try {
          next.keyframeTimes = rescaleKeyframeTimes(normalizedWeaponAnimation(next), nextDurationSeconds, nextFramesPerSecond);
          next.durationSeconds = nextDurationSeconds;
          next.framesPerSecond = nextFramesPerSecond;
        } catch (error) {
          state = { ...state, notice: error instanceof Error ? error.message : String(error) };
          return;
        }
      }
      else if (fieldName === 'loop') next.loop = Boolean(rawValue);
      else next.loopMode = rawValue === 'ping-pong' ? 'ping-pong' : 'wrap';
      attack.animation = next;
    } else if (animationMatch) {
      const animationId = animationMatch[1] as WeaponAnimationId;
      const fieldName = animationMatch[2] as 'frames' | 'durationSeconds' | 'framesPerSecond' | 'loop' | 'loopMode';
      const animations = weaponAnimations(draft, info);
      const next = clone(animations[animationId]) as MutableWeaponAnimation;
      if (fieldName === 'frames') {
        const frames = String(rawValue).split(',').map((entry) => Number(entry.trim())).filter((entry) => Number.isInteger(entry) && entry >= 0);
        next.frames = frames.length > 0 ? frames : [0];
        const timelineFrames = Math.max(timelineFrameCount(next), next.frames.length);
        next.durationSeconds = timelineFrames / next.framesPerSecond;
        next.keyframeTimes = evenKeyframeTimes(timelineFrames, next.frames.length);
        next.frameTransforms = Object.fromEntries(Object.entries(next.frameTransforms ?? {}).filter(([position]) => Number(position) < next.frames.length));
      }
      else if (fieldName === 'durationSeconds' || fieldName === 'framesPerSecond') {
        const nextFramesPerSecond = fieldName === 'framesPerSecond' ? Math.min(240, Math.max(1, integerValue(rawValue, 12))) : next.framesPerSecond;
        const nextDurationSeconds = fieldName === 'durationSeconds' ? Math.max(0.01, Number.isFinite(Number(rawValue)) ? Number(rawValue) : (next.durationSeconds ?? 1 / next.framesPerSecond)) : next.durationSeconds ?? next.frames.length / next.framesPerSecond;
        try {
          next.keyframeTimes = rescaleKeyframeTimes(normalizedWeaponAnimation(next), nextDurationSeconds, nextFramesPerSecond);
          next.durationSeconds = nextDurationSeconds;
          next.framesPerSecond = nextFramesPerSecond;
        } catch (error) {
          state = { ...state, notice: error instanceof Error ? error.message : String(error) };
          return;
        }
      }
      else if (fieldName === 'loop') next.loop = Boolean(rawValue);
      else next.loopMode = rawValue === 'ping-pong' ? 'ping-pong' : 'wrap';
      draft.animations = { ...animations, [animationId]: next };
    } else if (path.match(/^directionalAttacks\.(right|left|up|down)\.characterActionId$/)) {
      const direction = path.split('.')[1] as WeaponAttackDirection;
      const requested = String(value).trim().toLowerCase();
      const actions = characterActions(previewCharacter(state.selectedCharacterId));
      ensureDirectionalAttackDraft(draft, info, direction).characterActionId = actions.includes(requested) ? requested : actions[0] ?? 'trick';
    } else if (path.startsWith('scaling.')) {
      const [, group, attribute] = path.split('.') as ['', keyof MutableWeaponScaling, keyof MutableWeaponScalingGroup];
      draft.scaling ??= {};
      draft.scaling[group] ??= {};
      draft.scaling[group]![attribute] = Number(value);
    } else if (path === 'weaponId') draft.weaponId = String(value).trim().toLowerCase();
    else if (path === 'displayName') draft.displayName = String(value);
    else if (path === 'category') draft.category = value === 'ranged' ? 'ranged' : 'melee';
    else if (path === 'animKey') draft.animKey = String(value);
    else if (path === 'characterActionId') {
      const requested = String(value).trim().toLowerCase();
      const actions = characterActions(previewCharacter(state.selectedCharacterId));
      draft.characterActionId = actions.includes(requested) ? requested : actions[0] ?? 'trick';
    }
    else if (path === 'assetId') {
      draft.assetId = String(value);
      const source = state.assets?.assets.find((entry) => entry.assetId === draft.assetId && isWeaponAsset(entry));
      draft.animations = weaponAnimations(draft, assetInfo(source));
    }
    else if (path === 'description') draft.description = String(value);
    else if (path === 'baseDamage') draft.baseDamage = Number(value);
    else if (path === 'cooldownMs') draft.cooldownMs = Number(value);
    else if (path === 'hitboxWidth') draft.hitboxWidth = Number(value);
    else if (path === 'hitboxHeight') draft.hitboxHeight = Number(value);
    else if (path === 'hitboxOffset') draft.hitboxOffset = Number(value);
    else if (path === 'hitboxDurationMs') draft.hitboxDurationMs = Number(value);
    else if (path === 'knockStrength') draft.knockStrength = Number(value);
    else if (path === 'unlockLevel') draft.unlockLevel = Number(value);
    else if (path.match(/^directionalAttacks\.(right|left|up|down)\.hitboxes\.[^.]+\.(shape|width|height|offsetX|offsetY|radius|radiusX|radiusY|innerRadius|outerRadius|arcWidthRad|damageMultiplier|knockbackMultiplier)$/)) {
      const [, direction, , hitboxId, property] = path.split('.') as ['', WeaponAttackDirection, 'hitboxes', string, keyof MutableWeaponHitbox];
      const attack = ensureDirectionalAttackDraft(draft, info, direction);
      attack.hitboxes ??= clone(weaponHitboxes(draft, direction)) as Record<string, MutableWeaponHitbox>;
      const hitbox = attack.hitboxes[hitboxId];
      if (hitbox) {
        if (property === 'shape') applyWeaponHitboxShape(hitbox, value as WeaponHitboxShape);
        else hitbox[property] = (property === 'arcWidthRad' ? Number(value) * Math.PI / 180 : Number(value)) as never;
      }
    }
    else if (path.match(/^hitboxes\.[^.]+\.(shape|width|height|offsetX|offsetY|radius|radiusX|radiusY|innerRadius|outerRadius|arcWidthRad|damageMultiplier|knockbackMultiplier)$/)) {
      const [, hitboxId, property] = path.split('.');
      draft.hitboxes ??= clone(weaponHitboxes(draft)) as Record<string, MutableWeaponHitbox>;
      const hitbox = draft.hitboxes[hitboxId];
      if (hitbox) {
        if (property === 'shape') applyWeaponHitboxShape(hitbox, value as WeaponHitboxShape);
        else hitbox[property as keyof MutableWeaponHitbox] = (property === 'arcWidthRad' ? Number(value) * Math.PI / 180 : Number(value)) as never;
      }
    }
    else if (path === 'visual.sourceOffset.0' || path === 'visual.sourceOffset.1') {
      const offset = [...(draft.visual?.sourceOffset ?? [0, 0])] as [number, number];
      offset[path.endsWith('.0') ? 0 : 1] = integerValue(value);
      draft.visual = { ...(draft.visual ?? { sourceOffset: [0, 0] }), sourceOffset: offset };
    }
    else if (path.match(/^visual\.scale\.[01]$/)) {
      const scale = [...(draft.visual?.scale ?? [1, 1])] as [number, number];
      scale[path.endsWith('.0') ? 0 : 1] = Number(value);
      draft.visual = { ...(draft.visual ?? { sourceOffset: [0, 0] }), scale };
    }
    else if (path.match(/^visual\.animationOffsets\.attack\.[01]$/)) {
      const offset = [...(draft.visual?.animationOffsets?.attack ?? [0, 0])] as [number, number];
      offset[path.endsWith('.0') ? 0 : 1] = integerValue(value);
      draft.visual = { ...(draft.visual ?? { sourceOffset: [0, 0] }), animationOffsets: { ...(draft.visual?.animationOffsets ?? {}), attack: offset } };
    }
    else if (path === 'visual.facingMode') {
      draft.visual = { ...(draft.visual ?? { sourceOffset: [0, 0] }), facingMode: value === 'horizontal-flip' ? 'horizontal-flip' : 'vector' };
    }
    state = { ...state, draft, selectedId: draft.weaponId, dirty: true, notice: undefined };
  };
  const updateAttackTrack = (mutate: (track: MutableWeaponTrack, attack: WeaponAnimationDocument) => void): void => {
    if (!state.draft || leftMirrorLocked()) return;
    rememberDraft();
    const draft = clone(state.draft) as MutableWeaponDraft;
    const source = state.assets?.assets.find((entry) => entry.assetId === draft.assetId && isWeaponAsset(entry));
    const info = assetInfo(source);
    const attack = directionalAttack(draft, info, state.selectedAttackDirection).animation;
    const current = weaponTrack(draft, attack, state.selectedAttackDirection);
    const track: MutableWeaponTrack = { hitboxSpans: current.hitboxSpans.map((span) => ({ ...span })), events: (current.events ?? []).map((event) => ({ ...event })) };
    mutate(track, attack);
    ensureDirectionalAttackDraft(draft, info, state.selectedAttackDirection).attackTrack = track;
    state = { ...state, draft, dirty: true, notice: undefined };
  };
  const toggleWeaponSpan = (hitboxId: string, frame: number): void => {
    updateAttackTrack((track) => {
      const activeFrames = new Set<number>();
      track.hitboxSpans.filter((span) => span.hitboxId === hitboxId).forEach((span) => { for (let index = span.from; index <= span.through; index += 1) activeFrames.add(index); });
      if (activeFrames.has(frame)) activeFrames.delete(frame); else activeFrames.add(frame);
      track.hitboxSpans = track.hitboxSpans.filter((span) => span.hitboxId !== hitboxId);
      const sorted = [...activeFrames].sort((left, right) => left - right);
      let start: number | undefined;
      let previous: number | undefined;
      for (const index of sorted) {
        if (start === undefined) start = index;
        else if (previous !== undefined && index !== previous + 1) { track.hitboxSpans.push({ hitboxId, from: start, through: previous }); start = index; }
        previous = index;
      }
      if (start !== undefined && previous !== undefined) track.hitboxSpans.push({ hitboxId, from: start, through: previous });
    });
    render();
  };
  const updateWeaponEvent = (frame: number, eventId: string): void => {
    updateAttackTrack((track) => {
      track.events = track.events.filter((event) => event.at !== frame);
      if (eventId.trim()) track.events.push({ at: frame, eventId: eventId.trim().toLowerCase() });
      track.events.sort((left, right) => left.at - right.at);
    });
  };
  const addWeaponHitbox = (): void => {
    if (!state.draft || leftMirrorLocked()) return;
    rememberDraft();
    const draft = clone(state.draft) as MutableWeaponDraft;
    const direction = state.selectedAnimation === 'attack' ? state.selectedAttackDirection : undefined;
    const info = assetInfo(state.assets?.assets.find((entry) => entry.assetId === draft.assetId && isWeaponAsset(entry)));
    const attack = direction ? ensureDirectionalAttackDraft(draft, info, direction) : undefined;
    if (attack) attack.hitboxes ??= clone(weaponHitboxes(draft, direction)) as Record<string, MutableWeaponHitbox>;
    else draft.hitboxes ??= clone(weaponHitboxes(draft)) as Record<string, MutableWeaponHitbox>;
    const hitboxes = attack?.hitboxes ?? draft.hitboxes!;
    let index = Object.keys(hitboxes).length + 1;
    let hitboxId = `hitbox-${index}`;
    while (hitboxes[hitboxId]) { index += 1; hitboxId = `hitbox-${index}`; }
    hitboxes[hitboxId] = { shape: 'circle', width: 24, height: 24, radius: 12, offsetX: 30, offsetY: 0, damageMultiplier: 1, knockbackMultiplier: 1 };
    state = { ...state, draft, selectedHitboxId: hitboxId, selectedInspectorTab: 'combat', dirty: true, notice: undefined };
    render();
    revealHitboxControls(hitboxId);
  };
  const removeWeaponHitbox = (hitboxId: string): void => {
    if (!state.draft || leftMirrorLocked()) return;
    const draft = clone(state.draft) as MutableWeaponDraft;
    const direction = state.selectedAnimation === 'attack' ? state.selectedAttackDirection : undefined;
    const info = assetInfo(state.assets?.assets.find((entry) => entry.assetId === draft.assetId && isWeaponAsset(entry)));
    const attack = direction ? ensureDirectionalAttackDraft(draft, info, direction) : undefined;
    if (attack) attack.hitboxes ??= clone(weaponHitboxes(draft, direction)) as Record<string, MutableWeaponHitbox>;
    else draft.hitboxes ??= clone(weaponHitboxes(draft)) as Record<string, MutableWeaponHitbox>;
    const hitboxes = attack?.hitboxes ?? draft.hitboxes!;
    if (Object.keys(hitboxes).length <= 1) return;
    rememberDraft();
    delete hitboxes[hitboxId];
    if (attack?.attackTrack) attack.attackTrack.hitboxSpans = attack.attackTrack.hitboxSpans.filter((span) => span.hitboxId !== hitboxId);
    else if (!direction) {
      if (draft.attackTrack) draft.attackTrack.hitboxSpans = draft.attackTrack.hitboxSpans.filter((span) => span.hitboxId !== hitboxId);
      for (const directional of Object.values(draft.directionalAttacks ?? {})) {
        if (directional?.attackTrack) directional.attackTrack.hitboxSpans = directional.attackTrack.hitboxSpans.filter((span) => span.hitboxId !== hitboxId);
      }
    }
    const selectedHitboxId = state.selectedHitboxId === hitboxId
      ? Object.keys(hitboxes)[0] ?? ''
      : resolvedSelectedHitboxId(hitboxes, state.selectedHitboxId);
    state = { ...state, draft, selectedHitboxId, dirty: true, notice: undefined };
    render();
    if (selectedHitboxId) revealHitboxControls(selectedHitboxId);
  };
  const commitAnimationOrder = (newFrames: number[], newToOldPositions: number[], selectedPositions: number[], nextKeyframeTimes?: readonly number[], nextDurationSeconds?: number): void => {
    if (!state.draft || newFrames.length === 0 || leftMirrorLocked()) return;
    rememberDraft();
    const draft = clone(state.draft) as MutableWeaponDraft;
    const source = state.assets?.assets.find((entry) => entry.assetId === draft.assetId && isWeaponAsset(entry));
    const info = assetInfo(source);
    const previousAnimation = selectedWeaponAnimation(draft, info, state);
    const nextAnimation = clone(previousAnimation) as MutableWeaponAnimation;
    nextAnimation.frames = newFrames;
    nextAnimation.keyframeTimes = [...(nextKeyframeTimes ?? previousAnimation.keyframeTimes)];
    if (nextDurationSeconds !== undefined) nextAnimation.durationSeconds = nextDurationSeconds;
    const nextFrameTransforms = remapFrameTransforms(previousAnimation.frameTransforms, newToOldPositions);
    if (nextFrameTransforms) nextAnimation.frameTransforms = { ...nextFrameTransforms };
    else delete nextAnimation.frameTransforms;
    writeSelectedAnimation(draft, info, state, nextAnimation);
    if (state.selectedAnimation === 'attack') ensureDirectionalAttackDraft(draft, info, state.selectedAttackDirection).attackTrack ??= clone(weaponTrack(draft, previousAnimation, state.selectedAttackDirection)) as MutableWeaponTrack;
    const selected = selectedPositions.length > 0 ? selectedPositions : [0];
    const selectedPosition = selected[selected.length - 1] ?? 0;
    const previewStep = nextAnimation.keyframeTimes[selectedPosition] ?? selectedPosition;
    state = { ...state, draft, selectedAnimationPositions: selected, previewStep, selectedPreviewFrame: newFrames[selectedPosition] ?? 0, dirty: true, notice: undefined };
    render();
  };
  const setTileHold = (position: number, requestedHold: number): boolean => {
    if (!state.draft || !Number.isFinite(requestedHold) || leftMirrorLocked()) return false;
    const source = state.assets?.assets.find((entry) => entry.assetId === state.draft?.assetId && isWeaponAsset(entry));
    const animation = selectedWeaponAnimation(state.draft, assetInfo(source), state);
    if (!Number.isInteger(position) || position < 0 || position >= animation.frames.length) return false;
    const currentHold = holdLengthAtKeyframe(animation, position);
    const nextHold = Math.max(1, Math.round(requestedHold));
    if (nextHold === currentHold) return false;
    const resized = resizeKeyframeHold(animation, position, nextHold);
    commitAnimationOrder(animation.frames.slice(), animation.frames.map((_, index) => index), [...state.selectedAnimationPositions], resized.keyframeTimes, resized.durationSeconds);
    return true;
  };
  const adjustTileHold = (position: number, delta: number): void => {
    if (!state.draft || !Number.isFinite(delta) || delta === 0 || leftMirrorLocked()) return;
    const source = state.assets?.assets.find((entry) => entry.assetId === state.draft?.assetId && isWeaponAsset(entry));
    const animation = selectedWeaponAnimation(state.draft, assetInfo(source), state);
    if (!Number.isInteger(position) || position < 0 || position >= animation.frames.length) return;
    setTileHold(position, holdLengthAtKeyframe(animation, position) + Math.round(delta));
  };

  const weaponResizeValidationToken = (animation: NormalizedWeaponAnimationDocument): string => JSON.stringify([
    state.selectedId,
    state.selectedAnimation,
    state.selectedAttackDirection,
    animation.framesPerSecond,
    animation.durationSeconds,
    animation.frames,
    animation.keyframeTimes,
  ]);
  resizeController = new TimelineHoldResizeController({
    resolveContext: (keyframeIndex, handle) => {
      if (!state.draft || leftMirrorLocked()) return undefined;
      const source = state.assets?.assets.find((entry) => entry.assetId === state.draft?.assetId && isWeaponAsset(entry));
      const animation = selectedWeaponAnimation(state.draft, assetInfo(source), state);
      const tile = handle.closest<HTMLElement>('.timeline-frame');
      const lane = tile?.closest<HTMLElement>('.timeline-frames');
      const timeline = tile?.closest<HTMLElement>('.studio-timeline');
      if (!tile || !lane || !timeline || keyframeIndex < 0 || keyframeIndex >= animation.frames.length) return undefined;
      return {
        keyframeIndex,
        sourceFrame: animation.frames[keyframeIndex],
        startFrame: animation.keyframeTimes[keyframeIndex],
        originalHold: holdLengthAtKeyframe(animation, keyframeIndex),
        framesPerSecond: animation.framesPerSecond,
        timelineFrames: timelineFrameCount(animation),
        validationToken: weaponResizeValidationToken(animation),
        timeline,
        lane,
        tile,
      };
    },
    commitHold: (commit) => {
      if (!state.draft || leftMirrorLocked()) return false;
      const source = state.assets?.assets.find((entry) => entry.assetId === state.draft?.assetId && isWeaponAsset(entry));
      const animation = selectedWeaponAnimation(state.draft, assetInfo(source), state);
      if (weaponResizeValidationToken(animation) !== commit.validationToken
        || animation.frames[commit.keyframeIndex] !== commit.sourceFrame
        || animation.keyframeTimes[commit.keyframeIndex] !== commit.startFrame
        || holdLengthAtKeyframe(animation, commit.keyframeIndex) !== commit.originalHold) return false;
      stopPreview();
      return setTileHold(commit.keyframeIndex, commit.requestedHold);
    },
    afterCommit: (keyframeIndex) => queueMicrotask(() => {
      const handle = container.querySelector<HTMLElement>(`[data-timeline-resize-handle][data-keyframe-index="${keyframeIndex}"]`);
      (handle ?? container.querySelector<HTMLElement>('.studio-timeline'))?.focus({ preventScroll: true });
    }),
  });
  const addSourceTiles = (frames: readonly number[]): void => {
    if (!state.draft) return;
    if (frames.length === 0 || leftMirrorLocked()) return;
    const source = state.assets?.assets.find((entry) => entry.assetId === state.draft?.assetId && isWeaponAsset(entry));
    const animation = selectedWeaponAnimation(state.draft, assetInfo(source), state);
    const nextFrames = [...animation.frames, ...frames];
    const previousTimelineFrames = timelineFrameCount(animation);
    const nextTimelineFrames = previousTimelineFrames + frames.length;
    const nextKeyframeTimes = [...animation.keyframeTimes, ...frames.map((_, index) => previousTimelineFrames + index)];
    commitAnimationOrder(nextFrames, [...animation.frames.map((_, position) => position), ...frames.map(() => -1)], [nextFrames.length - 1], nextKeyframeTimes, nextTimelineFrames / animation.framesPerSecond);
  };
  const addSourceTile = (frame: number): void => {
    addSourceTiles([frame]);
  };
  const distributeSelectedAnimation = (): void => {
    if (!state.draft || leftMirrorLocked()) return;
    rememberDraft();
    const draft = clone(state.draft) as MutableWeaponDraft;
    const source = state.assets?.assets.find((entry) => entry.assetId === draft.assetId && isWeaponAsset(entry));
    const animation = selectedWeaponAnimation(draft, assetInfo(source), state);
    try {
      const next = { ...animation, keyframeTimes: evenKeyframeTimes(timelineFrameCount(animation), animation.frames.length) };
      writeSelectedAnimation(draft, assetInfo(source), state, next);
      state = { ...state, draft, selectedAnimationPositions: [0], previewStep: 0, selectedPreviewFrame: next.frames[0] ?? 0, dirty: true, notice: undefined };
      render();
    } catch (error) {
      state = { ...state, notice: error instanceof Error ? error.message : String(error) };
      render();
    }
  };
  const deleteSelectedTiles = (): void => {
    if (!state.draft) return;
    const source = state.assets?.assets.find((entry) => entry.assetId === state.draft?.assetId && isWeaponAsset(entry));
    const animation = selectedWeaponAnimation(state.draft, assetInfo(source), state);
    const selected = new Set(state.selectedAnimationPositions);
    if (animation.frames.length <= 1 || selected.size === 0) return;
    const order = animation.frames.map((_, position) => position).filter((position) => !selected.has(position));
    if (order.length === 0) return;
    const nextSelection = [Math.min(state.previewStep, order.length - 1)];
    const deleted = deleteKeyframes(animation, [...selected]);
    commitAnimationOrder(deleted.frames, order, nextSelection, deleted.keyframeTimes);
  };
  const moveSelectedTiles = (direction: -1 | 1): void => {
    if (!state.draft) return;
    const source = state.assets?.assets.find((entry) => entry.assetId === state.draft?.assetId && isWeaponAsset(entry));
    const animation = selectedWeaponAnimation(state.draft, assetInfo(source), state);
    const order = animation.frames.map((_, position) => position);
    const selectedOld = new Set(state.selectedAnimationPositions);
    if (direction < 0) {
      for (let position = 1; position < order.length; position += 1) {
        if (selectedOld.has(order[position]) && !selectedOld.has(order[position - 1])) [order[position - 1], order[position]] = [order[position], order[position - 1]];
      }
    } else {
      for (let position = order.length - 2; position >= 0; position -= 1) {
        if (selectedOld.has(order[position]) && !selectedOld.has(order[position + 1])) [order[position], order[position + 1]] = [order[position + 1], order[position]];
      }
    }
    const nextSelection = order.flatMap((oldPosition, newPosition) => selectedOld.has(oldPosition) ? [newPosition] : []);
    commitAnimationOrder(order.map((position) => animation.frames[position] ?? 0), order, nextSelection);
  };
  const duplicateSelectedTiles = (): void => {
    if (!state.draft) return;
    const source = state.assets?.assets.find((entry) => entry.assetId === state.draft?.assetId && isWeaponAsset(entry));
    const animation = selectedWeaponAnimation(state.draft, assetInfo(source), state);
    const selected = state.selectedAnimationPositions.filter((position) => position >= 0 && position < animation.frames.length).sort((left, right) => left - right);
    if (selected.length === 0) return;
    if (selected.length === 1) {
      try {
        const duplicated = duplicateKeyframe(animation, selected[0]);
        commitAnimationOrder(duplicated.frames, duplicated.newToOldPositions, [duplicated.newIndex], duplicated.keyframeTimes);
      } catch (error) {
        state = { ...state, notice: error instanceof Error ? error.message : String(error) };
        render();
      }
      return;
    }
    const order = [...animation.frames.map((_, position) => position), ...selected];
    const firstNew = animation.frames.length;
    const nextFrames = order.map((position) => animation.frames[position] ?? 0);
    const nextTimelineFrames = Math.max(timelineFrameCount(animation), nextFrames.length);
    commitAnimationOrder(nextFrames, order, selected.map((_, index) => firstNew + index), evenKeyframeTimes(nextTimelineFrames, nextFrames.length), nextTimelineFrames / animation.framesPerSecond);
  };
  const reorderSelectedTilesBefore = (targetPosition: number): void => {
    if (!state.draft || draggedAnimationPosition === undefined) return;
    const source = state.assets?.assets.find((entry) => entry.assetId === state.draft?.assetId && isWeaponAsset(entry));
    const animation = selectedWeaponAnimation(state.draft, assetInfo(source), state);
    const selectedOld = new Set(state.selectedAnimationPositions.includes(draggedAnimationPosition) ? state.selectedAnimationPositions : [draggedAnimationPosition]);
    if (selectedOld.has(targetPosition)) return;
    const remaining = animation.frames.map((_, position) => position).filter((position) => !selectedOld.has(position));
    const insertion = Math.max(0, remaining.indexOf(targetPosition));
    const block = [...selectedOld].sort((left, right) => left - right);
    const order = [...remaining.slice(0, insertion), ...block, ...remaining.slice(insertion)];
    const nextSelection = order.flatMap((oldPosition, newPosition) => selectedOld.has(oldPosition) ? [newPosition] : []);
    commitAnimationOrder(order.map((position) => animation.frames[position] ?? 0), order, nextSelection);
  };
  const updateSelectedTileTransforms = (
    property: 'offset.0' | 'offset.1' | 'scale.0' | 'scale.1' | 'rotationDeg',
    numericValue: number,
    baseDraft = state.draft,
    recordHistory = true,
  ): void => {
    if (!baseDraft || !Number.isFinite(numericValue) || leftMirrorLocked()) return;
    if (recordHistory) rememberDraft();
    const draft = clone(baseDraft) as MutableWeaponDraft;
    const source = state.assets?.assets.find((entry) => entry.assetId === draft.assetId && isWeaponAsset(entry));
    const info = assetInfo(source);
    const animation = selectedWeaponAnimation(draft, info, state);
    const positions = state.selectedAnimationPositions.length > 0 ? state.selectedAnimationPositions : [state.previewStep];
    const transforms = { ...(animation.frameTransforms ?? {}) };
    for (const position of positions) {
      if (position < 0 || position >= animation.frames.length) continue;
      const current = frameTransformAt(animation, position);
      const offset = [...current.offset] as [number, number];
      const scale = [...current.scale] as [number, number];
      if (property === 'offset.0') offset[0] = numericValue;
      else if (property === 'offset.1') offset[1] = numericValue;
      else if (property === 'scale.0') scale[0] = Math.max(0.05, numericValue);
      else if (property === 'scale.1') scale[1] = Math.max(0.05, numericValue);
      transforms[String(position)] = { offset, scale, rotationDeg: property === 'rotationDeg' ? numericValue : current.rotationDeg };
    }
    writeSelectedAnimation(draft, info, state, { ...animation, frameTransforms: transforms });
    state = { ...state, draft, dirty: true, notice: undefined };
  };
  const resetSelectedTileTransforms = (): void => {
    if (!state.draft || leftMirrorLocked()) return;
    rememberDraft();
    const draft = clone(state.draft) as MutableWeaponDraft;
    const source = state.assets?.assets.find((entry) => entry.assetId === draft.assetId && isWeaponAsset(entry));
    const info = assetInfo(source);
    const animation = selectedWeaponAnimation(draft, info, state);
    const transforms = { ...(animation.frameTransforms ?? {}) };
    for (const position of state.selectedAnimationPositions) delete transforms[String(position)];
    writeSelectedAnimation(draft, info, state, { ...animation, frameTransforms: Object.keys(transforms).length > 0 ? transforms : undefined });
    state = { ...state, draft, dirty: true, notice: undefined };
    render();
  };
  const createCustomLeft = (): void => {
    if (!state.draft || !isMirroredLeft(state.draft)) return;
    rememberDraft();
    const draft = clone(state.draft) as MutableWeaponDraft;
    const source = state.assets?.assets.find((entry) => entry.assetId === draft.assetId && isWeaponAsset(entry));
    const info = assetInfo(source);
    ensureDirectionalAttackDraft(draft, info, 'right');
    ensureDirectionalAttackDraft(draft, info, 'left');
    state = { ...state, draft, selectedAnimationPositions: [0], previewStep: 0, dirty: true, notice: 'Custom LEFT created from the mirrored RIGHT package' };
    render();
  };
  const restoreMirroredLeft = (): void => {
    if (!state.draft || isMirroredLeft(state.draft)) return;
    rememberDraft();
    const draft = clone(state.draft) as MutableWeaponDraft;
    if (draft.directionalAttacks) delete draft.directionalAttacks.left;
    state = { ...state, draft, selectedAnimationPositions: [0], previewStep: 0, dirty: true, notice: 'LEFT restored to the RIGHT mirror' };
    render();
  };
  const save = async (): Promise<void> => {
    if (!state.draft || !state.dirty) return;
    state = { ...state, saving: true, notice: 'Saving weapon…' }; render();
    const isNew = !state.weapons.some((entry) => entry.weaponId === state.draft?.weaponId);
    try {
      const response = await fetch(`/__character-studio/weapon/${isNew ? 'create' : 'update'}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ weapon: state.draft, ...(isNew ? {} : { expectedRevision: state.revision }) }) });
      const payload = await response.json() as { ok: boolean; data?: { weapon: WeaponDefinition; revision: string }; error?: { message?: string } };
      if (!response.ok || !payload.ok || !payload.data) throw new Error(payload.error?.message ?? 'Weapon save failed');
      const next = state.weapons.filter((entry) => entry.weaponId !== payload.data?.weapon.weaponId).concat({ ...payload.data.weapon, revision: payload.data.revision });
      state = { ...state, weapons: next, selectedId: payload.data.weapon.weaponId, draft: clone(payload.data.weapon), revision: payload.data.revision, dirty: false, saving: false, notice: 'Saved weapon' }; render();
    } catch (error) { state = { ...state, saving: false, notice: error instanceof Error ? error.message : String(error) }; render(); }
  };
  const onClick = (event: MouseEvent): void => {
    if (resizeController?.click(event)) return;
    const target = event.target as HTMLElement;
    const shelfBackdrop = target.closest<HTMLElement>('[data-weapon-shelf-backdrop]');
    if (shelfBackdrop && target === shelfBackdrop) { state = { ...state, assetShelfOpen: false, notice: undefined }; render(); return; }
    const tilePickerBackdrop = target.closest<HTMLElement>('[data-weapon-tile-picker-backdrop]');
    if (tilePickerBackdrop && target === tilePickerBackdrop) { state = { ...state, sourceTilePickerOpen: false, notice: undefined }; render(); return; }
    const weaponButton = target.closest<HTMLElement>('[data-weapon-id]');
    if (weaponButton) { const weapon = state.weapons.find((entry) => entry.weaponId === weaponButton.dataset.weaponId); if (weapon) select(weapon, weapon.revision); return; }
    const animationId = target.closest<HTMLElement>('[data-weapon-animation-id]')?.dataset.weaponAnimationId;
    if (animationId === 'idle' || animationId === 'attack' || animationId === 'impact') { stopPreview(); state = { ...state, selectedAnimation: animationId, selectedAnimationPositions: [0], selectedPreviewFrame: 0, previewStep: 0 }; render(); return; }
    const attackDirection = target.closest<HTMLElement>('[data-weapon-attack-direction]')?.dataset.weaponAttackDirection as WeaponAttackDirection | undefined;
    if (attackDirection && WEAPON_ATTACK_DIRECTIONS.includes(attackDirection)) { stopPreview(); const selectedHitboxId = state.draft ? resolvedSelectedHitboxId(weaponHitboxes(state.draft, attackDirection), state.selectedHitboxId) : state.selectedHitboxId; state = { ...state, selectedAttackDirection: attackDirection, selectedHitboxId, selectedAnimationPositions: [0], selectedPreviewFrame: 0, previewStep: 0 }; render(); return; }
    const hitboxSelector = target.closest<HTMLElement>('[data-select-weapon-hitbox]');
    if (hitboxSelector) { selectWeaponHitbox(hitboxSelector.dataset.selectWeaponHitbox ?? ''); return; }
    const spanToggle = target.closest<HTMLElement>('[data-weapon-span-toggle]');
    if (spanToggle) {
      toggleWeaponSpan(spanToggle.dataset.weaponSpanToggle ?? '', Number(spanToggle.dataset.weaponSpanFrame));
      return;
    }
    const sourceTile = target.closest<HTMLElement>('[data-weapon-source-frame]');
    if (sourceTile) {
      const frame = Number(sourceTile.dataset.weaponSourceFrame);
      if (state.sourceTilePickerOpen) {
        const selected = new Set(state.selectedPickerFrames);
        if (selected.has(frame)) selected.delete(frame); else selected.add(frame);
        state = { ...state, selectedPickerFrames: [...selected].sort((left, right) => left - right) };
        render();
      } else addSourceTile(frame);
      return;
    }
    const holdAction = target.closest<HTMLElement>('[data-action="adjust-keyframe-hold"]');
    if (holdAction) { adjustTileHold(Number(holdAction.dataset.keyframeIndex ?? -1), Number(holdAction.dataset.holdDelta ?? 0)); return; }
    const sequenceTile = target.closest<HTMLElement>('[data-weapon-animation-position]');
    if (sequenceTile && state.draft) {
      const position = Number(sequenceTile.dataset.weaponAnimationPosition);
      const source = state.assets?.assets.find((entry) => entry.assetId === state.draft?.assetId && isWeaponAsset(entry));
      const animation = selectedWeaponAnimation(state.draft, assetInfo(source), state);
      let selectedPositions: number[];
      if (event.shiftKey) {
        const anchor = state.selectedAnimationPositions.at(-1) ?? state.previewStep;
        const from = Math.min(anchor, position);
        const through = Math.max(anchor, position);
        selectedPositions = Array.from({ length: through - from + 1 }, (_, index) => from + index);
      } else if (event.ctrlKey || event.metaKey) {
        selectedPositions = toggleTimelineSelection(state.selectedAnimationPositions, position);
        if (selectedPositions.length === 0) selectedPositions = [position];
      } else selectedPositions = [position];
      const previewTarget = previewTargetAtKeyframe(animation, position);
      state = { ...state, selectedAnimationPositions: selectedPositions, selectedPreviewFrame: previewTarget?.sourceFrame ?? 0, previewStep: previewTarget?.timelineFrame ?? 0 };
      render();
      return;
    }
    const action = target.closest<HTMLElement>('[data-action]')?.dataset.action;
    if (action === 'previous-weapon-frame' || action === 'next-weapon-frame') {
      if (!state.draft) return;
      const draft = state.draft;
      const source = state.assets?.assets.find((entry) => entry.assetId === draft.assetId && isWeaponAsset(entry));
      const animation = selectedWeaponAnimation(draft, assetInfo(source), state);
  const timelineFrames = timelineFrameCount(normalizedWeaponAnimation(animation));
      const nextStep = action === 'previous-weapon-frame'
        ? Math.max(0, state.previewStep - 1)
        : Math.min(Math.max(0, timelineFrames - 1), state.previewStep + 1);
      const expanded = expandAnimationClip(animation);
      state = { ...state, previewStep: nextStep, selectedPreviewFrame: expanded.sourceFrames[nextStep] ?? 0 };
      updateCombinedPreviewDom(container, draft, state);
      return;
    }
    const inspectorTab = target.closest<HTMLElement>('[data-weapon-inspector-tab]')?.dataset.weaponInspectorTab as WeaponInspectorTab | undefined;
    if (inspectorTab && WEAPON_INSPECTOR_TABS.some((tab) => tab.id === inspectorTab)) {
      state = { ...state, selectedInspectorTab: inspectorTab };
      render();
      return;
    }
    if (action === 'new-weapon') { select(makeNewWeapon()); return; }
    if (action === 'open-weapon-tile-picker') { state = { ...state, sourceTilePickerOpen: true, selectedPickerFrames: [], notice: undefined }; render(); return; }
    if (action === 'close-weapon-tile-picker') { state = { ...state, sourceTilePickerOpen: false, selectedPickerFrames: [], notice: undefined }; render(); return; }
    if (action === 'add-selected-weapon-tiles') { const frames = [...state.selectedPickerFrames]; state = { ...state, sourceTilePickerOpen: false, selectedPickerFrames: [] }; addSourceTiles(frames); return; }
    if (action === 'distribute-weapon-tiles') { distributeSelectedAnimation(); return; }
    if (action === 'create-custom-left') { createCustomLeft(); return; }
    if (action === 'restore-mirrored-left') { restoreMirroredLeft(); return; }
    const transformTool = target.closest<HTMLElement>('[data-weapon-transform-tool]')?.dataset.weaponTransformTool as WeaponTransformTool | undefined;
    if (transformTool === 'move' || transformTool === 'scale' || transformTool === 'rotate') { state = { ...state, transformTool }; render(); return; }
    if (action === 'show-weapon-visual-controls') { state = { ...state, selectedInspectorTab: 'visual' }; render(); return; }
    if (action === 'reset-weapon-tile-transform') { resetSelectedTileTransforms(); return; }
    if (action === 'delete-weapon-tiles') { deleteSelectedTiles(); return; }
    if (action === 'duplicate-weapon-tiles') { duplicateSelectedTiles(); return; }
    if (action === 'move-weapon-tiles-left') { moveSelectedTiles(-1); return; }
    if (action === 'move-weapon-tiles-right') { moveSelectedTiles(1); return; }
    if (action === 'add-weapon-hitbox') { addWeaponHitbox(); return; }
    const removeHitboxId = target.closest<HTMLElement>('[data-remove-weapon-hitbox]')?.dataset.removeWeaponHitbox;
    if (removeHitboxId) { removeWeaponHitbox(removeHitboxId); return; }
    if (action === 'play-weapon-preview') {
      if (previewTimer !== undefined) { stopPreview(); render(); return; }
      if (!state.draft) return;
      const previewDraft = state.draft;
      const source = state.assets?.assets.find((entry) => entry.assetId === previewDraft.assetId && isWeaponAsset(entry));
      const animation = selectedWeaponAnimation(previewDraft, assetInfo(source), state);
      state = { ...state, previewPlaying: true, previewStep: 0 };
      previewTimer = window.setInterval(() => {
        if (!state.draft) { stopPreview(); return; }
        const currentSource = state.assets?.assets.find((entry) => entry.assetId === state.draft?.assetId && isWeaponAsset(entry));
        const currentAnimation = selectedWeaponAnimation(state.draft, assetInfo(currentSource), state);
        const currentTimelineFrames = timelineFrameCount(currentAnimation);
        const next = state.previewStep + 1;
        if (next >= currentTimelineFrames) {
          if (currentAnimation.loop) state = { ...state, previewStep: 0 };
          else { stopPreview(); state = { ...state, previewStep: Math.max(0, currentTimelineFrames - 1) }; }
        } else state = { ...state, previewStep: next };
        if (state.draft) updateCombinedPreviewDom(container, state.draft, state);
      }, 1000 / Math.max(1, animation.framesPerSecond));
      updateCombinedPreviewDom(container, previewDraft, state);
      return;
    }
    if (action === 'open-weapon-source-library') { state = { ...state, assetShelfOpen: true, notice: undefined }; render(); return; }
    if (action === 'close-weapon-source-library') { state = { ...state, assetShelfOpen: false, notice: undefined }; render(); return; }
    if (action === 'select-weapon-asset') {
      const assetId = target.closest<HTMLElement>('[data-weapon-asset-id]')?.dataset.weaponAssetId;
      if (assetId) { updateDraft('assetId', assetId); state = { ...state, assetShelfOpen: false, selectedPreviewFrame: 0 }; render(); }
      return;
    }
    if (action === 'upload-weapon-source') { container.querySelector<HTMLInputElement>('[data-weapon-upload]')?.click(); return; }
    if (action === 'save-weapon') void save();
  };
  const onInput = (event: Event): void => {
    const target = event.target as HTMLInputElement | HTMLSelectElement;
    if (target.matches('[data-weapon-upload]')) {
      const upload = target instanceof HTMLInputElement ? target : undefined;
      const file = upload?.files?.[0];
      if (upload) upload.value = '';
      if (file) void importSource(file);
      return;
    }
    const importField = target.dataset.weaponImportField;
    if (importField && importField in state.importForm) { state = { ...state, importForm: { ...state.importForm, [importField]: target.value } }; return; }
    if (target.matches('[data-weapon-character-id]')) { stopPreview(); state = { ...state, selectedCharacterId: target.value, previewStep: 0 }; render(); return; }
    if (target.matches('[data-weapon-onion-skin]')) { state = { ...state, onionSkin: target instanceof HTMLInputElement && target.checked }; render(); return; }
    const transformField = target.dataset.weaponTransformField as 'offset.0' | 'offset.1' | 'scale.0' | 'scale.1' | 'rotationDeg' | undefined;
    if (transformField) {
      updateSelectedTileTransforms(transformField, Number(target.value));
      if (state.draft) updateCombinedPreviewDom(container, state.draft, state);
      if (event.type === 'change') render();
      return;
    }
    const eventFrame = target.dataset.weaponEventFrame;
    if (eventFrame !== undefined) { updateWeaponEvent(Number(eventFrame), target.value); return; }
    const path = target.dataset.weaponField;
    if (!path) return;
    updateDraft(path, target instanceof HTMLInputElement && target.type === 'checkbox' ? target.checked : target.value);
    if (state.draft) {
      const refreshHitboxGeometry = path.startsWith('hitboxes.') || /^directionalAttacks\.(right|left|up|down)\.hitboxes\./.test(path);
      updateCombinedPreviewDom(container, state.draft, state, refreshHitboxGeometry);
    }
    if (event.type === 'change' && (path.startsWith('hitboxes.') || path.startsWith('visual.') || path.startsWith('animations.') || path.startsWith('directionalAttacks.'))) { render(); return; }
    if (target instanceof HTMLSelectElement || (target instanceof HTMLInputElement && target.type === 'checkbox')) render();
  };
  const onDragStart = (event: DragEvent): void => {
    if ((event.target as HTMLElement).closest('[data-timeline-resize-handle]')) { event.preventDefault(); return; }
    const tile = (event.target as HTMLElement).closest<HTMLElement>('[data-weapon-animation-position]');
    if (!tile) return;
    draggedAnimationPosition = Number(tile.dataset.weaponAnimationPosition);
    event.dataTransfer?.setData('text/plain', String(draggedAnimationPosition));
    if (event.dataTransfer) event.dataTransfer.effectAllowed = 'move';
  };
  const onDragOver = (event: DragEvent): void => {
    if ((event.target as HTMLElement).closest('[data-weapon-animation-position]')) event.preventDefault();
  };
  const onDrop = (event: DragEvent): void => {
    const tile = (event.target as HTMLElement).closest<HTMLElement>('[data-weapon-animation-position]');
    if (!tile) return;
    event.preventDefault();
    reorderSelectedTilesBefore(Number(tile.dataset.weaponAnimationPosition));
    draggedAnimationPosition = undefined;
  };
  const onPointerDown = (event: PointerEvent): void => {
    if (resizeController?.pointerDown(event)) return;
    const sprite = (event.target as HTMLElement).closest<HTMLElement>('[data-weapon-preview-transform]');
    if (!sprite || !state.draft || event.button !== 0) return;
    event.preventDefault();
    stopPreview();
    rememberDraft();
    const stage = sprite.closest<HTMLElement>('.weapon-stage');
    const bounds = stage?.getBoundingClientRect();
    const centerX = bounds ? bounds.left + bounds.width / 2 : event.clientX;
    const centerY = bounds ? bounds.top + bounds.height / 2 : event.clientY;
    transformDrag = {
      baseDraft: clone(state.draft),
      startX: event.clientX,
      startY: event.clientY,
      centerX,
      centerY,
      startAngle: Math.atan2(event.clientY - centerY, event.clientX - centerX),
    };
    sprite.setPointerCapture(event.pointerId);
  };
  const onPointerMove = (event: PointerEvent): void => {
    if (resizeController?.pointerMove(event)) return;
    if (!transformDrag) return;
    const draft = clone(transformDrag.baseDraft) as MutableWeaponDraft;
    const source = state.assets?.assets.find((entry) => entry.assetId === draft.assetId && isWeaponAsset(entry));
    const info = assetInfo(source);
    const animation = selectedWeaponAnimation(draft, info, state);
    const positions = state.selectedAnimationPositions.length > 0 ? state.selectedAnimationPositions : [state.previewStep];
    const transforms = { ...(animation.frameTransforms ?? {}) };
    const globalScale = draft.visual?.scale ?? [1, 1];
    const deltaX = (event.clientX - transformDrag.startX) / (Math.max(0.05, globalScale[0]) * 2.8);
    const deltaY = (event.clientY - transformDrag.startY) / (Math.max(0.05, globalScale[1]) * 2.8);
    const scaleFactor = Math.max(0.05, 1 + ((event.clientX - transformDrag.startX) - (event.clientY - transformDrag.startY)) / 140);
    const angle = Math.atan2(event.clientY - transformDrag.centerY, event.clientX - transformDrag.centerX);
    const rotationDelta = (angle - transformDrag.startAngle) * 180 / Math.PI;
    for (const position of positions) {
      if (position < 0 || position >= animation.frames.length) continue;
      const baseAnimation = selectedWeaponAnimation(transformDrag.baseDraft, info, state);
      const current = frameTransformAt(baseAnimation, position);
      transforms[String(position)] = state.transformTool === 'move'
        ? { ...current, offset: [transformValue(current.offset[0] + deltaX), transformValue(current.offset[1] + deltaY)] }
        : state.transformTool === 'scale'
          ? { ...current, scale: [transformValue(Math.max(0.05, current.scale[0] * scaleFactor)), transformValue(Math.max(0.05, current.scale[1] * scaleFactor))] }
          : { ...current, rotationDeg: transformValue(current.rotationDeg + rotationDelta) };
    }
    writeSelectedAnimation(draft, info, state, { ...animation, frameTransforms: transforms });
    state = { ...state, draft, dirty: true, notice: undefined };
    updateCombinedPreviewDom(container, draft, state);
  };
  const onPointerUp = (event: PointerEvent): void => {
    if (resizeController?.pointerUp(event)) return;
    if (!transformDrag) return;
    transformDrag = undefined;
    render();
  };
  const onPointerCancel = (event: PointerEvent): void => {
    if (resizeController?.pointerCancel(event)) return;
    if (!transformDrag) return;
    transformDrag = undefined;
    render();
  };
  const onKeyDown = (event: KeyboardEvent): void => {
    if (resizeController?.keyDown(event)) return;
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'z') {
      event.preventDefault();
      if (event.shiftKey) redo(); else undo();
      return;
    }
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'y') {
      event.preventDefault();
      redo();
      return;
    }
    const target = event.target as HTMLElement | null;
    if ((event.key === 'Delete' || event.key === 'Backspace') && !target?.closest('input, select, textarea')) {
      event.preventDefault();
      deleteSelectedTiles();
    }
  };
  container.addEventListener('click', onClick);
  container.addEventListener('input', onInput);
  container.addEventListener('change', onInput);
  container.addEventListener('dragstart', onDragStart);
  container.addEventListener('dragover', onDragOver);
  container.addEventListener('drop', onDrop);
  container.addEventListener('pointerdown', onPointerDown);
  window.addEventListener('pointermove', onPointerMove);
  window.addEventListener('pointerup', onPointerUp);
  window.addEventListener('pointercancel', onPointerCancel);
  window.addEventListener('keydown', onKeyDown);
  render(); void load();
  return () => {
    container.removeEventListener('click', onClick);
    container.removeEventListener('input', onInput);
    container.removeEventListener('change', onInput);
    container.removeEventListener('dragstart', onDragStart);
    container.removeEventListener('dragover', onDragOver);
    container.removeEventListener('drop', onDrop);
    container.removeEventListener('pointerdown', onPointerDown);
    window.removeEventListener('pointermove', onPointerMove);
    window.removeEventListener('pointerup', onPointerUp);
    window.removeEventListener('pointercancel', onPointerCancel);
    window.removeEventListener('keydown', onKeyDown);
    resizeController?.dispose();
    container.classList.remove('is-character-studio-host');
  };
}
