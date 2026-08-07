import './character-studio.css';

import { characterPackages } from 'virtual-character-content';
import type { CharacterStudioAssetCatalog, CharacterStudioAssetEntry } from '../content/characters/characterAssetCatalog';
import type { WeaponAnimationDocument, WeaponAnimationSet, WeaponAttackTrackDocument, WeaponDefinition, WeaponHitboxDocument, WeaponHitboxShape } from '../content/weapons/types';
import { resolveAssetUrl } from '../infrastructure/assets/assetUrls';
import { ensureStudioModeTabs } from './StudioModeTabs';

type WeaponAnimationId = 'idle' | 'attack' | 'impact';

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
  readonly selectedPreviewFrame: number;
  readonly selectedCharacterId: string;
  readonly previewStep: number;
  readonly previewPlaying: boolean;
  readonly draft?: WeaponDefinition;
  readonly revision?: string;
  readonly dirty: boolean;
  readonly saving: boolean;
  readonly assetShelfOpen: boolean;
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
  reach?: MutableWeaponScalingGroup;
}

type MutableWeaponHitbox = { -readonly [Key in keyof WeaponHitboxDocument]: WeaponHitboxDocument[Key] };
type MutableWeaponTrack = { hitboxSpans: Array<{ hitboxId: string; from: number; through: number }>; events: Array<{ at: number; eventId: string; payload?: unknown }> };
type Mutable<T> = { -readonly [Key in keyof T]: T[Key] };
type MutableWeaponDraft = Omit<Mutable<WeaponDefinition>, 'scaling' | 'hitboxes' | 'attackTrack'> & { scaling?: MutableWeaponScaling; hitboxes?: Record<string, MutableWeaponHitbox>; attackTrack?: MutableWeaponTrack };

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

