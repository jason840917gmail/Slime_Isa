import './character-studio.css';

import type { CharacterStudioAssetCatalog, CharacterStudioAssetEntry } from '../content/characters/characterAssetCatalog';
import type { WeaponAnimationDocument, WeaponAnimationSet, WeaponDefinition } from '../content/weapons/types';
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

type Mutable<T> = { -readonly [Key in keyof T]: T[Key] };
type MutableWeaponDraft = Omit<Mutable<WeaponDefinition>, 'scaling'> & { scaling?: MutableWeaponScaling };

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
  return `<label class="studio-field"><span>${label}<small>${unit}</small></span><input type="number" step="${step}" inputmode="numeric" value="${escapeHtml(integerValue(value))}" data-weapon-field="${path}" /></label>`;
}

function makeNewWeapon(): WeaponDefinition {
  return {
    version: 1,
    weaponId: 'new-weapon',
    displayName: 'New Weapon',
    category: 'melee',
    animKey: 'attack-1',
    animations: defaultWeaponAnimations(assetInfo(undefined)),
    visual: { sourceOffset: [0, 0] },
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
  return `<section class="studio-inspector-section" data-weapon-visual><div class="studio-section-heading"><span class="studio-kicker">Visual</span><strong>Attachment alignment</strong></div><p class="studio-help">The weapon effect shifts around the character anchor without changing its gameplay hitbox.</p><div class="studio-field-grid">${field('Offset X', 'visual.sourceOffset.0', offset[0], 'source pixels')}${field('Offset Y', 'visual.sourceOffset.1', offset[1], 'source pixels')}</div></section>`;
}

function renderWeaponPreview(weapon: WeaponDefinition, info: ReturnType<typeof assetInfo>, animationId: WeaponAnimationId, frame: number): string {
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
  return `<section class="studio-timeline-panel weapon-animation-panel"><div class="studio-section-bar"><div><span class="studio-kicker">Animation timeline</span><strong>Editing ${state.selectedAnimation}</strong></div><span class="studio-muted">Select frames from the weapon sheet</span></div><div class="studio-clip-tabs">${(['idle', 'attack', 'impact'] as const).map((id) => `<button type="button" class="studio-clip-tab${id === state.selectedAnimation ? ' is-active' : ''}" data-weapon-animation-id="${id}"><span>${id.toUpperCase()}</span><small>${animations[id].frames.length}F</small></button>`).join('')}</div><div class="studio-sheet-grid projectile-frame-grid">${Array.from({ length: info.count }, (_, frame) => renderWeaponFrameTile(source, frame, animation.frames.includes(frame))).join('')}</div><label class="studio-field studio-field--wide"><span>${state.selectedAnimation.toUpperCase()} frames<small>comma-separated source IDs</small></span><input type="text" value="${escapeHtml(animation.frames.join(', '))}" data-weapon-field="animations.${state.selectedAnimation}.frames" /></label><div class="studio-field-grid"><label class="studio-field"><span>FPS<small>frames / second</small></span><input type="number" min="1" max="240" step="1" inputmode="numeric" value="${integerValue(animation.framesPerSecond, 12)}" data-weapon-field="animations.${state.selectedAnimation}.framesPerSecond" /></label><label class="studio-field"><span>Loop mode<small>playback</small></span><select data-weapon-field="animations.${state.selectedAnimation}.loopMode"><option value="wrap" ${animation.loopMode !== 'ping-pong' ? 'selected' : ''}>Wrap</option><option value="ping-pong" ${animation.loopMode === 'ping-pong' ? 'selected' : ''}>Ping-pong</option></select></label></div><label class="studio-toggle-field"><input type="checkbox" data-weapon-field="animations.${state.selectedAnimation}.loop" ${animation.loop ? 'checked' : ''} /><span><strong>Loop ${state.selectedAnimation}</strong><small>Keep this weapon visual track playing</small></span></label></section>`;
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

function reflowWeaponStudio(container: HTMLDivElement, weapon: WeaponDefinition, state: WeaponStudioState): void {
  const layout = container.querySelector<HTMLElement>('.studio-layout');
  const workbench = container.querySelector<HTMLElement>('.weapon-studio .studio-workbench');
  const inspector = container.querySelector<HTMLElement>('.weapon-inspector');
  const heading = workbench?.querySelector<HTMLElement>('.studio-workbench-heading');
  if (!layout || !workbench || !inspector || !heading) return;
  const source = state.assets?.assets.find((entry) => entry.assetId === weapon.assetId && isWeaponAsset(entry));
  const info = assetInfo(source);
  const animation = weaponAnimations(weapon, info)[state.selectedAnimation];
  const previewFrame = animation.frames.includes(state.selectedPreviewFrame) ? state.selectedPreviewFrame : animation.frames[0] ?? 0;
  if (!workbench.querySelector('.weapon-preview-card')) heading.insertAdjacentHTML('afterend', renderWeaponPreview(weapon, info, state.selectedAnimation, previewFrame));
  if (!workbench.querySelector('.weapon-animation-panel')) workbench.querySelector('.weapon-preview-card')?.insertAdjacentHTML('afterend', renderWeaponAnimationPanel(weapon, source, state));
  const presentation = inspector.querySelector<HTMLElement>('[data-weapon-presentation]');
  if (presentation) {
    presentation.querySelector('.studio-section-heading strong')!.textContent = 'Animation';
    workbench.append(presentation);
  }
  if (!inspector.querySelector('.studio-inspector-heading')) inspector.insertAdjacentHTML('afterbegin', '<div class="studio-inspector-heading"><span class="studio-kicker">Inspector</span><h2>Weapon controls</h2><p>Identity, combat behavior, and visual alignment</p></div>');
  layout.append(inspector);
  applyWeaponPreview(container, weapon);
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
  let state: WeaponStudioState = { weapons: [], selectedId: '', selectedAnimation: 'attack', selectedPreviewFrame: 0, dirty: false, saving: false, assetShelfOpen: false, importing: false, importForm: { assetId: 'weapon.player.new', frameWidth: '16', frameHeight: '16', populatedCount: '' } };
  const render = (): void => {
    container.innerHTML = renderStudio(state, returnEditor);
    ensureStudioModeTabs(container, returnEditor, 'weapons');
    if (state.draft) {
      const presentation = container.querySelector<HTMLElement>('[data-weapon-presentation]');
      if (presentation) presentation.insertAdjacentHTML('beforebegin', renderWeaponVisualFields(state.draft));
      const identity = container.querySelector<HTMLElement>('.weapon-inspector .studio-inspector-section');
      const description = identity?.querySelector<HTMLElement>('.studio-field--wide');
      if (description) description.insertAdjacentHTML('beforebegin', renderWeaponAssetField(state));
      reflowWeaponStudio(container, state.draft, state);
    }
  };
  const select = (weapon: WeaponDefinition, revision?: string): void => { state = { ...state, selectedId: weapon.weaponId, selectedAnimation: 'attack', selectedPreviewFrame: 0, draft: clone(weapon), revision, dirty: false, assetShelfOpen: false, notice: undefined }; render(); };
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
    else if (path === 'visual.sourceOffset.0' || path === 'visual.sourceOffset.1') {
      const offset = [...(draft.visual?.sourceOffset ?? [0, 0])] as [number, number];
      offset[path.endsWith('.0') ? 0 : 1] = integerValue(value);
      draft.visual = { sourceOffset: offset };
    }
    state = { ...state, draft, selectedId: draft.weaponId, dirty: true, notice: undefined };
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
    if (animationId === 'idle' || animationId === 'attack' || animationId === 'impact') { state = { ...state, selectedAnimation: animationId, selectedPreviewFrame: 0 }; render(); return; }
    const frameButton = target.closest<HTMLElement>('[data-weapon-frame]');
    if (frameButton && state.draft) {
      const frame = Number(frameButton.dataset.weaponFrame);
      const animation = weaponAnimations(state.draft, assetInfo(state.assets?.assets.find((entry) => entry.assetId === state.draft?.assetId && isWeaponAsset(entry))))[state.selectedAnimation];
      const frames = animation.frames.includes(frame) ? animation.frames.filter((candidate) => candidate !== frame) : [...animation.frames, frame];
      updateDraft(`animations.${state.selectedAnimation}.frames`, frames.join(', '));
      state = { ...state, selectedPreviewFrame: frame };
      render();
      return;
    }
    const action = target.closest<HTMLElement>('[data-action]')?.dataset.action;
    if (action === 'new-weapon') { select(makeNewWeapon()); return; }
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
    const path = target.dataset.weaponField;
    if (!path) return;
    updateDraft(path, target instanceof HTMLInputElement && target.type === 'checkbox' ? target.checked : target.value);
    if (state.draft) applyWeaponPreview(container, state.draft);
    if (target instanceof HTMLSelectElement || (target instanceof HTMLInputElement && target.type === 'checkbox')) render();
  };
  container.addEventListener('click', onClick); container.addEventListener('input', onInput); container.addEventListener('change', onInput); render(); void load();
  return () => { container.removeEventListener('click', onClick); container.removeEventListener('input', onInput); container.removeEventListener('change', onInput); container.classList.remove('is-character-studio-host'); };
}