function weaponHitboxes(weapon: WeaponDefinition): Readonly<Record<string, WeaponHitboxDocument>> {
  return weapon.hitboxes ?? {
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

function weaponTrack(weapon: WeaponDefinition, animation: WeaponAnimationDocument): WeaponAttackTrackDocument {
  return weapon.attackTrack ?? {
    hitboxSpans: [{ hitboxId: Object.keys(weaponHitboxes(weapon))[0] ?? 'primary', from: 0, through: Math.max(0, animation.frames.length - 1) }],
    events: [],
  };
}

function selectedCharacter(): StudioCharacterPackage | undefined {
  return characterPackages.find((entry) => entry.character.kind === 'player') ?? characterPackages[0];
}

function characterClip(character: StudioCharacterPackage | undefined, actionId: string): { readonly id: string; readonly frames: readonly number[]; readonly framesPerSecond: number } | undefined {
  if (!character) return undefined;
  const clips = character.visualSet.clips;
  const id = clips[actionId] ? actionId : clips.trick ? 'trick' : clips.idle ? 'idle' : Object.keys(clips)[0];
  const clip = id ? clips[id] : undefined;
  return clip ? { id: id ?? 'idle', frames: clip.frames, framesPerSecond: clip.framesPerSecond } : undefined;
}

function hitboxDimensions(hitbox: WeaponHitboxDocument): { readonly width: number; readonly height: number; readonly offsetX: number; readonly offsetY: number; readonly shape: WeaponHitboxShape } {
  if (hitbox.shape === 'sector') {
    const diameter = (hitbox.outerRadius ?? hitbox.offsetX + hitbox.width / 2) * 2;
    return { width: diameter, height: diameter, offsetX: 0, offsetY: 0, shape: hitbox.shape };
  }
  if (hitbox.shape === 'circle') {
    const radius = hitbox.radius ?? hitbox.radiusX ?? hitbox.width / 2;
    return { width: radius * 2, height: radius * 2, offsetX: hitbox.offsetX, offsetY: hitbox.offsetY, shape: hitbox.shape };
  }
  return { width: hitbox.width, height: hitbox.height, offsetX: hitbox.offsetX, offsetY: hitbox.offsetY, shape: hitbox.shape };
}

function assetInfo(entry: CharacterStudioAssetEntry | undefined): { readonly url: string; readonly width: number; readonly height: number; readonly columns: number; readonly rows: number; readonly count: number } {
  if (!entry) return { url: '', width: 1, height: 1, columns: 1, rows: 1, count: 1 };
  if (!entry.frame) return { url: resolveAssetUrl(entry.sourcePath), width: entry.dimensions.width, height: entry.dimensions.height, columns: 1, rows: 1, count: 1 };
  return { url: resolveAssetUrl(entry.sourcePath), width: entry.frame.width, height: entry.frame.height, columns: entry.frame.columns, rows: entry.frame.rows, count: entry.frame.count };
}

function isWeaponAsset(entry: CharacterStudioAssetEntry): boolean {
  return entry.tags.includes('weapon');
}

function defaultWeaponAnimations(info: ReturnType<typeof assetInfo>): WeaponAnimationSet {
  const attackFrames = Array.from({ length: Math.min(info.count, 4) }, (_, index) => index);
  return {
    idle: { frames: [0], framesPerSecond: 8, loop: true, loopMode: 'wrap' },
    attack: { frames: attackFrames.length > 0 ? attackFrames : [0], framesPerSecond: 12, loop: false, loopMode: 'wrap' },
    impact: { frames: [Math.max(info.count - 1, 0)], framesPerSecond: 12, loop: false, loopMode: 'wrap' },
  };
}

function weaponAnimations(weapon: WeaponDefinition | undefined, info: ReturnType<typeof assetInfo>): WeaponAnimationSet {
  const current = weapon?.animations;
  const fallback = defaultWeaponAnimations(info);
  const clamp = (clip: WeaponAnimationDocument): WeaponAnimationDocument => {
    const frames = clip.frames.map((frame) => Math.max(0, Math.min(integerValue(frame), info.count - 1))).filter((frame) => Number.isInteger(frame));
    return { ...clip, frames: frames.length > 0 ? frames : [0] };
  };
  return {
    idle: clamp(current?.idle ?? fallback.idle),
    attack: clamp(current?.attack ?? fallback.attack),
    impact: clamp(current?.impact ?? fallback.impact),
  };
}

function renderWeaponFrameTile(entry: CharacterStudioAssetEntry | undefined, frame: number, selected: boolean): string {
  const info = assetInfo(entry);
  const column = frame % info.columns;
  const row = Math.floor(frame / info.columns);
  return `<button type="button" class="studio-frame-tile${selected ? ' is-selected' : ''}" data-weapon-frame="${frame}" title="Source frame ${frame}"><span class="studio-frame-image" style="--thumb-w:${info.width}px;--thumb-h:${info.height}px;--sheet-thumb-w:${info.width * info.columns}px;--sheet-thumb-h:${info.height * info.rows}px;--sheet-offset-x:${-column * info.width}px;--sheet-offset-y:${-row * info.height}px"><img src="${escapeHtml(info.url)}" alt="" aria-hidden="true" draggable="false" /></span><small>${frame}</small></button>`;
}

function field(label: string, path: string, value: unknown, unit: string, step = '1'): string {
  const displayValue = step === '1' ? integerValue(value) : (Number.isFinite(Number(value)) ? Number(value) : 1);
  return `<label class="studio-field"><span>${label}<small>${unit}</small></span><input type="number" step="${step}" inputmode="numeric" value="${escapeHtml(displayValue)}" data-weapon-field="${path}" /></label>`;
}

function makeNewWeapon(): WeaponDefinition {
  return {
    version: 1,
    weaponId: 'new-weapon',
    displayName: 'New Weapon',
    category: 'melee',
    characterActionId: 'trick',
    animations: defaultWeaponAnimations(assetInfo(undefined)),
    visual: { sourceOffset: [0, 0] },
    hitboxes: {
      primary: { shape: 'sector', width: 32, height: 18, offsetX: 24, offsetY: 0, outerRadius: 33, arcWidthRad: 1.35 },
    },
    attackTrack: { hitboxSpans: [{ hitboxId: 'primary', from: 0, through: 0 }], events: [] },
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

function renderWeaponVisualFields(weapon: WeaponDefinition): string {
  const offset = weapon.visual?.sourceOffset ?? [0, 0];
  const animationOffset = weapon.visual?.animationOffsets?.attack ?? [0, 0];
  const scale = weapon.visual?.scale ?? [1, 1];
  return `<section class="studio-inspector-section" data-weapon-visual><div class="studio-section-heading"><span class="studio-kicker">Visual</span><strong>Attachment alignment</strong></div><p class="studio-help">The weapon layer follows the character’s existing anchor. Offsets are art alignment only; hitboxes stay in their own authored coordinates.</p><div class="studio-field-grid">${field('Default X', 'visual.sourceOffset.0', offset[0], 'source pixels')}${field('Default Y', 'visual.sourceOffset.1', offset[1], 'source pixels')}${field('Scale X', 'visual.scale.0', scale[0], 'multiplier', '0.05')}${field('Scale Y', 'visual.scale.1', scale[1], 'multiplier', '0.05')}</div><div class="studio-subheading">Attack clip override</div><div class="studio-field-grid">${field('Attack X', 'visual.animationOffsets.attack.0', animationOffset[0], 'source pixels')}${field('Attack Y', 'visual.animationOffsets.attack.1', animationOffset[1], 'source pixels')}</div><label class="studio-field studio-field--wide"><span>Facing mode<small>attachment rotation</small></span><select data-weapon-field="visual.facingMode"><option value="vector" ${(weapon.visual?.facingMode ?? 'vector') === 'vector' ? 'selected' : ''}>Vector rotate</option><option value="horizontal-flip" ${weapon.visual?.facingMode === 'horizontal-flip' ? 'selected' : ''}>Horizontal flip</option></select></label></section>`;
}

function renderWeaponHitboxEditor(weapon: WeaponDefinition): string {
  const hitboxes = weaponHitboxes(weapon);
  const rows = Object.entries(hitboxes).map(([hitboxId, hitbox]) => {
    const shape = hitbox.shape;
    const shapeFields = shape === 'sector'
      ? `${field('Outer radius', `hitboxes.${hitboxId}.outerRadius`, hitbox.outerRadius ?? hitbox.offsetX + hitbox.width / 2, 'world units')}${field('Arc width', `hitboxes.${hitboxId}.arcWidthRad`, hitbox.arcWidthRad ?? 1.35, 'radians', '0.05')}`
      : shape === 'circle'
        ? field('Radius', `hitboxes.${hitboxId}.radius`, hitbox.radius ?? hitbox.width / 2, 'world units')
        : '';
    return `<div class="studio-hitbox-row studio-hitbox-row--expanded"><div class="studio-hitbox-row-heading"><span class="hitbox-chip">${escapeHtml(hitboxId)}</span><button type="button" class="studio-icon-button is-danger" data-remove-weapon-hitbox="${escapeHtml(hitboxId)}">×</button></div><label class="studio-field"><span>Shape<small>runtime primitive</small></span><select data-weapon-field="hitboxes.${hitboxId}.shape"><option value="rectangle" ${shape === 'rectangle' ? 'selected' : ''}>Rectangle</option><option value="circle" ${shape === 'circle' ? 'selected' : ''}>Circle</option><option value="ellipse" ${shape === 'ellipse' ? 'selected' : ''}>Ellipse</option><option value="sector" ${shape === 'sector' ? 'selected' : ''}>Sector</option></select></label>${field('Width', `hitboxes.${hitboxId}.width`, hitbox.width, 'world units')}${field('Height', `hitboxes.${hitboxId}.height`, hitbox.height, 'world units')}${field('Offset X', `hitboxes.${hitboxId}.offsetX`, hitbox.offsetX, 'local units')}${field('Offset Y', `hitboxes.${hitboxId}.offsetY`, hitbox.offsetY, 'local units')}${shapeFields}${field('Damage ×', `hitboxes.${hitboxId}.damageMultiplier`, hitbox.damageMultiplier ?? 1, 'multiplier', '0.05')}${field('Knockback ×', `hitboxes.${hitboxId}.knockbackMultiplier`, hitbox.knockbackMultiplier ?? 1, 'multiplier', '0.05')}</div>`;
  }).join('');
  return `<section class="studio-inspector-section studio-weapon-hitbox-section"><div class="studio-section-heading"><span class="studio-kicker">Hitboxes</span><strong>Named attack geometry</strong><button type="button" class="studio-icon-button" data-action="add-weapon-hitbox">+</button></div><p class="studio-help">Every named shape can have its own damage multiplier and its own active frame window. The preview highlights all shapes at the current attack position.</p>${rows || '<p class="studio-empty-note">Add a named hitbox to author weapon contact geometry.</p>'}</section>`;
}

function renderWeaponTrackEditor(weapon: WeaponDefinition, attack: WeaponAnimationDocument): string {
  const hitboxes = weaponHitboxes(weapon);
  const track = weaponTrack(weapon, attack);
  const cells = (hitboxId: string): string => attack.frames.map((_, index) => `<button type="button" class="timeline-cell${track.hitboxSpans.some((span) => span.hitboxId === hitboxId && span.from <= index && index <= span.through) ? ' is-hot' : ''}" data-weapon-span-toggle="${escapeHtml(hitboxId)}" data-weapon-span-frame="${index}" aria-label="${escapeHtml(hitboxId)} frame ${index}"></button>`).join('');
  const eventInputs = attack.frames.map((_, index) => {
    const event = track.events?.find((candidate) => candidate.at === index);
    return `<label class="weapon-event-cell"><span>${index}</span><input type="text" value="${escapeHtml(event?.eventId ?? '')}" placeholder="event" data-weapon-event-frame="${index}" /></label>`;
  }).join('');
  return `<section class="studio-track-editor"><div class="studio-section-bar"><div><span class="studio-kicker">Attack event track</span><strong>Hitbox activation windows</strong></div><span class="studio-muted">Click cells to toggle inclusive active frames</span></div><div class="studio-timeline"><div class="timeline-ruler">${attack.frames.map((_, index) => `<span>${String(index).padStart(2, '0')}</span>`).join('')}</div>${Object.keys(hitboxes).map((hitboxId) => `<div class="timeline-track-row"><span class="timeline-track-label" title="${escapeHtml(hitboxId)}">${escapeHtml(hitboxId)}</span>${cells(hitboxId)}</div>`).join('')}<div class="timeline-track-row timeline-event-row"><span class="timeline-track-label">EVENTS</span>${eventInputs}</div></div><p class="studio-help">Events are stable IDs such as <code>weapon.impact</code>. The runtime receives them at the exact attack-frame position.</p></section>`;
}

function renderWeaponPreview(
  weapon: WeaponDefinition,
  info: ReturnType<typeof assetInfo>,
  animationId: WeaponAnimationId,
  position: number,
  character: StudioCharacterPackage | undefined,
  characterInfo: ReturnType<typeof assetInfo>,
): string {
  if (!character) return renderWeaponPreviewLegacy(weapon, info, animationId, position);
  const animations = weaponAnimations(weapon, info);
  const animation = animations[animationId];
  const weaponFrame = animation.frames[position % Math.max(1, animation.frames.length)] ?? 0;
  const weaponColumn = weaponFrame % info.columns;
  const weaponRow = Math.floor(weaponFrame / info.columns);
  const characterAction = characterClip(character, weapon.characterActionId ?? weapon.animKey ?? 'trick');
  const characterFrame = characterAction?.frames[position % Math.max(1, characterAction.frames.length)] ?? 0;
  const characterColumn = characterFrame % characterInfo.columns;
  const characterRow = Math.floor(characterFrame / characterInfo.columns);
  const characterVisual = character?.visualSet;
  const characterFrameVisual = characterVisual?.frameVisuals?.[String(characterFrame)] ?? {};
  const characterSourceOffset = characterFrameVisual.sourceOffset ?? characterVisual?.defaults.sourceOffset ?? [0, 0];
  const characterScale = (characterFrameVisual.scale ?? characterVisual?.defaults.scale ?? [1, 1])[0] * 2.8;
  const characterOrigin = characterFrameVisual.origin ?? characterVisual?.defaults.origin ?? [0.5, 0.5];
  const characterSprite = characterInfo.url ? `<span class="stage-sprite stage-character-sprite" style="--sheet-url:url('${escapeHtml(characterInfo.url)}');--frame-w:${characterInfo.width}px;--frame-h:${characterInfo.height}px;--sheet-w:${characterInfo.width * characterInfo.columns}px;--sheet-h:${characterInfo.height * characterInfo.rows}px;--frame-x:${characterColumn * characterInfo.width}px;--frame-y:${characterRow * characterInfo.height}px;--preview-scale:${characterScale};--origin-offset-x:${-characterOrigin[0] * characterInfo.width * characterScale}px;--origin-offset-y:${-characterOrigin[1] * characterInfo.height * characterScale}px;--offset-x:${characterSourceOffset[0] * characterScale}px;--offset-y:${characterSourceOffset[1] * characterScale}px"></span>` : '<span class="stage-character-fallback">CHARACTER</span>';
  const weaponOffset = weapon.visual?.animationOffsets?.[animationId] ?? weapon.visual?.sourceOffset ?? [0, 0];
  const weaponSprite = info.url ? `<span class="stage-sprite stage-weapon-sprite" style="--sheet-url:url('${escapeHtml(info.url)}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:${weaponColumn * info.width}px;--frame-y:${weaponRow * info.height}px;--preview-scale:2.8;--offset-x:${weaponOffset[0] * 2.8}px;--offset-y:${weaponOffset[1] * 2.8}px"></span>` : '<span class="weapon-preview-effect"></span>';
  const length = animation.frames.length;
  return `<section class="studio-preview-card weapon-preview-card"><div class="studio-preview-toolbar"><span class="studio-kicker">COMBINED PREVIEW</span><span class="studio-muted">${animationId.toUpperCase()} · position ${position + 1}/${length} · ${escapeHtml(character?.character.displayName ?? 'character')} + weapon</span><button type="button" class="studio-button studio-button--quiet" data-action="play-weapon-preview">▶ PLAY</button></div><div class="studio-stage weapon-stage"><span class="stage-axis stage-axis-x"></span><span class="stage-axis stage-axis-y"></span><span class="stage-anchor">+</span><span class="stage-label">PLAYER ANCHOR</span>${characterSprite}${weaponSprite}${renderWeaponHitboxGuides(weapon, position)}<span class="stage-caption"><b>${escapeHtml(weapon.displayName)}</b><span>CHARACTER ACTION ${escapeHtml(characterAction?.id ?? weapon.characterActionId ?? 'trick')} · WEAPON FRAME ${weaponFrame}</span></span></div><div class="studio-preview-footer"><span><i class="legend-dot legend-dot--cyan"></i> character layer</span><span><i class="legend-dot legend-dot--amber"></i> weapon layer</span><span><i class="legend-dot legend-dot--red"></i> named hitboxes</span></div></section>`;
}

function renderWeaponHitboxGuides(weapon: WeaponDefinition, position: number): string {
  const hitboxes = weaponHitboxes(weapon);
  const track = weapon.attackTrack;
  return Object.entries(hitboxes).map(([hitboxId, hitbox]) => {
    const dimensions = hitboxDimensions(hitbox);
    const isActive = track?.hitboxSpans.some((span) => span.hitboxId === hitboxId && span.from <= position && position <= span.through) ?? true;
    return `<span class="stage-hitbox stage-hitbox--${dimensions.shape}${isActive ? ' is-hot' : ''}" data-weapon-hitbox-id="${escapeHtml(hitboxId)}" style="width:${dimensions.width * 2}px;height:${dimensions.height * 2}px;transform:translate(-50%,-50%) translate(${dimensions.offsetX * 2}px,${dimensions.offsetY * 2}px)" title="${escapeHtml(hitboxId)}"><small>${escapeHtml(hitboxId)}</small></span>`;
  }).join('');
}

function renderWeaponPreviewLegacy(weapon: WeaponDefinition, info: ReturnType<typeof assetInfo>, animationId: WeaponAnimationId, frame: number): string {
  const offset = weapon.visual?.sourceOffset ?? [0, 0];
  const column = frame % info.columns;
  const row = Math.floor(frame / info.columns);
  const sprite = info.url ? `<span class="stage-sprite" style="--sheet-url:url('${escapeHtml(info.url)}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:${column * info.width}px;--frame-y:${row * info.height}px;--preview-scale:2.8;--offset-x:${offset[0] * 2.8}px;--offset-y:${offset[1] * 2.8}px"></span>` : '<span class="weapon-preview-effect"></span>';
  return `<section class="studio-preview-card weapon-preview-card"><div class="studio-preview-toolbar"><span class="studio-kicker">WEAPON PREVIEW</span><span class="studio-muted">${animationId.toUpperCase()} · frame ${frame} · ${info.width} x ${info.height} px</span></div><div class="studio-stage weapon-stage"><span class="stage-axis stage-axis-x"></span><span class="stage-axis stage-axis-y"></span><span class="stage-anchor">+</span><span class="stage-label">CHARACTER ANCHOR</span><span class="stage-body" style="width:${weapon.hitboxWidth * 2}px;height:${weapon.hitboxHeight * 2}px;transform:translate(-50%,-50%) translate(${weapon.hitboxOffset * 2}px,0)" ></span>${sprite}<span class="stage-caption"><b>${escapeHtml(weapon.displayName)}</b><span>${weapon.hitboxWidth} WORLD UNITS · ${weapon.hitboxDurationMs} MS ACTIVE</span></span></div><div class="studio-preview-footer"><span><i class="legend-dot legend-dot--amber"></i> weapon artwork</span><span><i class="legend-dot legend-dot--red"></i> gameplay hitbox</span></div></section>`;
}

function renderWeaponAnimationPanel(weapon: WeaponDefinition, source: CharacterStudioAssetEntry | undefined, state: WeaponStudioState): string {
  const info = assetInfo(source);
  const animations = weaponAnimations(weapon, info);
  const animation = animations[state.selectedAnimation];
  const trackEditor = state.selectedAnimation === 'attack' ? renderWeaponTrackEditor(weapon, animation) : '';
  return `<section class="studio-timeline-panel weapon-animation-panel"><div class="studio-section-bar"><div><span class="studio-kicker">Animation timeline</span><strong>Editing ${state.selectedAnimation}</strong></div><span class="studio-muted">Select frames from the weapon sheet</span></div><div class="studio-clip-tabs">${(['idle', 'attack', 'impact'] as const).map((id) => `<button type="button" class="studio-clip-tab${id === state.selectedAnimation ? ' is-active' : ''}" data-weapon-animation-id="${id}"><span>${id.toUpperCase()}</span><small>${animations[id].frames.length}F</small></button>`).join('')}</div><div class="studio-sheet-grid projectile-frame-grid">${Array.from({ length: info.count }, (_, frame) => renderWeaponFrameTile(source, frame, animation.frames.includes(frame))).join('')}</div><label class="studio-field studio-field--wide"><span>${state.selectedAnimation.toUpperCase()} frames<small>comma-separated source IDs</small></span><input type="text" value="${escapeHtml(animation.frames.join(', '))}" data-weapon-field="animations.${state.selectedAnimation}.frames" /></label><div class="studio-field-grid"><label class="studio-field"><span>FPS<small>frames / second</small></span><input type="number" min="1" max="240" step="1" inputmode="numeric" value="${integerValue(animation.framesPerSecond, 12)}" data-weapon-field="animations.${state.selectedAnimation}.framesPerSecond" /></label><label class="studio-field"><span>Loop mode<small>playback</small></span><select data-weapon-field="animations.${state.selectedAnimation}.loopMode"><option value="wrap" ${animation.loopMode !== 'ping-pong' ? 'selected' : ''}>Wrap</option><option value="ping-pong" ${animation.loopMode === 'ping-pong' ? 'selected' : ''}>Ping-pong</option></select></label></div><label class="studio-toggle-field"><input type="checkbox" data-weapon-field="animations.${state.selectedAnimation}.loop" ${animation.loop ? 'checked' : ''} /><span><strong>Loop ${state.selectedAnimation}</strong><small>Keep this weapon visual track playing</small></span></label>${trackEditor}</section>`;
}

function applyWeaponPreview(container: HTMLDivElement, weapon: WeaponDefinition): void {
  const body = container.querySelector<HTMLElement>('.weapon-preview-card .stage-body');
  if (body) {
    body.style.width = `${weapon.hitboxWidth * 2}px`;
    body.style.height = `${weapon.hitboxHeight * 2}px`;
    body.style.transform = `translate(-50%,-50%) translate(${weapon.hitboxOffset * 2}px,0)`;
  }
  const sprite = container.querySelector<HTMLElement>('.weapon-preview-card .stage-sprite');
  const offset = weapon.visual?.sourceOffset ?? [0, 0];
  sprite?.style.setProperty('--offset-x', `${offset[0] * 2.8}px`);
  sprite?.style.setProperty('--offset-y', `${offset[1] * 2.8}px`);
}

function updateCombinedPreviewDom(container: HTMLDivElement, weapon: WeaponDefinition, state: WeaponStudioState): void {
  const source = state.assets?.assets.find((entry) => entry.assetId === weapon.assetId && isWeaponAsset(entry));
  const info = assetInfo(source);
  const animation = weaponAnimations(weapon, info)[state.selectedAnimation];
  const position = Math.min(Math.max(state.previewStep, 0), Math.max(0, animation.frames.length - 1));
  const weaponFrame = animation.frames[position] ?? 0;
  const weaponSprite = container.querySelector<HTMLElement>('.stage-weapon-sprite');
  if (weaponSprite) {
    weaponSprite.style.setProperty('--frame-x', `${(weaponFrame % info.columns) * info.width}px`);
    weaponSprite.style.setProperty('--frame-y', `${Math.floor(weaponFrame / info.columns) * info.height}px`);
    const offset = weapon.visual?.animationOffsets?.[state.selectedAnimation] ?? weapon.visual?.sourceOffset ?? [0, 0];
    weaponSprite.style.setProperty('--offset-x', `${offset[0] * 2.8}px`);
    weaponSprite.style.setProperty('--offset-y', `${offset[1] * 2.8}px`);
  }
  const character = characterPackages.find((entry) => entry.characterId === state.selectedCharacterId) ?? selectedCharacter();
  const characterSource = state.assets?.assets.find((entry) => entry.assetId === character?.visualSet.assetId);
  const characterInfo = assetInfo(characterSource);
  const action = characterClip(character, weapon.characterActionId ?? weapon.animKey ?? 'trick');
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
  const track = weaponTrack(weapon, animation);
  container.querySelectorAll<HTMLElement>('[data-weapon-hitbox-id]').forEach((guide) => {
    const hitboxId = guide.dataset.weaponHitboxId ?? '';
    const active = track.hitboxSpans.some((span) => span.hitboxId === hitboxId && span.from <= position && position <= span.through);
    guide.classList.toggle('is-hot', active);
  });
  const caption = container.querySelector<HTMLElement>('.weapon-preview-card .stage-caption span');
  if (caption) caption.textContent = `CHARACTER ACTION ${action?.id ?? weapon.characterActionId ?? 'trick'} · WEAPON FRAME ${weaponFrame}`;
  const toolbar = container.querySelector<HTMLElement>('.weapon-preview-card .studio-preview-toolbar .studio-muted');
  if (toolbar) toolbar.textContent = `${state.selectedAnimation.toUpperCase()} · position ${position + 1}/${animation.frames.length} · ${character?.character.displayName ?? 'character'} + weapon`;
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
  if (!workbench.querySelector('.weapon-preview-card')) heading.insertAdjacentHTML('afterend', renderWeaponPreview(weapon, info, state.selectedAnimation, state.previewStep, character, assetInfo(characterSource)));
  if (!workbench.querySelector('.weapon-animation-panel')) workbench.querySelector('.weapon-preview-card')?.insertAdjacentHTML('afterend', renderWeaponAnimationPanel(weapon, source, state));
  const presentation = inspector.querySelector<HTMLElement>('[data-weapon-presentation]');
  if (presentation) {
    presentation.querySelector('.studio-section-heading strong')!.textContent = 'Animation';
    workbench.append(presentation);
  }
  if (!inspector.querySelector('.studio-inspector-heading')) inspector.insertAdjacentHTML('afterbegin', '<div class="studio-inspector-heading"><span class="studio-kicker">Inspector</span><h2>Weapon controls</h2><p>Identity, combat behavior, and visual alignment</p></div>');
  layout.append(inspector);
  applyWeaponPreview(container, weapon);
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

function renderStudio(state: WeaponStudioState, returnEditor: string): string {
  const weapon = state.draft;
  const scaling = weapon?.scaling ?? {};
  return `<main class="character-studio weapon-studio" data-weapon-studio>
    <header class="studio-topbar"><a class="studio-brand" href="?" aria-label="Back to game"><span class="brand-mark">✦</span><span><small>FIELD CARTOGRAPHER</small><strong>WEAPON STUDIO</strong></span></a><div class="studio-topbar-actions"><span class="studio-save-state${state.notice ? ' is-error' : ''}"><i></i>${escapeHtml(state.notice ?? (state.dirty ? 'Unsaved weapon' : 'Saved library'))}</span><button type="button" class="studio-button studio-button--save" data-action="save-weapon" ${!weapon || !state.dirty || state.saving ? 'disabled' : ''}>${state.saving ? 'SAVING…' : 'SAVE WEAPON'}</button></div></header>
    <div class="studio-layout"><aside class="studio-library"><div class="studio-panel-title"><div><span class="studio-kicker">Equipment library</span><h1>Weapons</h1></div><span class="studio-count">${String(state.weapons.length).padStart(2, '0')}</span></div><div class="studio-roster">${state.weapons.map((entry) => `<button type="button" class="studio-roster-item${entry.weaponId === state.selectedId ? ' is-active' : ''}" data-weapon-id="${escapeHtml(entry.weaponId)}"><span class="roster-glyph player">◆</span><span><strong>${escapeHtml(entry.displayName)}</strong><small>${entry.category.toUpperCase()} · ${escapeHtml(entry.weaponId)}</small></span><em>${entry.weaponId === state.selectedId ? 'OPEN' : ''}</em></button>`).join('')}</div><div class="studio-library-footer"><button type="button" class="studio-button studio-button--outline studio-button--create" data-action="new-weapon">NEW WEAPON</button><a class="studio-button studio-button--outline studio-button--navigation" href="?studio=characters&editor=${encodeURIComponent(returnEditor)}">↗ CHARACTER STUDIO</a></div></aside>
      <section class="studio-workbench">${weapon ? `<div class="studio-workbench-heading"><div><span class="studio-kicker">Reusable combat definition</span><h2>${escapeHtml(weapon.displayName)}</h2></div><div class="studio-workbench-meta"><span>WEAPON <b>${escapeHtml(weapon.weaponId)}</b></span><span>CATEGORY <b>${weapon.category.toUpperCase()}</b></span><span>BASE DAMAGE <b>${weapon.baseDamage}</b></span></div></div><section class="studio-inspector weapon-inspector"><div class="studio-inspector-scroll"><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Identity</span><strong>Equipment profile</strong></div><div class="studio-field-grid"><label class="studio-field"><span>Stable ID<small>lowercase</small></span><input type="text" value="${escapeHtml(weapon.weaponId)}" data-weapon-field="weaponId" /></label><label class="studio-field"><span>Display name<small>library label</small></span><input type="text" value="${escapeHtml(weapon.displayName)}" data-weapon-field="displayName" /></label></div><div class="studio-field-grid"><label class="studio-field"><span>Category<small>combat family</small></span><select data-weapon-field="category"><option value="melee" ${weapon.category === 'melee' ? 'selected' : ''}>Melee</option><option value="ranged" ${weapon.category === 'ranged' ? 'selected' : ''}>Ranged</option></select></label><label class="studio-field"><span>Character action<small>animation key</small></span><input type="text" value="${escapeHtml(weapon.animKey)}" data-weapon-field="animKey" /></label></div><label class="studio-field studio-field--wide"><span>Description<small>authoring note</small></span><input type="text" value="${escapeHtml(weapon.description)}" data-weapon-field="description" /></label></section><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Combat profile</span><strong>Base behavior</strong></div><div class="studio-field-grid">${field('Base damage', 'baseDamage', weapon.baseDamage, 'points')}${field('Cooldown', 'cooldownMs', weapon.cooldownMs, 'milliseconds')}${field('Hitbox width', 'hitboxWidth', weapon.hitboxWidth, 'world units')}${field('Hitbox height', 'hitboxHeight', weapon.hitboxHeight, 'world units')}${field('Hitbox offset', 'hitboxOffset', weapon.hitboxOffset, 'world units')}${field('Active duration', 'hitboxDurationMs', weapon.hitboxDurationMs, 'milliseconds')}${field('Knockback', 'knockStrength', weapon.knockStrength, 'world units/s')}${field('Unlock level', 'unlockLevel', weapon.unlockLevel, 'level', '1')}</div></section><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Attribute scaling</span><strong>Final value modifiers</strong></div><p class="studio-help">Coefficients resolve around attribute 10. Movement speed is intentionally not part of weapon scaling.</p><div class="studio-subheading">Damage</div><div class="studio-field-grid">${field('Strength', 'scaling.damage.strength', scaling.damage?.strength ?? 0, 'coefficient')}${field('Agility', 'scaling.damage.agility', scaling.damage?.agility ?? 0, 'coefficient')}${field('Intellect', 'scaling.damage.intellect', scaling.damage?.intellect ?? 0, 'coefficient')}</div><div class="studio-subheading">Cooldown</div><div class="studio-field-grid">${field('Agility', 'scaling.cooldown.agility', scaling.cooldown?.agility ?? 0, 'coefficient')}</div><div class="studio-subheading">Knockback</div><div class="studio-field-grid">${field('Strength', 'scaling.knockback.strength', scaling.knockback?.strength ?? 0, 'coefficient')}</div></section><section class="studio-inspector-section" data-weapon-presentation><div class="studio-section-heading"><span class="studio-kicker">Presentation</span><strong>Weapon layer foundation</strong></div><p class="studio-help">Weapon art will render as a separate layer attached to the character. This keeps one character compatible with many weapons.</p><div class="studio-callout"><strong>Character action: ${escapeHtml(weapon.animKey)}</strong><span>Next layer: import weapon art, define attachment offsets, and author the weapon timeline independently.</span></div></section></div></section>` : '<section class="studio-empty-state"><span class="studio-loading-orb">✦</span><h2>Select or create a weapon</h2><p>Weapons are reusable definitions. Characters and loadouts select them without duplicating character art.</p></section>'}</section></div>${renderWeaponAssetShelf(state)}
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
  let state: WeaponStudioState = { weapons: [], selectedId: '', selectedAnimation: 'attack', selectedPreviewFrame: 0, selectedCharacterId: selectedCharacter()?.characterId ?? '', previewStep: 0, previewPlaying: false, dirty: false, saving: false, assetShelfOpen: false, importing: false, importForm: { assetId: 'weapon.player.new', frameWidth: '16', frameHeight: '16', populatedCount: '' } };
  let previewTimer: number | undefined;
  const stopPreview = (): void => {
    if (previewTimer !== undefined) window.clearInterval(previewTimer);
    previewTimer = undefined;
    state = { ...state, previewPlaying: false };
  };
  const render = (): void => {
    container.innerHTML = renderStudio(state, returnEditor);
    ensureStudioModeTabs(container, returnEditor, 'weapons');
    if (state.draft) {
      const presentation = container.querySelector<HTMLElement>('[data-weapon-presentation]');
      if (presentation) {
        presentation.insertAdjacentHTML('beforebegin', renderWeaponHitboxEditor(state.draft));
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
      if (identity && !identity.querySelector('[data-weapon-character-id]')) {
        const options = characterPackages.map((entry) => `<option value="${escapeHtml(entry.characterId)}" ${entry.characterId === state.selectedCharacterId ? 'selected' : ''}>${escapeHtml(entry.character.displayName)} · ${escapeHtml(entry.characterId)}</option>`).join('');
        identity.insertAdjacentHTML('beforeend', `<label class="studio-field studio-field--wide"><span>Preview character<small>existing anchor + action</small></span><select data-weapon-character-id>${options}</select></label>`);
      }
      reflowWeaponStudio(container, state.draft, state);
    }
  };
  const select = (weapon: WeaponDefinition, revision?: string): void => { stopPreview(); state = { ...state, selectedId: weapon.weaponId, selectedAnimation: 'attack', selectedPreviewFrame: 0, previewStep: 0, previewPlaying: false, draft: clone(weapon), revision, dirty: false, assetShelfOpen: false, notice: undefined }; render(); };
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
    const draft = clone(state.draft) as MutableWeaponDraft;
    const numericPaths = new Set(['baseDamage', 'cooldownMs', 'hitboxWidth', 'hitboxHeight', 'hitboxOffset', 'hitboxDurationMs', 'knockStrength', 'unlockLevel', 'scaling.damage.strength', 'scaling.damage.agility', 'scaling.damage.intellect', 'scaling.cooldown.agility', 'scaling.knockback.strength', 'visual.sourceOffset.0', 'visual.sourceOffset.1']);
    const value = numericPaths.has(path) ? integerValue(rawValue) : rawValue;
    const animationMatch = path.match(/^animations\.(idle|attack|impact)\.(frames|framesPerSecond|loop|loopMode)$/);
    if (animationMatch) {
      const animationId = animationMatch[1] as WeaponAnimationId;
      const fieldName = animationMatch[2] as 'frames' | 'framesPerSecond' | 'loop' | 'loopMode';
      const animations = weaponAnimations(draft, assetInfo(state.assets?.assets.find((entry) => entry.assetId === draft.assetId && isWeaponAsset(entry))));
      const next = { ...animations[animationId] } as { frames: number[]; framesPerSecond: number; loop: boolean; loopMode?: 'wrap' | 'ping-pong' };
      if (fieldName === 'frames') next.frames = String(rawValue).split(',').map((entry) => Number(entry.trim())).filter((entry) => Number.isInteger(entry) && entry >= 0);
      else if (fieldName === 'framesPerSecond') next.framesPerSecond = Math.min(240, Math.max(1, integerValue(rawValue, 12)));
      else if (fieldName === 'loop') next.loop = Boolean(rawValue);
      else next.loopMode = rawValue === 'ping-pong' ? 'ping-pong' : 'wrap';
      draft.animations = { ...animations, [animationId]: next };
    } else if (path.startsWith('scaling.')) {
      const [, group, attribute] = path.split('.') as ['', keyof MutableWeaponScaling, keyof MutableWeaponScalingGroup];
      draft.scaling ??= {};
      draft.scaling[group] ??= {};
      draft.scaling[group]![attribute] = Number(value);
    } else if (path === 'weaponId') draft.weaponId = String(value).trim().toLowerCase();
    else if (path === 'displayName') draft.displayName = String(value);
    else if (path === 'category') draft.category = value === 'ranged' ? 'ranged' : 'melee';
    else if (path === 'animKey') draft.animKey = String(value);
    else if (path === 'characterActionId') draft.characterActionId = String(value).trim().toLowerCase();
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
    else if (path.match(/^hitboxes\.[^.]+\.(shape|width|height|offsetX|offsetY|radius|radiusX|radiusY|innerRadius|outerRadius|arcWidthRad|damageMultiplier|knockbackMultiplier)$/)) {
      const [, hitboxId, property] = path.split('.');
      draft.hitboxes ??= clone(weaponHitboxes(draft)) as Record<string, MutableWeaponHitbox>;
      const hitbox = draft.hitboxes[hitboxId];
      if (hitbox) {
        if (property === 'shape') hitbox.shape = value as WeaponHitboxShape;
        else hitbox[property as keyof MutableWeaponHitbox] = Number(value) as never;
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
    if (!state.draft) return;
    const draft = clone(state.draft) as MutableWeaponDraft;
    const source = state.assets?.assets.find((entry) => entry.assetId === draft.assetId && isWeaponAsset(entry));
    const attack = weaponAnimations(draft, assetInfo(source)).attack;
    const current = weaponTrack(draft, attack);
    const track: MutableWeaponTrack = { hitboxSpans: current.hitboxSpans.map((span) => ({ ...span })), events: (current.events ?? []).map((event) => ({ ...event })) };
    mutate(track, attack);
    draft.attackTrack = track;
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
    if (!state.draft) return;
    const draft = clone(state.draft) as MutableWeaponDraft;
    draft.hitboxes ??= clone(weaponHitboxes(draft)) as Record<string, MutableWeaponHitbox>;
    let index = Object.keys(draft.hitboxes).length + 1;
    let hitboxId = `hitbox-${index}`;
    while (draft.hitboxes[hitboxId]) { index += 1; hitboxId = `hitbox-${index}`; }
    draft.hitboxes[hitboxId] = { shape: 'circle', width: 24, height: 24, radius: 12, offsetX: 30, offsetY: 0, damageMultiplier: 1, knockbackMultiplier: 1 };
    state = { ...state, draft, dirty: true, notice: undefined };
    render();
  };
  const removeWeaponHitbox = (hitboxId: string): void => {
    if (!state.draft) return;
    const draft = clone(state.draft) as MutableWeaponDraft;
    draft.hitboxes ??= clone(weaponHitboxes(draft)) as Record<string, MutableWeaponHitbox>;
    if (Object.keys(draft.hitboxes).length <= 1) return;
    delete draft.hitboxes[hitboxId];
    if (draft.attackTrack) draft.attackTrack.hitboxSpans = draft.attackTrack.hitboxSpans.filter((span) => span.hitboxId !== hitboxId);
    state = { ...state, draft, dirty: true, notice: undefined };
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
    const target = event.target as HTMLElement;
    const shelfBackdrop = target.closest<HTMLElement>('[data-weapon-shelf-backdrop]');
    if (shelfBackdrop && target === shelfBackdrop) { state = { ...state, assetShelfOpen: false, notice: undefined }; render(); return; }
    const weaponButton = target.closest<HTMLElement>('[data-weapon-id]');
    if (weaponButton) { const weapon = state.weapons.find((entry) => entry.weaponId === weaponButton.dataset.weaponId); if (weapon) select(weapon, weapon.revision); return; }
    const animationId = target.closest<HTMLElement>('[data-weapon-animation-id]')?.dataset.weaponAnimationId;
    if (animationId === 'idle' || animationId === 'attack' || animationId === 'impact') { stopPreview(); state = { ...state, selectedAnimation: animationId, selectedPreviewFrame: 0, previewStep: 0 }; render(); return; }
    const spanToggle = target.closest<HTMLElement>('[data-weapon-span-toggle]');
    if (spanToggle) {
      toggleWeaponSpan(spanToggle.dataset.weaponSpanToggle ?? '', Number(spanToggle.dataset.weaponSpanFrame));
      return;
    }
    const frameButton = target.closest<HTMLElement>('[data-weapon-frame]');
    if (frameButton && state.draft) {
      const frame = Number(frameButton.dataset.weaponFrame);
      const animation = weaponAnimations(state.draft, assetInfo(state.assets?.assets.find((entry) => entry.assetId === state.draft?.assetId && isWeaponAsset(entry))))[state.selectedAnimation];
      const frames = animation.frames.includes(frame) ? animation.frames.filter((candidate) => candidate !== frame) : [...animation.frames, frame];
      updateDraft(`animations.${state.selectedAnimation}.frames`, frames.join(', '));
      state = { ...state, selectedPreviewFrame: frame, previewStep: Math.max(0, frames.indexOf(frame)) };
      render();
      return;
    }
    const action = target.closest<HTMLElement>('[data-action]')?.dataset.action;
    if (action === 'new-weapon') { select(makeNewWeapon()); return; }
    if (action === 'add-weapon-hitbox') { addWeaponHitbox(); return; }
    const removeHitboxId = target.closest<HTMLElement>('[data-remove-weapon-hitbox]')?.dataset.removeWeaponHitbox;
    if (removeHitboxId) { removeWeaponHitbox(removeHitboxId); return; }
    if (action === 'play-weapon-preview') {
      if (previewTimer !== undefined) { stopPreview(); render(); return; }
      if (!state.draft) return;
      const previewDraft = state.draft;
      const source = state.assets?.assets.find((entry) => entry.assetId === previewDraft.assetId && isWeaponAsset(entry));
      const animation = weaponAnimations(previewDraft, assetInfo(source))[state.selectedAnimation];
      state = { ...state, previewPlaying: true, previewStep: 0 };
      previewTimer = window.setInterval(() => {
        if (!state.draft) { stopPreview(); return; }
        const currentSource = state.assets?.assets.find((entry) => entry.assetId === state.draft?.assetId && isWeaponAsset(entry));
        const currentAnimation = weaponAnimations(state.draft, assetInfo(currentSource))[state.selectedAnimation];
        const next = state.previewStep + 1;
        if (next >= currentAnimation.frames.length) {
          if (currentAnimation.loop) state = { ...state, previewStep: 0 };
          else { stopPreview(); state = { ...state, previewStep: Math.max(0, currentAnimation.frames.length - 1) }; }
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
    const eventFrame = target.dataset.weaponEventFrame;
    if (eventFrame !== undefined) { updateWeaponEvent(Number(eventFrame), target.value); return; }
    const path = target.dataset.weaponField;
    if (!path) return;
    updateDraft(path, target instanceof HTMLInputElement && target.type === 'checkbox' ? target.checked : target.value);
    if (state.draft) {
      applyWeaponPreview(container, state.draft);
      updateCombinedPreviewDom(container, state.draft, state);
    }
    if (event.type === 'change' && (path.startsWith('hitboxes.') || path.startsWith('visual.') || path.startsWith('animations.'))) { render(); return; }
    if (target instanceof HTMLSelectElement || (target instanceof HTMLInputElement && target.type === 'checkbox')) render();
  };
  container.addEventListener('click', onClick); container.addEventListener('input', onInput); container.addEventListener('change', onInput); render(); void load();
  return () => { container.removeEventListener('click', onClick); container.removeEventListener('input', onInput); container.removeEventListener('change', onInput); container.classList.remove('is-character-studio-host'); };
}
