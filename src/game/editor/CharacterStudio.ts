import { characterPackages } from 'virtual-character-content';

import './character-studio.css';
import { ensureStudioModeTabs } from './StudioModeTabs';
import { createAnimationTimelineView } from './AnimationTimelineView';

import { ASSET_MANIFEST, getAsset } from '../infrastructure/assets/manifest';
import { resolveAssetUrl } from '../infrastructure/assets/assetUrls';
import type { CharacterStudioAssetCatalog, CharacterStudioAssetEntry } from '../content/characters/characterAssetCatalog';
import { CharacterDocumentState, type CharacterDocumentSnapshot } from './CharacterDocumentState';
import { animationCycleFrameCount, animationFrameIndexAtStep } from '../shared/animationLoop';
import { keyframeIndexAtTimelineFrame, normalizeAnimationClip, timelineFrameCount } from '../shared/animation';
import { resolveCollisionShapeDimensions, type CollisionShape } from '../shared/collisionShapes';
import type { CharacterPackage, JsonValue, VisualClipDocument, VisualLoopMode } from '../content/characters/types';

interface PackageResponse {
  readonly character: CharacterPackage['character'];
  readonly visualSet: CharacterPackage['visualSet'];
  readonly revision: string;
}

interface AssetShelfState {
  readonly open: boolean;
  readonly loading: boolean;
  readonly catalog?: CharacterStudioAssetCatalog;
  readonly selectedAssetId?: string;
  readonly error?: string;
  readonly submitting?: boolean;
  readonly notice?: string;
}

interface CreationFormState {
  readonly kind: 'player' | 'enemy';
  readonly template: 'player' | 'melee-enemy' | 'ranged-enemy';
  readonly characterId: string;
  readonly displayName: string;
  readonly assetId: string;
}

interface StudioModalField {
  readonly id: string;
  readonly label: string;
  readonly value?: string;
  readonly placeholder?: string;
  readonly inputType?: 'text' | 'number';
  readonly optional?: boolean;
}

interface StudioModalRequest {
  readonly kind: 'prompt' | 'confirm' | 'alert';
  readonly title: string;
  readonly message: string;
  readonly fields?: readonly StudioModalField[];
  readonly confirmLabel?: string;
  readonly cancelLabel?: string;
  readonly danger?: boolean;
}

type StudioModalResult = Record<string, string> | boolean | undefined;

interface ActiveStudioModal {
  readonly request: StudioModalRequest;
  readonly resolve: (result: StudioModalResult) => void;
}

function escapeHtml(value: unknown): string {
  return String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}

function numberValue(value: unknown, fallback = 0): number {
  return typeof value === 'number' ? value : fallback;
}

function integerValue(value: unknown, fallback = 0): number {
  const numeric = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(numeric) ? Math.round(numeric) : fallback;
}

function integerInputValue(value: unknown, fallback = 0): string {
  return String(integerValue(value, fallback));
}

function assetFrameInfo(assetId: string): { width: number; height: number; columns: number; rows: number; count: number; url: string } {
  const asset = getAsset(assetId as never);
  if (!('path' in asset.source)) return { width: 1, height: 1, columns: 1, rows: 1, count: 1, url: '' };
  if (!('frame' in asset.source)) {
    const width = 'expect' in asset.source ? asset.source.expect.w : 1;
    const height = 'expect' in asset.source ? asset.source.expect.h : 1;
    return { width, height, columns: 1, rows: 1, count: 1, url: resolveAssetUrl(asset.source.path) };
  }
  const count = 'count' in asset.source.frame && asset.source.frame.count ? asset.source.frame.count : asset.source.frame.cols * asset.source.frame.rows;
  return { width: asset.source.frame.w, height: asset.source.frame.h, columns: asset.source.frame.cols, rows: asset.source.frame.rows, count, url: resolveAssetUrl(asset.source.path) };
}

function resolvePreviewTransform(visualSet: CharacterPackage['visualSet'], frame: number, clipId?: string): { origin: readonly [number, number]; scale: readonly [number, number]; sourceOffset: readonly [number, number] } {
  const override = visualSet.frameVisuals?.[String(frame)];
  const clip = clipId ? visualSet.clips[clipId] : undefined;
  return {
    origin: override?.origin ?? visualSet.defaults.origin,
    scale: override?.scale ?? visualSet.defaults.scale,
    sourceOffset: override?.sourceOffset ?? clip?.sourceOffset ?? visualSet.defaults.sourceOffset,
  };
}

function manifestTags(value: unknown): readonly string[] {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return [];
  const tags = (value as { readonly tags?: unknown }).tags;
  return Array.isArray(tags) ? tags.filter((tag): tag is string => typeof tag === 'string') : [];
}

function projectileAssetOptions(selectedAssetId: string): string {
  const ids = Object.entries(ASSET_MANIFEST.assets)
    .filter(([assetId, entry]) => assetId === selectedAssetId || manifestTags(entry).includes('projectile'))
    .map(([assetId]) => assetId);
  return `<option value="">Select projectile source</option>${ids.map((assetId) => `<option value="${escapeHtml(assetId)}" ${assetId === selectedAssetId ? 'selected' : ''}>${escapeHtml(assetId)}</option>`).join('')}`;
}

function assetShelfPreview(entry: CharacterStudioAssetEntry): string {
  try {
    return resolveAssetUrl(entry.sourcePath);
  } catch {
    return '';
  }
}

function renderAssetCard(entry: CharacterStudioAssetEntry, selected: boolean): string {
  const previewUrl = assetShelfPreview(entry);
  const frame = entry.frame;
  const previewStyle = frame
    ? `--sheet-url:url('${previewUrl}');--frame-w:${frame.width}px;--frame-h:${frame.height}px;--sheet-w:${frame.width * frame.columns}px;--sheet-h:${frame.height * frame.rows}px;--frame-x:0px;--frame-y:0px`
    : `--sheet-url:url('${previewUrl}')`;
  const usedBy = entry.characterIds.length > 0 ? `USED BY ${entry.characterIds.length}` : 'UNUSED SOURCE';
  return `<button type="button" class="studio-asset-card${selected ? ' is-selected' : ''}" data-action="select-asset" data-asset-id="${escapeHtml(entry.assetId)}" aria-pressed="${selected}">
    <span class="studio-asset-card-preview${frame ? ' is-sheet' : ''}" style="${previewStyle}"></span>
    <span class="studio-asset-card-copy"><strong>${escapeHtml(entry.assetId)}</strong><small>${entry.kind.toUpperCase()} · ${escapeHtml(usedBy)}</small><em>${frame ? `${frame.columns} × ${frame.rows} · ${frame.count} FRAMES` : `${entry.dimensions.width} × ${entry.dimensions.height} PX`}</em></span>
  </button>`;
}

function renderAssetShelf(state: AssetShelfState, currentAssetId: string, form: CreationFormState): string {
  if (!state.open) return '';
  const selectedAssetId = state.selectedAssetId ?? currentAssetId;
  const selected = state.catalog?.assets.find((entry) => entry.assetId === selectedAssetId);
  const content = state.loading
    ? '<div class="studio-asset-shelf-state"><span class="studio-loading-orb">✦</span><p>Reading the registered source library…</p></div>'
    : state.error
      ? `<div class="studio-asset-shelf-state is-error"><strong>Source library unavailable</strong><p>${escapeHtml(state.error)}</p></div>`
      : `<div class="studio-asset-shelf-grid">${state.catalog?.assets.map((entry) => renderAssetCard(entry, entry.assetId === selectedAssetId)).join('') ?? '<p class="studio-empty-note">No ready image or spritesheet assets are registered yet.</p>'}</div>`;
  return `<div class="studio-asset-shelf-backdrop" data-action="close-asset-shelf"><section class="studio-asset-shelf" role="dialog" aria-modal="true" aria-labelledby="studio-asset-shelf-title" data-asset-shelf-panel>
    <header class="studio-asset-shelf-heading"><div><span class="studio-kicker">Creation foundation</span><h2 id="studio-asset-shelf-title">Source library</h2><p>Choose a registered visual source for the next character package.</p></div><button type="button" class="studio-icon-button" data-action="close-asset-shelf" aria-label="Close source library">×</button></header>
    ${content}
    <section class="studio-asset-create-panel"><div class="studio-asset-create-heading"><span><span class="studio-kicker">Package seed</span><strong>${selected ? `Build from ${escapeHtml(selected.assetId)}` : 'Choose a source above'}</strong></span><span class="studio-asset-create-status">${state.notice ? escapeHtml(state.notice) : 'New content remains development-only until you place it in a map.'}</span></div><div class="studio-asset-create-fields"><label class="studio-create-field"><span>Stable ID</span><input type="text" value="${escapeHtml(form.characterId)}" data-creation-field="characterId" placeholder="ice-worm" /></label><label class="studio-create-field"><span>Display name</span><input type="text" value="${escapeHtml(form.displayName)}" data-creation-field="displayName" placeholder="Ice Worm" /></label><label class="studio-create-field"><span>Kind</span><select data-creation-field="kind"><option value="enemy" ${form.kind === 'enemy' ? 'selected' : ''}>Enemy</option><option value="player" ${form.kind === 'player' ? 'selected' : ''}>Player</option></select></label><label class="studio-create-field"><span>Starter behavior</span><select data-creation-field="template" ${form.kind === 'player' ? 'disabled' : ''}><option value="player" ${form.template === 'player' ? 'selected' : ''}>Player baseline</option><option value="melee-enemy" ${form.template === 'melee-enemy' ? 'selected' : ''}>Melee enemy</option><option value="ranged-enemy" ${form.template === 'ranged-enemy' ? 'selected' : ''}>Ranged enemy</option></select></label></div><div class="studio-asset-create-actions"><button type="button" class="studio-button studio-button--save" data-action="create-package" ${!selected || state.submitting ? 'disabled' : ''}>${state.submitting ? 'CREATING…' : 'CREATE PACKAGE'}</button><span class="studio-asset-create-divider">OR</span><input type="file" accept="image/png" data-upload-input hidden /><button type="button" class="studio-button studio-button--quiet" data-action="upload-create" ${state.submitting ? 'disabled' : ''}>IMPORT PNG + CREATE</button></div></section>
    <footer class="studio-asset-shelf-footer"><span>${selected ? `SELECTED <b>${escapeHtml(selected.assetId)}</b>` : 'Select a source to continue'}</span><small>PNG imports use a 32 MB development upload limit.</small></footer>
  </section></div>`;
}

function syncAssetCreationControls(container: HTMLDivElement, state: AssetShelfState, currentAssetId: string, form: CreationFormState): void {
  const hasIdentity = form.characterId.trim().length > 0 && form.displayName.trim().length > 0;
  const selectedAssetId = state.selectedAssetId ?? currentAssetId;
  const hasSelectedAsset = state.catalog?.assets.some((entry) => entry.assetId === selectedAssetId) ?? false;
  const createButton = container.querySelector<HTMLButtonElement>('[data-action="create-package"]');
  const importButton = container.querySelector<HTMLButtonElement>('[data-action="upload-create"]');
  if (createButton) {
    createButton.disabled = state.submitting === true || !hasIdentity || !hasSelectedAsset;
    createButton.title = hasIdentity ? (hasSelectedAsset ? 'Create the character package' : 'Choose a source sheet first') : 'Enter stable ID and display name first';
  }
  if (importButton) {
    importButton.disabled = state.submitting === true || !hasIdentity;
    importButton.title = hasIdentity ? 'Import a PNG and create the character package' : 'Enter stable ID and display name first';
  }
}

function renderStudioModal(activeModal: ActiveStudioModal | undefined): string {
  if (!activeModal) return '';
  const { request } = activeModal;
  const titleId = 'studio-modal-title';
  const messageId = 'studio-modal-message';
  const fields = request.fields ?? [];
  const primaryLabel = request.confirmLabel ?? (request.kind === 'confirm' ? 'CONFIRM' : request.kind === 'alert' ? 'OK' : 'APPLY');
  return `<div class="studio-modal-backdrop" data-studio-modal-backdrop>
    <section class="studio-modal${request.danger ? ' is-danger' : ''}" role="dialog" aria-modal="true" aria-labelledby="${titleId}" aria-describedby="${messageId}" data-studio-modal>
      <header class="studio-modal-header"><span class="studio-kicker">Character Studio</span><h2 id="${titleId}">${escapeHtml(request.title)}</h2></header>
      <p class="studio-modal-message" id="${messageId}">${escapeHtml(request.message)}</p>
      <form class="studio-modal-form" data-studio-modal-form>
        ${fields.map((field, index) => { const isNumber = field.inputType === 'number'; const rawValue = field.value ?? ''; const value = isNumber && rawValue.trim() ? integerInputValue(rawValue) : rawValue; return `<label class="studio-modal-field"><span>${escapeHtml(field.label)}${field.optional ? '<small>optional</small>' : ''}</span><input type="${field.inputType ?? 'text'}" name="${escapeHtml(field.id)}" data-modal-field="${escapeHtml(field.id)}" value="${escapeHtml(value)}" placeholder="${escapeHtml(field.placeholder ?? '')}" ${isNumber ? 'step="1" inputmode="numeric"' : ''} ${field.optional ? '' : 'required'} ${index === 0 ? 'data-modal-autofocus' : ''} autocomplete="off" /></label>`; }).join('')}
        <footer class="studio-modal-actions">${request.kind !== 'alert' ? `<button type="button" class="studio-button studio-button--quiet" data-modal-action="cancel">${escapeHtml(request.cancelLabel ?? 'CANCEL')}</button>` : ''}<button type="submit" class="studio-button ${request.danger ? 'studio-button--danger' : 'studio-button--save'}">${escapeHtml(primaryLabel)}</button></footer>
      </form>
    </section>
  </div>`;
}

function statusClass(snapshot: CharacterDocumentSnapshot): string {
  if (snapshot.errors.length > 0) return 'is-invalid';
  if (snapshot.dirty) return 'is-dirty';
  return snapshot.saveState === 'saved' ? 'is-saved' : '';
}

function renderFrameTile(frame: number, info: ReturnType<typeof assetFrameInfo>, selected: boolean, compact = false, interactive = true, inClip = false): string {
  const column = frame % info.columns;
  const row = Math.floor(frame / info.columns);
  const maxWidth = compact ? 52 : 64;
  const maxHeight = compact ? 36 : 47;
  const thumbScale = Math.min(1, maxWidth / Math.max(info.width, 1), maxHeight / Math.max(info.height, 1));
  const frameWidth = info.width * thumbScale;
  const frameHeight = info.height * thumbScale;
  const image = info.url
    ? `<img src="${escapeHtml(info.url)}" alt="" aria-hidden="true" draggable="false" />`
    : '<span class="studio-frame-image-fallback" aria-hidden="true">?</span>';
  const tag = interactive ? 'button' : 'div';
  const attributes = interactive ? ` type="button" data-source-frame="${frame}" aria-label="Source frame ${frame}"` : '';
  return `<${tag} class="studio-frame-tile${selected ? ' is-selected' : ''}${inClip ? ' is-in-clip' : ''}${compact ? ' is-compact' : ''}"${attributes}>
    <span class="studio-frame-image" style="--thumb-w:${frameWidth}px;--thumb-h:${frameHeight}px;--sheet-thumb-w:${info.width * info.columns * thumbScale}px;--sheet-thumb-h:${info.height * info.rows * thumbScale}px;--sheet-offset-x:${-column * info.width * thumbScale}px;--sheet-offset-y:${-row * info.height * thumbScale}px">${image}</span>
    <small>${frame}</small>
  </${tag}>`;
}

function renderCharacterSourceTilePicker(snapshot: CharacterDocumentSnapshot): string {
  const info = assetFrameInfo(String(snapshot.visualSet.assetId));
  const selected = new Set(snapshot.selectedSourceFrames);
  const focused = selected.size > 0 ? `${selected.size} selected` : `focused source ${snapshot.selectedSourceFrame}`;
  return `<div class="studio-asset-shelf-backdrop character-tile-picker-backdrop" data-character-tile-picker-backdrop><section class="studio-asset-shelf character-tile-picker" role="dialog" aria-modal="true" aria-labelledby="character-tile-picker-title"><header class="studio-asset-shelf-heading"><div><span class="studio-kicker">Animation keyframe picker</span><h2 id="character-tile-picker-title">Add source tiles</h2><p>Select source tiles for this animation. They become keyframes and can hold for multiple timeline frames.</p></div><button type="button" class="studio-icon-button" data-action="close-character-tile-picker" aria-label="Close animation keyframe picker">×</button></header><div class="studio-sheet-grid character-picker-grid">${Array.from({ length: info.count }, (_, frame) => renderFrameTile(frame, info, selected.has(frame), false, true, snapshot.visualSet.clips[snapshot.selectedClipId]?.frames.includes(frame) ?? false)).join('')}</div><footer class="character-tile-picker-footer"><span>${escapeHtml(focused)} · ${info.count} available</span><div><button type="button" class="studio-button studio-button--quiet" data-action="insert-frame">INSERT AT PLAYHEAD</button><button type="button" class="studio-button studio-button--accent" data-action="append-frame">ADD TO ANIMATION</button></div></footer></section></div>`;
}

function renderInspector(snapshot: CharacterDocumentSnapshot): string {
  const { character, visualSet } = snapshot;
  const frame = snapshot.selectedSourceFrame;
  const transform = visualSet.frameVisuals?.[String(frame)] ?? {};
  const animation = visualSet.clips[snapshot.selectedClipId];
  const animationOffset = animation?.sourceOffset ?? visualSet.defaults.sourceOffset;
  const resolvedTransform = resolvePreviewTransform(visualSet, frame, snapshot.selectedClipId);
  const numberField = (label: string, path: string, value: unknown, unit: string): string => `<label class="studio-field"><span>${label}<small>${unit}</small></span><input type="number" step="1" inputmode="numeric" data-number-path="${path}" value="${escapeHtml(integerInputValue(value))}" /></label>`;
  const shapeField = (path: string, shape: CollisionShape | undefined): string => `<label class="studio-field"><span>Shape<small>collision primitive</small></span><select data-collision-shape-path="${path}"><option value="rectangle" ${(shape ?? 'rectangle') === 'rectangle' ? 'selected' : ''}>Rectangle</option><option value="circle" ${shape === 'circle' ? 'selected' : ''}>Circle</option><option value="ellipse" ${shape === 'ellipse' ? 'selected' : ''}>Ellipse</option></select></label>`;
  const behaviorField = character.kind === 'enemy' && character.enemy
    ? `<label class="studio-field studio-field--wide"><span>AI behavior<small>runtime controller</small></span><select data-select-path="enemy.ai.behavior"><option value="standard" ${(character.enemy.ai.behavior ?? 'standard') === 'standard' ? 'selected' : ''}>Standard</option><option value="slime-spider" ${character.enemy.ai.behavior === 'slime-spider' ? 'selected' : ''}>Slime spider</option></select></label>`
    : '';
  const booleanField = (label: string, path: string, checked: boolean, detail: string): string => `<label class="studio-toggle-field"><input type="checkbox" data-boolean-path="${path}" ${checked ? 'checked' : ''} /><span><strong>${label}</strong><small>${detail}</small></span></label>`;
  const body = character.body;
  const bodyShape = body.shape ?? 'rectangle';
  const attributes = character.attributes ?? { strength: 10, vitality: 10, agility: 10, intellect: 10 };
  const gameplay = (character.kind === 'player' ? character.player : character.enemy) as unknown as { maxHp: number; ai: { aggroRange: number; attackRange: number; wanderSpeed: number; chaseSpeed: number; attackCooldownMs: number; contactDamage: number; knockbackStrength: number; knockbackResist: number } };
  const gameplayFields = character.kind === 'player' && character.player
    ? `<div class="studio-field-grid">${numberField('Base speed', 'player.movement.baseSpeed', character.player.movement.baseSpeed, 'world units/s')}${numberField('Boost speed', 'player.movement.boostSpeed', character.player.movement.boostSpeed, 'world units/s')}${numberField('Dodge speed', 'player.movement.dodgeSpeed', character.player.movement.dodgeSpeed, 'world units/s')}${numberField('Dodge i-frames', 'player.movement.dodgeInvulnerabilityMs', character.player.movement.dodgeInvulnerabilityMs, 'milliseconds')}${numberField('Base max HP', 'player.progression.baseMaxHp', character.player.progression.baseMaxHp, 'points')}${numberField('Base max energy', 'player.progression.baseMaxEnergy', character.player.progression.baseMaxEnergy, 'points')}${numberField('HP / level', 'player.progression.hpPerLevel', character.player.progression.hpPerLevel, 'points')}${numberField('Attack / level', 'player.progression.attackPerLevel', character.player.progression.attackPerLevel, 'points')}</div>`
    : character.enemy && `<div class="studio-field-grid">${behaviorField}${numberField('Max HP', 'enemy.maxHp', gameplay.maxHp, 'points')}${numberField('Aggro range', 'enemy.ai.aggroRange', gameplay.ai.aggroRange, 'world units')}${numberField('Attack range', 'enemy.ai.attackRange', gameplay.ai.attackRange, 'world units')}${numberField('Wander speed', 'enemy.ai.wanderSpeed', gameplay.ai.wanderSpeed, 'world units/s')}${numberField('Chase speed', 'enemy.ai.chaseSpeed', gameplay.ai.chaseSpeed, 'world units/s')}${numberField('Cooldown', 'enemy.ai.attackCooldownMs', gameplay.ai.attackCooldownMs, 'milliseconds')}${numberField('Contact damage', 'enemy.ai.contactDamage', gameplay.ai.contactDamage, 'points')}${numberField('Knockback', 'enemy.ai.knockbackStrength', gameplay.ai.knockbackStrength, 'world units/s')}${numberField('Resist', 'enemy.ai.knockbackResist', gameplay.ai.knockbackResist, 'ratio 0–1')}</div>`;
  const capabilityFields = character.kind === 'enemy' && character.enemy
    ? `<div class="studio-capability-stack">${booleanField('Ranged attack', 'enemy.ai.isRanged', character.enemy.ai.isRanged, 'fires the authored projectile capability')}${booleanField('Leap / charge', 'enemy.ai.isLeaper', character.enemy.ai.isLeaper === true, 'enables the supported leap-range branch')}</div>${character.enemy.ai.isRanged ? `<div class="studio-capability-card"><div><span class="studio-kicker">Projectile capability</span><strong>Configured projectile</strong></div><label class="studio-field studio-field--wide"><span>Source asset<small>manifest</small></span><select data-select-path="enemy.projectile.assetId">${projectileAssetOptions(String(character.enemy.projectile?.assetId ?? ''))}</select></label>${numberField('Damage', 'enemy.projectile.damage', character.enemy.projectile?.damage ?? character.enemy.ai.contactDamage, 'points')}</div>` : ''}`
    : '';
  const advancedEnemyFields = character.kind === 'enemy' && character.enemy
    ? `<div class="studio-field-grid">${numberField('Flee threshold', 'enemy.ai.fleeRange', character.enemy.ai.fleeRange ?? 0, 'optional world units')}${numberField('Windup', 'enemy.ai.attackWindupMs', character.enemy.ai.attackWindupMs, 'milliseconds')}${numberField('Recovery', 'enemy.ai.attackRecoveryMs', character.enemy.ai.attackRecoveryMs, 'milliseconds')}${character.enemy.ai.isLeaper ? numberField('Leap range', 'enemy.ai.leapRange', character.enemy.ai.leapRange ?? 0, 'world units') : ''}${character.enemy.ai.isRanged ? numberField('Projectile speed', 'enemy.ai.projectileSpeed', character.enemy.ai.projectileSpeed ?? 0, 'world units/s') : ''}</div>`
    : '';
  return `<div class="studio-inspector-scroll">
    ${capabilityFields ? `<section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Capabilities</span><strong>Supported runtime modes</strong></div>${capabilityFields}${advancedEnemyFields}</section>` : ''}
    <section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Visual</span><strong>Alignment</strong></div><p class="studio-help">Offsets resolve from default to animation to frame. More specific values override the level before them.</p><div class="studio-field-grid">${numberField('Default offset X', 'visual.defaults.sourceOffset.0', visualSet.defaults.sourceOffset[0], 'source px')}${numberField('Default offset Y', 'visual.defaults.sourceOffset.1', visualSet.defaults.sourceOffset[1], 'source px')}${numberField('Scale X', 'visual.defaults.scale.0', visualSet.defaults.scale[0], 'multiplier')}${numberField('Scale Y', 'visual.defaults.scale.1', visualSet.defaults.scale[1], 'multiplier')}</div><div class="studio-subheading">Animation ${escapeHtml(snapshot.selectedClipId)} offset <button type="button" class="studio-link-button" data-action="reset-animation-visual">reset</button></div><div class="studio-field-grid">${numberField('Offset X', 'visual.animation.sourceOffset.0', animationOffset[0], animation?.sourceOffset ? 'source px override' : 'uses default')}${numberField('Offset Y', 'visual.animation.sourceOffset.1', animationOffset[1], animation?.sourceOffset ? 'source px override' : 'uses default')}</div><div class="studio-subheading">Frame ${frame} override <button type="button" class="studio-link-button" data-action="reset-frame-visual">reset</button></div><div class="studio-field-grid">${numberField('Offset X', 'visual.frame.sourceOffset.0', resolvedTransform.sourceOffset[0], transform.sourceOffset ? 'source px override' : 'uses animation')}${numberField('Offset Y', 'visual.frame.sourceOffset.1', resolvedTransform.sourceOffset[1], transform.sourceOffset ? 'source px override' : 'uses animation')}</div></section>
    <section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Body</span><strong>Stable movement body</strong></div><p class="studio-help">Circles use native Arcade Physics. Ellipses keep their authored geometry for hitbox math and use a conservative rectangle for world/tile movement collision.</p><div class="studio-field-grid">${shapeField('body.shape', bodyShape)}${bodyShape === 'circle' ? numberField('Radius', 'body.radius', body.radius ?? Math.min(body.width, body.height) / 2, 'world units') : bodyShape === 'ellipse' ? `${numberField('Radius X', 'body.radiusX', body.radiusX ?? body.width / 2, 'world units')}${numberField('Radius Y', 'body.radiusY', body.radiusY ?? body.height / 2, 'world units')}` : `${numberField('Width', 'body.width', body.width, 'world units')}${numberField('Height', 'body.height', body.height, 'world units')}`}${numberField('Center X', 'body.centerOffsetX', body.centerOffsetX, 'world units')}${numberField('Center Y', 'body.centerOffsetY', body.centerOffsetY, 'world units')}</div></section>
    <section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Attributes</span><strong>Base character attributes</strong></div><p class="studio-help">Movement speed is separate and comes from movement, equipment, or temporary effects. These values are the neutral foundation for future weapon and ability scaling.</p><div class="studio-field-grid">${numberField('Strength', 'attributes.strength', attributes.strength, 'base points')}${numberField('Vitality', 'attributes.vitality', attributes.vitality, 'base points')}${numberField('Agility', 'attributes.agility', attributes.agility, 'base points')}${numberField('Intellect', 'attributes.intellect', attributes.intellect, 'base points')}</div></section>
    <section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Gameplay</span><strong>${character.kind === 'player' ? 'Player progression' : 'Enemy behavior'}</strong></div>${gameplayFields}</section>
    <section class="studio-inspector-section studio-collision-shape-section"><div class="studio-section-heading"><span class="studio-kicker">Collision shapes</span><strong>Named geometry</strong></div><p class="studio-help">Use circles for rounded bodies. Ellipses are resolved by the authored hitbox system and previewed precisely in the Studio.</p>${Object.entries(character.hitboxes).map(([hitboxId, hitbox]) => { const shape = hitbox.shape ?? 'rectangle'; return `<div class="studio-collision-shape-row"><strong>${escapeHtml(hitboxId)}</strong>${shapeField(`hitbox.${hitboxId}.shape`, shape)}${shape === 'circle' ? numberField('Radius', `hitbox.${hitboxId}.radius`, hitbox.radius ?? Math.min(hitbox.width, hitbox.height) / 2, 'world') : shape === 'ellipse' ? `${numberField('Radius X', `hitbox.${hitboxId}.radiusX`, hitbox.radiusX ?? hitbox.width / 2, 'world')}${numberField('Radius Y', `hitbox.${hitboxId}.radiusY`, hitbox.radiusY ?? hitbox.height / 2, 'world')}` : ''}</div>`; }).join('') || '<p class="studio-empty-note">Add a named hitbox to author a shape.</p>'}</section>
    <section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Hitboxes</span><strong>Named attack geometry</strong><button type="button" class="studio-icon-button" data-action="add-hitbox">+</button></div>${Object.entries(character.hitboxes).map(([hitboxId, hitbox]) => `<div class="studio-hitbox-row studio-hitbox-row--expanded"><span class="hitbox-chip">${escapeHtml(hitboxId)}</span>${numberField('W', `hitbox.${hitboxId}.width`, hitbox.width, 'world')}${numberField('H', `hitbox.${hitboxId}.height`, hitbox.height, 'world')}${numberField('Offset X', `hitbox.${hitboxId}.offsetX`, hitbox.offsetX, 'world')}${numberField('Offset Y', `hitbox.${hitboxId}.offsetY`, hitbox.offsetY, 'world')}<label class="studio-hitbox-mirror"><input type="checkbox" data-boolean-path="hitbox.${hitboxId}.mirrorX" ${hitbox.mirrorX ? 'checked' : ''} /><span>MIRROR</span></label><button type="button" class="studio-icon-button is-danger" data-remove-hitbox="${escapeHtml(hitboxId)}">×</button></div>`).join('') || '<p class="studio-empty-note">No named hitboxes yet.</p>'}</section>
  </div>`;
}

function renderStudio(snapshot: CharacterDocumentSnapshot, assetShelf: AssetShelfState, creationForm: CreationFormState, returnEditor: string, playing = false, activeModal?: ActiveStudioModal): string {
  const { character, visualSet, selectedClipId, selectedTimelineIndex } = snapshot;
  const clip = visualSet.clips[selectedClipId];
  const info = assetFrameInfo(String(visualSet.assetId));
  const usedSourceFrames = new Set(clip?.frames ?? []);
  const selectedSourceFrames = new Set(snapshot.selectedSourceFrames);
  const normalizedClip = clip && clip.frames.length > 0 ? normalizeAnimationClip(clip) : undefined;
  const timeline = clip?.frames ?? [];
  const timelineView = normalizedClip ? createAnimationTimelineView(normalizedClip) : undefined;
  const timelineFrames = timelineView?.timelineFrames ?? 0;
  const selectedTimelineFrame = normalizedClip?.keyframeTimes[selectedTimelineIndex] ?? selectedTimelineIndex;
  const track = character.animationTracks[selectedClipId] ?? {};
  const selectedFrame = timeline[selectedTimelineIndex] ?? snapshot.selectedSourceFrame;
  const previewColumn = selectedFrame % info.columns;
  const previewRow = Math.floor(selectedFrame / info.columns);
  const transform = resolvePreviewTransform(visualSet, selectedFrame, selectedClipId);
  const previewScale = numberValue(transform.scale[0], 1) * 2.8;
  const originOffsetX = -numberValue(transform.origin[0], 0.5) * info.width * previewScale;
  const originOffsetY = -numberValue(transform.origin[1], 0.5) * info.height * previewScale;
  const bodyDimensions = resolveCollisionShapeDimensions(character.body);
  const bodyWidth = bodyDimensions.width * 3;
  const bodyHeight = bodyDimensions.height * 3;
  const hitboxGuides = Object.entries(character.hitboxes).map(([hitboxId, hitbox]) => { const dimensions = resolveCollisionShapeDimensions(hitbox); const shapeStyle = dimensions.shape === 'rectangle' ? '' : 'border-radius:50%;'; return `<span class="stage-hitbox stage-hitbox--${dimensions.shape}" style="width:${dimensions.width * 3}px;height:${dimensions.height * 3}px;${shapeStyle}transform:translate(-50%,-50%) translate(${hitbox.offsetX * 3}px,${hitbox.offsetY * 3}px)" title="${escapeHtml(hitboxId)}"><small>${escapeHtml(hitboxId)}</small></span>`; }).join('');
  const trackSpans = track.hitboxSpans ?? [];
  const selectedSpans = trackSpans.filter((span) => span.from <= selectedTimelineFrame && selectedTimelineFrame <= span.through);
  const selectedEvents = (track.events ?? []).filter((event) => event.at === selectedTimelineFrame);
  const spanSummary = selectedSpans.length > 0 ? selectedSpans.map((span) => `${escapeHtml(span.hitboxId)} · frames ${span.from}–${span.through}`).join(' / ') : 'none on this frame';
  const eventSummary = selectedEvents.length > 0 ? selectedEvents.map((event) => escapeHtml(event.eventId)).join(' / ') : 'none on this frame';
  const trackHitboxIds = Array.from(new Set([...Object.keys(character.hitboxes), ...trackSpans.map((span) => span.hitboxId)]));
  const hitboxTrackRows = trackHitboxIds.length > 0
    ? trackHitboxIds.map((hitboxId) => `<div class="timeline-track-row"><span class="timeline-track-label" title="${escapeHtml(hitboxId)}">${escapeHtml(hitboxId)}</span>${Array.from({ length: timelineFrames }, (_, index) => `<span class="timeline-cell${trackSpans.some((span) => span.hitboxId === hitboxId && span.from <= index && index <= span.through) ? ' is-hot' : ''}"></span>`).join('')}</div>`).join('')
    : '<div class="timeline-track-row"><span class="timeline-track-label">HITBOX</span><span class="timeline-track-empty">Add a named hitbox to author active frames.</span></div>';
  return `<main class="character-studio ${statusClass(snapshot)}" data-studio-root>
    <header class="studio-topbar"><a class="studio-brand" href="?" aria-label="Back to game"><span class="brand-mark">✦</span><span><small>FIELD CARTOGRAPHER</small><strong>CHARACTER STUDIO</strong></span></a><div class="studio-topbar-actions"><span class="studio-save-state"><i></i>${escapeHtml(snapshot.statusMessage)}</span><button type="button" class="studio-button studio-button--quiet" data-action="undo" ${snapshot.dirty ? '' : 'disabled'}>↶</button><button type="button" class="studio-button studio-button--quiet" data-action="redo">↷</button><button type="button" class="studio-button studio-button--save" data-action="save" ${snapshot.errors.length > 0 || !snapshot.dirty ? 'disabled' : ''}>SAVE DRAFT</button></div></header>
    <div class="studio-layout">
      <aside class="studio-library"><div class="studio-panel-title"><div><span class="studio-kicker">Catalog</span><h1>Characters</h1></div><span class="studio-count">${characterPackages.length.toString().padStart(2, '0')}</span></div><label class="studio-search"><span>⌕</span><input type="search" placeholder="Filter roster" data-library-search /></label><div class="studio-roster" data-roster>${characterPackages.map((entry) => `<button type="button" class="studio-roster-item${entry.characterId === character.characterId ? ' is-active' : ''}" data-character-id="${escapeHtml(entry.characterId)}" data-character-name="${escapeHtml(entry.character.displayName)}"><span class="roster-glyph ${entry.character.kind}">${entry.character.kind === 'player' ? '●' : '◆'}</span><span><strong>${escapeHtml(entry.character.displayName)}</strong><small>${entry.character.kind === 'player' ? 'PLAYER' : 'ENEMY'} ${entry.character.runtimeRole ? '· PRIMARY' : ''}</small></span><em>${entry.characterId === character.characterId ? 'OPEN' : ''}</em></button>`).join('')}</div><div class="studio-library-footer"><button type="button" class="studio-button studio-button--outline studio-button--create" data-action="new-character">NEW CHARACTER</button><button type="button" class="studio-button studio-button--outline" data-action="duplicate">DUPLICATE PACKAGE</button><a class="studio-button studio-button--outline studio-button--navigation" href="?editor=${encodeURIComponent(returnEditor)}" data-testid="map-editor-link">↗ OPEN FIELD CARTOGRAPHER</a></div></aside>
      <section class="studio-workbench"><div class="studio-workbench-heading"><div><span class="studio-kicker">${character.kind === 'player' ? 'Player package' : 'Enemy package'}</span><h2>${escapeHtml(character.displayName)} <span>${escapeHtml(character.characterId)}</span></h2></div><div class="studio-workbench-meta"><span>ASSET <b>${escapeHtml(visualSet.assetId)}</b></span><span>GRID <b>${info.columns} × ${info.rows}</b></span><span>FRAMES <b>${info.count}</b></span></div></div>
        <section class="studio-preview-card"><div class="studio-preview-toolbar"><span class="studio-kicker">ANCHOR-LOCKED PREVIEW</span><div class="studio-toolbar-actions"><button type="button" class="studio-pill is-active" data-action="toggle-grid">GRID</button><button type="button" class="studio-pill is-active" data-action="toggle-body">BODY</button><button type="button" class="studio-pill" data-action="toggle-mirror">MIRROR</button><button type="button" class="studio-pill" data-action="toggle-onion">ONION</button></div></div><div class="studio-stage" data-preview-stage><span class="stage-axis stage-axis-x"></span><span class="stage-axis stage-axis-y"></span><span class="stage-anchor">+</span><span class="stage-label">WORLD ANCHOR</span><span class="stage-body" style="width:${bodyWidth}px;height:${bodyHeight}px;transform:translate(-50%,-50%) translate(${character.body.centerOffsetX * 3}px,${character.body.centerOffsetY * 3}px)"></span>${hitboxGuides}<span class="stage-sprite" style="--sheet-url:url('${info.url}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:${previewColumn * info.width}px;--frame-y:${previewRow * info.height}px;--preview-scale:${previewScale};--origin-offset-x:${originOffsetX}px;--origin-offset-y:${originOffsetY}px;--offset-x:${numberValue(transform.sourceOffset[0]) * previewScale}px;--offset-y:${numberValue(transform.sourceOffset[1]) * previewScale}px"></span><span class="stage-caption"><b>${escapeHtml(selectedClipId)}</b><span>POSITION ${selectedTimelineIndex + 1} / ${timeline.length} · SOURCE ${selectedFrame}</span></span></div><div class="studio-preview-footer"><span><i class="legend-dot legend-dot--amber"></i> art transform</span><span><i class="legend-dot legend-dot--red"></i> stable body</span><span><i class="legend-dot legend-dot--cyan"></i> hitbox</span><label>ZOOM <input type="range" min="1" max="2" step="1" value="1" data-preview-zoom /></label></div></section>
        <section class="studio-sheet-panel"><div class="studio-section-bar"><div><span class="studio-kicker">Source sheet</span><strong>Click frames to select · click again to deselect</strong></div><span class="studio-muted">${info.width} × ${info.height} px cells</span></div><div class="studio-sheet-grid">${Array.from({ length: info.count }, (_, frame) => renderFrameTile(frame, info, selectedSourceFrames.has(frame), false, true, usedSourceFrames.has(frame))).join('')}</div><div class="studio-sheet-actions"><button type="button" class="studio-button studio-button--accent" data-action="append-frame">+ APPEND SELECTED</button><button type="button" class="studio-button studio-button--quiet" data-action="insert-frame">INSERT AT PLAYHEAD</button><span class="studio-selection-note">focused source ${snapshot.selectedSourceFrame} · ${selectedSourceFrames.size} selected · ${usedSourceFrames.size} used</span></div></section>
        <section class="studio-timeline-panel"><div class="studio-section-bar"><div><span class="studio-kicker">Animation timeline</span><strong>Editing <span class="studio-inline-clip-name">${escapeHtml(selectedClipId)}</span></strong></div><span class="studio-muted">Drag keyframes to reorder · blocks show their hold length · ◆ = event</span><div class="studio-clip-actions"><button type="button" class="studio-icon-button" data-action="add-clip" title="Create a new animation clip" aria-label="Create a new animation clip">+</button><button type="button" class="studio-icon-button" data-action="rename-clip" title="Rename the current animation clip" aria-label="Rename the current animation clip">✎</button><button type="button" class="studio-icon-button" data-action="duplicate-clip" title="Duplicate the current animation clip" aria-label="Duplicate the current animation clip">⧉</button><button type="button" class="studio-icon-button is-danger" data-action="remove-clip" title="Remove the current animation clip" aria-label="Remove the current animation clip">×</button></div></div><div class="studio-clip-tabs">${Object.entries(visualSet.clips).map(([id, entry]) => `<button type="button" class="studio-clip-tab${id === selectedClipId ? ' is-active' : ''}" data-clip-id="${escapeHtml(id)}" title="Edit ${escapeHtml(id)}"><span>${escapeHtml(id)}</span><small>${entry.frames.length}K · ${entry.durationSeconds?.toFixed(2) ?? (entry.frames.length / entry.framesPerSecond).toFixed(2)}s</small></button>`).join('')}</div><div class="studio-timeline"><div class="timeline-ruler">${Array.from({ length: timelineView?.timelineFrames ?? 0 }, (_, index) => `<span>${String(index).padStart(2, '0')}</span>`).join('')}</div><div class="timeline-frames">${timeline.map((frame, index) => { const keyframe = timelineView?.keyframes[index]; const hold = keyframe?.hold ?? 1; const start = keyframe?.start ?? index; return `<button type="button" class="timeline-frame${index === selectedTimelineIndex ? ' is-active' : ''}" data-timeline-index="${index}" draggable="true" title="Keyframe ${index}. Holds ${hold} timeline frame${hold === 1 ? '' : 's'}. Drag to reorder." style="--timeline-hold:${Math.max(1, hold)}"><span class="timeline-frame-hold">${hold}F</span>${renderFrameTile(frame, info, false, true, false)}<span class="timeline-frame-number">${start}</span>${(track.events ?? []).filter((event) => event.at >= start && event.at < start + hold).map((event) => `<i class="event-marker" title="${escapeHtml(event.eventId)}" aria-label="Event: ${escapeHtml(event.eventId)}">◆</i>`).join('')}</button>`; }).join('')}</div>${hitboxTrackRows}</div><div class="studio-timeline-selection"><span><b data-timeline-selection-frame>KEYFRAME ${String(selectedTimelineIndex).padStart(2, '0')} · FRAME ${String(selectedTimelineFrame).padStart(2, '0')}</b></span><span><strong>HITBOX</strong> <span data-timeline-selection-hitbox>${spanSummary}</span></span><span><strong>EVENTS</strong> <span data-timeline-selection-events>${eventSummary}</span></span></div><div class="studio-timeline-help"><div><b>+ HITBOX SPAN</b><p>Marks a named hitbox active from the selected timeline frame through an inclusive end frame. Runtime collision callbacks use these timeline cells.</p></div><div><b>+ EVENT</b><p>Adds a one-frame event ID for runtime listeners. It is metadata only; it does not change the sprite by itself.</p></div></div><div class="studio-playback"><button type="button" class="studio-button studio-button--play${playing ? ' is-playing' : ''}" data-action="play" aria-pressed="${playing}" title="${playing ? 'Stop clip playback' : 'Play this clip'}">${playing ? '■ STOP CLIP' : '▶ PLAY CLIP'}</button><button type="button" class="studio-button studio-button--quiet" data-action="previous-frame">‹</button><button type="button" class="studio-button studio-button--quiet" data-action="next-frame">›</button><button type="button" class="studio-button studio-button--quiet" data-action="add-span" title="Mark a hitbox active across a range of timeline frames">+ HITBOX SPAN</button><button type="button" class="studio-button studio-button--quiet" data-action="add-event" title="Add a one-frame runtime event marker">+ EVENT</button><label class="studio-inline-field">FPS <input type="number" min="1" max="240" step="1" inputmode="numeric" value="${integerInputValue(clip?.framesPerSecond, 8)}" data-clip-fps /></label><label class="studio-inline-field">DURATION <input type="number" min="0.01" max="60" step="0.01" inputmode="decimal" value="${Number(clip?.durationSeconds ?? (timeline.length / Math.max(clip?.framesPerSecond ?? 8, 1))).toFixed(2)}" data-clip-duration /></label><label class="studio-switch"><input type="checkbox" ${clip?.loop ? 'checked' : ''} data-clip-loop /><span></span> LOOP</label><button type="button" class="studio-button studio-button--quiet is-danger" data-action="remove-frame" ${timeline.length <= 1 ? 'disabled' : ''}>REMOVE KEYFRAME</button></div></section>
      </section>
      <aside class="studio-inspector"><div class="studio-inspector-heading"><span class="studio-kicker">Inspector</span><h2>${escapeHtml(character.displayName)}</h2><p>${character.kind === 'player' ? 'Primary player runtime package' : 'Enemy runtime package'}</p></div>${renderInspector(snapshot)}${snapshot.errors.length > 0 ? `<section class="studio-errors"><div class="studio-section-heading"><span class="studio-kicker">Validation</span><strong>${snapshot.errors.length} issue${snapshot.errors.length === 1 ? '' : 's'}</strong></div>${snapshot.errors.map((error) => `<p><b>${escapeHtml(error.path)}</b> ${escapeHtml(error.message)}</p>`).join('')}</section>` : ''}</aside>
    </div>
    ${renderAssetShelf(assetShelf, String(visualSet.assetId), creationForm)}
    ${renderStudioModal(activeModal)}
  </main>`;
}

function decorateLoopModeControl(container: HTMLDivElement, clip: VisualClipDocument | undefined): void {
  const loopToggle = container.querySelector<HTMLInputElement>('[data-clip-loop]');
  const loopLabel = loopToggle?.closest('label');
  if (!loopToggle || !loopLabel || container.querySelector('[data-clip-loop-mode]')) return;
  const label = document.createElement('label');
  label.className = 'studio-inline-field';
  label.append('MODE ');
  const select = document.createElement('select');
  select.className = 'studio-inline-select';
  select.dataset.clipLoopMode = '';
  select.disabled = !loopToggle.checked;
  for (const [value, text] of [['wrap', 'WRAP'], ['ping-pong', 'PING-PONG']] as const) {
    const option = document.createElement('option');
    option.value = value;
    option.textContent = text;
    option.selected = (clip?.loopMode ?? 'wrap') === value;
    select.append(option);
  }
  label.append(select);
  loopLabel.after(label);
}

function updatePlaybackFrameDom(container: HTMLDivElement, snapshot: CharacterDocumentSnapshot): void {
  const clip = snapshot.visualSet.clips[snapshot.selectedClipId];
  const timeline = clip?.frames ?? [];
  if (!clip || timeline.length === 0) return;
  const index = Math.max(0, Math.min(snapshot.selectedTimelineIndex, timeline.length - 1));
  const frame = timeline[index] ?? 0;
  const info = assetFrameInfo(String(snapshot.visualSet.assetId));
  const transform = resolvePreviewTransform(snapshot.visualSet, frame, snapshot.selectedClipId);
  const previewColumn = frame % info.columns;
  const previewRow = Math.floor(frame / info.columns);
  const previewScale = numberValue(transform.scale[0], 1) * 2.8;
  const originOffsetX = -numberValue(transform.origin[0], 0.5) * info.width * previewScale;
  const originOffsetY = -numberValue(transform.origin[1], 0.5) * info.height * previewScale;
  const sprite = container.querySelector<HTMLElement>('.stage-sprite');
  sprite?.style.setProperty('--frame-x', `${previewColumn * info.width}px`);
  sprite?.style.setProperty('--frame-y', `${previewRow * info.height}px`);
  sprite?.style.setProperty('--preview-scale', String(previewScale));
  sprite?.style.setProperty('--origin-offset-x', `${originOffsetX}px`);
  sprite?.style.setProperty('--origin-offset-y', `${originOffsetY}px`);
  sprite?.style.setProperty('--offset-x', `${numberValue(transform.sourceOffset[0]) * previewScale}px`);
  sprite?.style.setProperty('--offset-y', `${numberValue(transform.sourceOffset[1]) * previewScale}px`);
  container.querySelectorAll<HTMLElement>('.timeline-frame.is-active').forEach((item) => item.classList.remove('is-active'));
  container.querySelector<HTMLElement>(`.timeline-frame[data-timeline-index="${index}"]`)?.classList.add('is-active');
  const caption = container.querySelector<HTMLElement>('.stage-caption span');
  const normalizedClip = normalizeAnimationClip(clip);
  const timelineFrame = normalizedClip.keyframeTimes[index] ?? index;
  if (caption) caption.textContent = `KEYFRAME ${index + 1} / ${timeline.length} · FRAME ${timelineFrame + 1} / ${timelineFrameCount(normalizedClip)} · SOURCE ${frame}`;
  const track = snapshot.character.animationTracks[snapshot.selectedClipId] ?? {};
  const selectedSpans = (track.hitboxSpans ?? []).filter((span) => span.from <= timelineFrame && timelineFrame <= span.through);
  const selectedEvents = (track.events ?? []).filter((event) => event.at === timelineFrame);
  const spanSummary = selectedSpans.length > 0 ? selectedSpans.map((span) => `${span.hitboxId} · frames ${span.from}–${span.through}`).join(' / ') : 'none on this frame';
  const eventSummary = selectedEvents.length > 0 ? selectedEvents.map((event) => event.eventId).join(' / ') : 'none on this frame';
  const frameSummary = container.querySelector<HTMLElement>('[data-timeline-selection-frame]');
  if (frameSummary) frameSummary.textContent = `KEYFRAME ${String(index).padStart(2, '0')} · FRAME ${String(timelineFrame).padStart(2, '0')}`;
  const hitboxSummary = container.querySelector<HTMLElement>('[data-timeline-selection-hitbox]');
  if (hitboxSummary) hitboxSummary.textContent = spanSummary;
  const eventSummaryElement = container.querySelector<HTMLElement>('[data-timeline-selection-events]');
  if (eventSummaryElement) eventSummaryElement.textContent = eventSummary;
}

async function loadPackage(characterId: string): Promise<PackageResponse> {
  const response = await fetch(`/__character-studio/package/${encodeURIComponent(characterId)}`);
  const payload = await response.json() as { ok: boolean; data?: PackageResponse; error?: { message?: string } };
  if (!response.ok || !payload.ok || !payload.data) throw new Error(payload.error?.message ?? 'Character package failed to load');
  return payload.data;
}

async function loadAssetCatalog(): Promise<CharacterStudioAssetCatalog> {
  const response = await fetch('/__character-studio/assets');
  const payload = await response.json() as { ok: boolean; data?: CharacterStudioAssetCatalog; error?: { message?: string } };
  if (!response.ok || !payload.ok || !payload.data) throw new Error(payload.error?.message ?? 'Source asset catalog failed to load');
  return payload.data;
}

const STUDIO_SCROLL_REGION_SELECTORS = [
  '.studio-workbench',
  '.studio-roster',
  '.studio-inspector-scroll',
  '.studio-sheet-grid',
  '.studio-clip-tabs',
  '.studio-timeline',
] as const;

interface StudioScrollPosition {
  readonly selector: string;
  readonly top: number;
  readonly left: number;
}

function captureStudioScroll(container: HTMLDivElement): StudioScrollPosition[] {
  return STUDIO_SCROLL_REGION_SELECTORS.flatMap((selector) => {
    const region = container.querySelector<HTMLElement>(selector);
    return region ? [{ selector, top: region.scrollTop, left: region.scrollLeft }] : [];
  });
}

function restoreStudioScroll(container: HTMLDivElement, positions: readonly StudioScrollPosition[]): void {
  for (const position of positions) {
    const region = container.querySelector<HTMLElement>(position.selector);
    if (!region) continue;
    region.scrollTop = position.top;
    region.scrollLeft = position.left;
  }
}

function ensureProjectileStudioLink(container: HTMLDivElement, returnEditor: string): void {
  const footer = container.querySelector<HTMLElement>('.studio-library-footer');
  if (!footer) return;
  if (!footer.querySelector('[data-projectile-studio-link]')) {
    const link = document.createElement('a');
    link.className = 'studio-button studio-button--outline studio-button--navigation';
    link.href = `?studio=projectiles&editor=${encodeURIComponent(returnEditor)}`;
    link.dataset.projectileStudioLink = 'true';
    link.textContent = 'PROJECTILE STUDIO';
    footer.append(link);
  }
  if (footer.querySelector('[data-weapon-studio-link]')) return;
  const link = document.createElement('a');
  link.className = 'studio-button studio-button--outline studio-button--navigation';
  link.href = `?studio=weapons&editor=${encodeURIComponent(returnEditor)}`;
  link.dataset.weaponStudioLink = 'true';
  link.textContent = 'WEAPON STUDIO';
  footer.append(link);
}

function decorateBodyPreview(container: HTMLDivElement, body: CharacterDocumentSnapshot['character']['body']): void {
  const stageBody = container.querySelector<HTMLElement>('[data-preview-stage] .stage-body');
  if (!stageBody) return;
  const shape = body.shape ?? 'rectangle';
  stageBody.classList.remove('stage-body--rectangle', 'stage-body--circle', 'stage-body--ellipse');
  stageBody.classList.add(`stage-body--${shape}`);
  stageBody.style.borderRadius = shape === 'rectangle' ? '0' : '50%';
}

async function createPackageRequest(form: CreationFormState): Promise<{ readonly characterId: string; readonly revision: string; readonly reloadRequired: true }> {
  const response = await fetch('/__character-studio/package/create', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(form) });
  const payload = await response.json() as { ok: boolean; data?: { characterId: string; revision: string; reloadRequired: true }; error?: { message?: string } };
  if (!response.ok || !payload.ok || !payload.data) throw new Error(payload.error?.message ?? 'Package creation failed');
  return payload.data;
}

export function mountCharacterStudio(container: HTMLDivElement): () => void {
  container.classList.add('is-character-studio-host');
  let currentState: CharacterDocumentState | undefined;
  let unsubscribe: (() => void) | undefined;
  let disposed = false;
  let playTimer: number | undefined;
  let playbackTick = false;
  let activeModal: ActiveStudioModal | undefined;
  let sourceTilePickerOpen = false;
  let assetShelf: AssetShelfState = { open: false, loading: false };
  let creationForm: CreationFormState = { kind: 'enemy', template: 'melee-enemy', characterId: '', displayName: '', assetId: '' };
  const query = new URLSearchParams(window.location.search);
  const returnEditor = query.get('editor') ?? 'meadow-crossing';
  let currentId = query.get('character') ?? characterPackages[0]?.characterId ?? '';
  const studioUrl = (characterId: string): string => `?studio=characters&character=${encodeURIComponent(characterId)}&editor=${encodeURIComponent(returnEditor)}`;
  const stopPlayback = (): void => {
    if (playTimer !== undefined) {
      window.clearInterval(playTimer);
      playTimer = undefined;
    }
  };

  const renderLoading = (message: string): void => { container.innerHTML = `<main class="character-studio studio-loading"><div><span class="studio-loading-orb">✦</span><p>${escapeHtml(message)}</p></div></main>`; };
  const ensureTimelineTilePickerButton = (): void => {
    const actions = container.querySelector<HTMLElement>('.studio-timeline-panel .studio-clip-actions');
    if (!actions || actions.querySelector('[data-action="open-character-tile-picker"]')) return;
    actions.insertAdjacentHTML('afterbegin', '<button type="button" class="studio-button studio-button--save studio-timeline-add-tiles" data-action="open-character-tile-picker">+ ADD TILES</button>');
  };
  const renderViewport = (snapshot: CharacterDocumentSnapshot): void => {
    const scrollPositions = captureStudioScroll(container);
    const active = document.activeElement as HTMLElement | null;
    const windowPosition = { x: window.scrollX, y: window.scrollY };
    const focusedSource = active?.dataset.sourceFrame;
    if (disposed) return;
    if (playbackTick && playTimer !== undefined) {
      updatePlaybackFrameDom(container, snapshot);
      return;
    }
    container.innerHTML = renderStudio(snapshot, assetShelf, creationForm, returnEditor, playTimer !== undefined, activeModal);
    container.querySelector('.studio-sheet-panel')?.classList.add('is-source-bank-hidden');
    if (sourceTilePickerOpen) container.insertAdjacentHTML('beforeend', renderCharacterSourceTilePicker(snapshot));
    ensureStudioModeTabs(container, returnEditor, 'characters');
    ensureProjectileStudioLink(container, returnEditor);
    ensureTimelineTilePickerButton();
    decorateBodyPreview(container, snapshot.character.body);
    decorateLoopModeControl(container, snapshot.visualSet.clips[snapshot.selectedClipId]);
    syncAssetCreationControls(container, assetShelf, String(snapshot.visualSet.assetId), creationForm);
    restoreStudioScroll(container, scrollPositions);
    window.scrollTo(windowPosition.x, windowPosition.y);
    if (focusedSource) container.querySelector<HTMLElement>(`[data-source-frame="${focusedSource}"]`)?.focus({ preventScroll: true });
    window.requestAnimationFrame(() => { restoreStudioScroll(container, scrollPositions); window.scrollTo(windowPosition.x, windowPosition.y); });
  };
  const rerender = (snapshot: CharacterDocumentSnapshot): void => {
    if (disposed) return;
    renderViewport(snapshot);
  };
  const rerenderShelf = (): void => {
    if (!disposed && currentState) {
      const scrollPositions = captureStudioScroll(container);
      container.innerHTML = renderStudio(currentState.value, assetShelf, creationForm, returnEditor, playTimer !== undefined, activeModal);
      container.querySelector('.studio-sheet-panel')?.classList.add('is-source-bank-hidden');
      if (sourceTilePickerOpen) container.insertAdjacentHTML('beforeend', renderCharacterSourceTilePicker(currentState.value));
      ensureStudioModeTabs(container, returnEditor, 'characters');
      ensureProjectileStudioLink(container, returnEditor);
      ensureTimelineTilePickerButton();
      decorateBodyPreview(container, currentState.value.character.body);
      decorateLoopModeControl(container, currentState.value.visualSet.clips[currentState.value.selectedClipId]);
      syncAssetCreationControls(container, assetShelf, String(currentState.value.visualSet.assetId), creationForm);
      restoreStudioScroll(container, scrollPositions);
      window.requestAnimationFrame(() => restoreStudioScroll(container, scrollPositions));
    }
  };
  const settleModal = (result: StudioModalResult): void => {
    const modal = activeModal;
    if (!modal) return;
    activeModal = undefined;
    modal.resolve(result);
    if (currentState) rerender(currentState.value);
  };
  const showModal = (request: StudioModalRequest): Promise<StudioModalResult> => new Promise((resolve) => {
    if (activeModal) activeModal.resolve(undefined);
    activeModal = { request, resolve };
    if (currentState) rerender(currentState.value);
    queueMicrotask(() => {
      const input = container.querySelector<HTMLInputElement>('[data-modal-autofocus]');
      input?.focus();
      input?.select();
    });
  });
  const promptModal = async (request: Omit<StudioModalRequest, 'kind'>): Promise<Record<string, string> | undefined> => {
    const result = await showModal({ ...request, kind: 'prompt' });
    return result && typeof result !== 'boolean' ? result : undefined;
  };
  const confirmModal = async (request: Omit<StudioModalRequest, 'kind'>): Promise<boolean> => (await showModal({ ...request, kind: 'confirm' })) === true;
  const alertModal = async (title: string, message: string): Promise<void> => { await showModal({ kind: 'alert', title, message, confirmLabel: 'GOT IT' }); };
  const choosePackage = async (characterId: string): Promise<void> => {
    if (currentState?.value.dirty && !(await confirmModal({ title: 'Discard unsaved changes?', message: 'The current Character Studio package has unsaved changes. Opening another package will discard them.', confirmLabel: 'DISCARD & OPEN', danger: true }))) return;
    stopPlayback();
    renderLoading('Opening package…');
    try {
      const loaded = await loadPackage(characterId);
      currentState = new CharacterDocumentState({ character: loaded.character, visualSet: loaded.visualSet }, loaded.revision);
      unsubscribe?.();
      unsubscribe = currentState.subscribe(rerender);
      currentId = characterId;
      window.history.replaceState({}, '', studioUrl(characterId));
    } catch (error) {
      renderLoading(error instanceof Error ? error.message : String(error));
    }
  };
  const promptClipId = async (title: string, suggestion: string, label = 'Animation ID', message = 'Choose a stable lowercase animation ID. The selected clip is already editable; this dialog is only for naming.'): Promise<string | undefined> => {
    const values = await promptModal({ title, message, fields: [{ id: 'clipId', label, value: suggestion, placeholder: label === 'Hitbox ID' ? 'sword' : 'attack-side' }], confirmLabel: 'CONTINUE' });
    const value = values?.clipId?.trim().toLowerCase();
    return value || undefined;
  };
  const save = async (): Promise<void> => {
    if (!currentState || currentState.value.errors.length > 0 || !currentState.value.dirty) return;
    const snapshot = currentState.value;
    currentState.markSaving();
    try {
      const characterId = snapshot.character.characterId || currentId;
      const response = await fetch('/__character-studio/package/update', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ characterId, expectedRevision: snapshot.revision, character: snapshot.character, visualSet: snapshot.visualSet }) });
      const payload = await response.json() as { ok: boolean; data?: PackageResponse; error?: { message?: string; issues?: Array<{ path: string; message: string }> } };
      if (!response.ok || !payload.ok || !payload.data) {
        currentState.markSaveFailure(payload.error?.message ?? 'Save failed', response.status === 409);
        return;
      }
      currentState.markSaved({ character: payload.data.character, visualSet: payload.data.visualSet }, payload.data.revision);
    } catch (error) { currentState.markSaveFailure(error instanceof Error ? error.message : String(error)); }
  };
  const duplicate = async (): Promise<void> => {
    if (!currentState) return;
    const snapshot = currentState.value;
    const values = await promptModal({ title: 'Duplicate character package', message: 'Create a separate package from the current character. This does not change the package you are editing.', fields: [{ id: 'characterId', label: 'New stable character ID', value: `${snapshot.character.characterId}-copy`, placeholder: 'ice-worm-copy' }, { id: 'displayName', label: 'New display name', value: `${snapshot.character.displayName} Copy`, placeholder: 'Ice Worm Copy' }], confirmLabel: 'DUPLICATE PACKAGE' });
    const nextId = values?.characterId?.trim().toLowerCase();
    const displayName = values?.displayName?.trim();
    if (!nextId || !displayName) return;
    try {
      const response = await fetch('/__character-studio/package/duplicate', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ sourceCharacterId: snapshot.character.characterId, characterId: nextId, newDisplayName: displayName, character: snapshot.character, visualSet: snapshot.visualSet }) });
      const payload = await response.json() as { ok: boolean; data?: { characterId: string }; error?: { message?: string } };
      if (!response.ok || !payload.ok || !payload.data) { currentState.markSaveFailure(payload.error?.message ?? 'Duplicate failed'); return; }
      window.location.assign(studioUrl(payload.data.characterId));
    } catch (error) { currentState.markSaveFailure(error instanceof Error ? error.message : String(error)); }
  };
  const openAssetShelf = async (): Promise<void> => {
    const selectedAssetId = currentState?.value.visualSet.assetId ?? '';
    creationForm = { ...creationForm, assetId: selectedAssetId, characterId: '', displayName: '' };
    assetShelf = { open: true, loading: true, selectedAssetId };
    rerenderShelf();
    try {
      const catalog = await loadAssetCatalog();
      if (disposed) return;
      const nextAssetId = catalog.assets.some((entry) => entry.assetId === assetShelf.selectedAssetId)
        ? assetShelf.selectedAssetId
        : catalog.assets[0]?.assetId;
      creationForm = { ...creationForm, assetId: nextAssetId ?? '' };
      assetShelf = { open: true, loading: false, catalog, selectedAssetId: nextAssetId };
    } catch (error) {
      assetShelf = { open: true, loading: false, error: error instanceof Error ? error.message : String(error) };
    }
    rerenderShelf();
  };
  const createPackage = async (): Promise<void> => {
    const form = { ...creationForm, characterId: creationForm.characterId.trim().toLowerCase(), displayName: creationForm.displayName.trim() };
    if (!form.assetId || !form.characterId || !form.displayName) {
      assetShelf = { ...assetShelf, notice: 'Choose a source, stable ID, and display name first.' };
      rerenderShelf();
      return;
    }
    creationForm = form;
    assetShelf = { ...assetShelf, submitting: true, notice: 'Writing the starter package…' };
    rerenderShelf();
    try {
      const result = await createPackageRequest(form);
      window.location.assign(studioUrl(result.characterId));
    } catch (error) {
      assetShelf = { ...assetShelf, submitting: false, notice: error instanceof Error ? error.message : String(error) };
      rerenderShelf();
    }
  };
  const registerUpload = async (file: File): Promise<void> => {
    const form = { ...creationForm, characterId: creationForm.characterId.trim().toLowerCase(), displayName: creationForm.displayName.trim() };
    if (!form.characterId || !form.displayName) {
      assetShelf = { ...assetShelf, notice: 'Enter stable ID and display name before importing a PNG.' };
      rerenderShelf();
      return;
    }
    creationForm = form;
    const values = await promptModal({ title: 'Import PNG source', message: 'Define the spritesheet grid for this new character package. Leave populated frames empty to use the full grid.', fields: [{ id: 'assetId', label: 'New asset ID', value: `character.${form.kind}.new`, placeholder: 'character.enemy.ice-worm' }, { id: 'frameWidth', label: 'Frame width (px)', value: '64', inputType: 'number' }, { id: 'frameHeight', label: 'Frame height (px)', value: '64', inputType: 'number' }, { id: 'populatedCount', label: 'Populated frames', placeholder: 'Optional', inputType: 'number', optional: true }], confirmLabel: 'IMPORT & CREATE' });
    const assetId = values?.assetId?.trim().toLowerCase();
    const frameWidthText = values?.frameWidth?.trim();
    const frameHeightText = values?.frameHeight?.trim();
    if (!assetId || !frameWidthText || !frameHeightText) return;
    const frameWidth = integerInputValue(frameWidthText, 64);
    const frameHeight = integerInputValue(frameHeightText, 64);
    const populatedCount = values?.populatedCount?.trim();
    const metadata: Record<string, string> = {
      assetId,
      frameWidth,
      frameHeight,
      kind: form.kind,
      template: form.template,
      characterId: form.characterId,
      displayName: form.displayName,
    };
    if (populatedCount) metadata.populatedCount = integerInputValue(populatedCount);
    const body = new FormData();
    body.append('metadata', JSON.stringify(metadata));
    body.append('file', file, file.name);
    assetShelf = { ...assetShelf, submitting: true, notice: 'Committing the PNG source + starter package…' };
    rerenderShelf();
    try {
      const response = await fetch('/__character-studio/create', { method: 'POST', body });
      const payload = await response.json() as { ok: boolean; data?: { characterId: string }; error?: { message?: string } };
      if (!response.ok || !payload.ok || !payload.data) throw new Error(payload.error?.message ?? 'Character creation failed');
      window.location.assign(studioUrl(payload.data.characterId));
    } catch (error) {
      assetShelf = { ...assetShelf, submitting: false, notice: error instanceof Error ? error.message : String(error) };
      rerenderShelf();
    }
  };
  const handleAction = async (action: string, actionElement?: HTMLElement): Promise<void> => {
    if (action === 'new-character') { stopPlayback(); void openAssetShelf(); return; }
    if (action === 'close-asset-shelf') { assetShelf = { open: false, loading: false }; rerenderShelf(); return; }
    if (action === 'open-character-tile-picker') { if (currentState) { sourceTilePickerOpen = true; rerender(currentState.value); } return; }
    if (action === 'close-character-tile-picker') { sourceTilePickerOpen = false; if (currentState) rerender(currentState.value); return; }
    if (action === 'select-asset') {
      const assetId = actionElement?.dataset.assetId;
      if (assetId) { creationForm = { ...creationForm, assetId }; assetShelf = { ...assetShelf, selectedAssetId: assetId, notice: undefined }; rerenderShelf(); }
      return;
    }
    if (!currentState) return;
    if (action !== 'play') stopPlayback();
    switch (action) {
      case 'save': void save(); break;
      case 'undo': currentState.undo(); break;
      case 'redo': currentState.redo(); break;
      case 'duplicate': await duplicate(); break;
      case 'add-clip': { const id = await promptClipId('Create animation clip', 'jump'); if (id) currentState.addClip(id); break; }
      case 'rename-clip': { const id = await promptClipId('Rename current animation', currentState.value.selectedClipId); if (id) currentState.renameClip(id); break; }
      case 'duplicate-clip': { const id = await promptClipId('Duplicate current animation', `${currentState.value.selectedClipId}-copy`); if (id) currentState.duplicateClip(id); break; }
      case 'remove-clip': if (await confirmModal({ title: 'Remove animation?', message: `Remove '${currentState.value.selectedClipId}' and its package-local hitbox/event track? This cannot be undone after saving.`, confirmLabel: 'REMOVE ANIMATION', danger: true })) currentState.removeClip(); break;
      case 'append-frame': { const frames = currentState.value.selectedSourceFrames.length > 0 ? currentState.value.selectedSourceFrames : [currentState.value.selectedSourceFrame]; sourceTilePickerOpen = false; currentState.appendSelectedFrames(frames); break; }
      case 'insert-frame': { const frames = currentState.value.selectedSourceFrames.length > 0 ? currentState.value.selectedSourceFrames : [currentState.value.selectedSourceFrame]; sourceTilePickerOpen = false; currentState.insertSelectedFrames(frames); break; }
      case 'add-span': {
        const hitboxIds = Object.keys(currentState.value.character.hitboxes);
        if (hitboxIds.length === 0) {
          await alertModal('No hitbox available', 'Add a named hitbox in the Inspector before creating a hitbox span.');
          break;
        }
        const clip = currentState.value.visualSet.clips[currentState.value.selectedClipId];
        const normalizedClip = clip && clip.frames.length > 0 ? normalizeAnimationClip(clip) : undefined;
        const from = normalizedClip?.keyframeTimes[currentState.value.selectedTimelineIndex] ?? currentState.value.selectedTimelineIndex;
        const hitboxValues = hitboxIds.length === 1 ? undefined : await promptModal({ title: 'Choose hitbox', message: 'Select the named hitbox that should be active during this range.', fields: [{ id: 'hitboxId', label: `Hitbox ID (${hitboxIds.join(', ')})`, value: hitboxIds[0] }], confirmLabel: 'NEXT' });
        const hitboxId = hitboxIds.length === 1 ? hitboxIds[0] : hitboxValues?.hitboxId?.trim();
        if (!hitboxId || !hitboxIds.includes(hitboxId)) break;
        const lastFrame = Math.max(from, normalizedClip ? timelineFrameCount(normalizedClip) - 1 : (clip?.frames.length ?? 1) - 1);
        const throughValues = await promptModal({ title: 'Set hitbox span', message: `This hitbox will stay active from frame ${from} through the end frame, inclusive.`, fields: [{ id: 'through', label: `End frame (${from}-${lastFrame})`, value: String(from), inputType: 'number' }], confirmLabel: 'ADD SPAN' });
        if (!throughValues) break;
        const throughValue = integerValue(throughValues.through, from);
        currentState.addSpan({ hitboxId, from, through: Math.max(from, Math.min(throughValue, lastFrame)) });
        break;
      }
      case 'add-event': {
        const eventValues = await promptModal({ title: 'Add animation event', message: 'Adds a one-frame runtime marker at the selected timeline position. It does not change the artwork by itself.', fields: [{ id: 'eventId', label: 'Event ID', value: 'attack-impact', placeholder: 'attack-impact' }], confirmLabel: 'ADD EVENT' });
        const eventId = eventValues?.eventId?.trim().toLowerCase();
        const clip = currentState.value.visualSet.clips[currentState.value.selectedClipId];
        const normalizedClip = clip && clip.frames.length > 0 ? normalizeAnimationClip(clip) : undefined;
        if (eventId) currentState.addEvent({ at: normalizedClip?.keyframeTimes[currentState.value.selectedTimelineIndex] ?? currentState.value.selectedTimelineIndex, eventId });
        break;
      }
      case 'remove-frame': currentState.removeSelectedFrame(); break;
      case 'previous-frame': currentState.selectTimelineIndex(currentState.value.selectedTimelineIndex - 1); break;
      case 'next-frame': currentState.selectTimelineIndex(currentState.value.selectedTimelineIndex + 1); break;
      case 'add-hitbox': { const id = await promptClipId('Create named hitbox', 'attack', 'Hitbox ID', 'Choose a stable lowercase hitbox ID. You can use this name when authoring hitbox spans on the timeline.'); if (id) currentState.addHitbox(id); break; }
      case 'reset-animation-visual': currentState.resetAnimationVisual(); break;
      case 'reset-frame-visual': currentState.resetFrameVisual(currentState.value.selectedSourceFrame); break;
      case 'play': {
        if (playTimer !== undefined) {
          stopPlayback();
          rerender(currentState.value);
          break;
        }
        const clip = currentState.value.visualSet.clips[currentState.value.selectedClipId];
        if (!clip) break;
        currentState.selectTimelineIndex(0);
        let playbackStep = 0;
        const normalizedClip = normalizeAnimationClip(clip);
        const cycleLength = animationCycleFrameCount(normalizedClip);
        playTimer = window.setInterval(() => {
          if (!currentState) {
            stopPlayback();
            return;
          }
          playbackStep += 1;
          if (playbackStep >= timelineFrameCount(normalizedClip) && !clip.loop) {
            stopPlayback();
            playbackStep = Math.max(timelineFrameCount(normalizedClip) - 1, 0);
          } else if (clip.loop) {
            playbackStep %= cycleLength;
          }
          const timelineFrame = animationFrameIndexAtStep(normalizedClip, playbackStep);
          const index = keyframeIndexAtTimelineFrame(normalizedClip, timelineFrame);
          playbackTick = true;
          try { currentState.selectTimelineIndex(index); } finally { playbackTick = false; }
        }, 1000 / Math.max(clip.framesPerSecond, 0.1));
        rerender(currentState.value);
        break;
      }
      case 'create-package': void createPackage(); break;
      case 'upload-create': container.querySelector<HTMLInputElement>('[data-upload-input]')?.click(); break;
      default: break;
    }
  };
  let draggedTimelineIndex: number | undefined;
  let nativeDragActive = false;
  let pointerDragSource: number | undefined;
  let pointerDragStart: { readonly x: number; readonly y: number } | undefined;
  let pointerDragId: number | undefined;
  let pointerDragActive = false;
  const clearTimelineDrag = (): void => {
    draggedTimelineIndex = undefined;
    nativeDragActive = false;
    pointerDragSource = undefined;
    pointerDragStart = undefined;
    pointerDragId = undefined;
    pointerDragActive = false;
    container.querySelectorAll<HTMLElement>('.timeline-frame.is-dragging, .timeline-frame.is-drop-target').forEach((item) => item.classList.remove('is-dragging', 'is-drop-target'));
  };
  const setTimelineDropTarget = (target: HTMLElement): void => {
    container.querySelectorAll<HTMLElement>('.timeline-frame.is-drop-target').forEach((item) => item.classList.remove('is-drop-target'));
    target.classList.add('is-drop-target');
  };
  const reorderDraggedFrame = (from: number, to: number): void => {
    if (!currentState || !Number.isInteger(from) || !Number.isInteger(to)) return;
    currentState.reorderFrameFrom(from, to);
  };
  const onDragStart = (event: DragEvent): void => {
    const target = event.target as HTMLElement;
    const timelineButton = target.closest<HTMLElement>('[data-timeline-index]');
    if (!timelineButton?.dataset.timelineIndex) return;
    nativeDragActive = true;
    draggedTimelineIndex = Number(timelineButton.dataset.timelineIndex);
    event.dataTransfer?.setData('text/plain', String(draggedTimelineIndex));
    if (event.dataTransfer) event.dataTransfer.effectAllowed = 'move';
    timelineButton.classList.add('is-dragging');
    stopPlayback();
  };
  const onDragOver = (event: DragEvent): void => {
    if (draggedTimelineIndex === undefined) return;
    const target = (event.target as HTMLElement).closest<HTMLElement>('[data-timeline-index]');
    if (!target?.dataset.timelineIndex) return;
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
    setTimelineDropTarget(target);
  };
  const onDrop = (event: DragEvent): void => {
    const target = (event.target as HTMLElement).closest<HTMLElement>('[data-timeline-index]');
    if (!target?.dataset.timelineIndex || !currentState) return;
    const from = draggedTimelineIndex ?? Number(event.dataTransfer?.getData('text/plain'));
    const to = Number(target.dataset.timelineIndex);
    if (Number.isInteger(from) && Number.isInteger(to)) {
      event.preventDefault();
      reorderDraggedFrame(from, to);
    }
    clearTimelineDrag();
  };
  const onDragEnd = (): void => { clearTimelineDrag(); };
  const onPointerDown = (event: PointerEvent): void => {
    if (event.button !== 0) return;
    const target = (event.target as HTMLElement).closest<HTMLElement>('[data-timeline-index]');
    if (!target?.dataset.timelineIndex) return;
    pointerDragSource = Number(target.dataset.timelineIndex);
    pointerDragStart = { x: event.clientX, y: event.clientY };
    pointerDragId = event.pointerId;
    pointerDragActive = false;
  };
  const onPointerMove = (event: PointerEvent): void => {
    if (nativeDragActive || pointerDragSource === undefined || pointerDragId !== event.pointerId || !pointerDragStart) return;
    if (!pointerDragActive) {
      const moved = Math.abs(event.clientX - pointerDragStart.x) + Math.abs(event.clientY - pointerDragStart.y);
      if (moved < 8) return;
      pointerDragActive = true;
      draggedTimelineIndex = pointerDragSource;
      stopPlayback();
      container.querySelector<HTMLElement>(`.timeline-frame[data-timeline-index="${pointerDragSource}"]`)?.classList.add('is-dragging');
    }
    const target = document.elementFromPoint(event.clientX, event.clientY)?.closest<HTMLElement>('[data-timeline-index]');
    if (!target || !container.contains(target)) return;
    event.preventDefault();
    setTimelineDropTarget(target);
  };
  const onPointerUp = (event: PointerEvent): void => {
    if (nativeDragActive || pointerDragSource === undefined || pointerDragId !== event.pointerId) return;
    if (pointerDragActive) {
      const target = document.elementFromPoint(event.clientX, event.clientY)?.closest<HTMLElement>('[data-timeline-index]');
      const to = target?.dataset.timelineIndex;
      if (to !== undefined) reorderDraggedFrame(pointerDragSource, Number(to));
    }
    clearTimelineDrag();
  };
  const onPointerCancel = (): void => { if (!nativeDragActive) clearTimelineDrag(); };
  const onSubmit = (event: Event): void => {
    const form = event.target as HTMLFormElement;
    if (!form.matches('[data-studio-modal-form]') || !activeModal) return;
    event.preventDefault();
    if (activeModal.request.kind === 'alert') {
      settleModal(undefined);
      return;
    }
    if (activeModal.request.kind === 'confirm') {
      settleModal(true);
      return;
    }
    const values: Record<string, string> = {};
    form.querySelectorAll<HTMLInputElement>('[data-modal-field]').forEach((input) => { if (input.dataset.modalField) values[input.dataset.modalField] = input.value; });
    settleModal(values);
  };
  const onKeydown = (event: KeyboardEvent): void => {
    if (activeModal && event.key === 'Escape') {
      event.preventDefault();
      settleModal(undefined);
    }
  };
  const onClick = (event: Event): void => {
    const target = event.target as HTMLElement;
    const modalAction = target.closest<HTMLElement>('[data-modal-action]')?.dataset.modalAction;
    if (modalAction === 'cancel') { settleModal(undefined); return; }
    const modalBackdrop = target.closest<HTMLElement>('[data-studio-modal-backdrop]');
    if (modalBackdrop && target === modalBackdrop) { settleModal(undefined); return; }
    const tilePickerBackdrop = target.closest<HTMLElement>('[data-character-tile-picker-backdrop]');
    if (tilePickerBackdrop && target === tilePickerBackdrop) { sourceTilePickerOpen = false; if (currentState) rerender(currentState.value); return; }
    const characterButton = target.closest<HTMLElement>('[data-character-id]');
    if (characterButton?.dataset.characterId) { void choosePackage(characterButton.dataset.characterId); return; }
    const clipButton = target.closest<HTMLElement>('[data-clip-id]');
    if (clipButton?.dataset.clipId) { stopPlayback(); currentState?.selectClip(clipButton.dataset.clipId); return; }
    const timelineButton = target.closest<HTMLElement>('[data-timeline-index]');
    if (timelineButton?.dataset.timelineIndex) { stopPlayback(); currentState?.selectTimelineIndex(Number(timelineButton.dataset.timelineIndex)); return; }
    const frameButton = target.closest<HTMLElement>('[data-source-frame]');
    if (frameButton?.dataset.sourceFrame) { stopPlayback(); currentState?.selectSourceFrame(Number(frameButton.dataset.sourceFrame)); return; }
    const actionElement = target.closest<HTMLElement>('[data-action]');
    if (actionElement?.classList.contains('studio-asset-shelf-backdrop') && target.closest('[data-asset-shelf-panel]')) return;
    const action = actionElement?.dataset.action;
    if (action) void handleAction(action, actionElement);
    const removeHitbox = target.closest<HTMLElement>('[data-remove-hitbox]')?.dataset.removeHitbox;
    if (removeHitbox && currentState) currentState.removeHitbox(removeHitbox);
  };
  const onChange = (event: Event): void => {
    const target = event.target as HTMLInputElement;
    if (target.matches('[data-upload-input]')) {
      const file = target.files?.[0];
      target.value = '';
      if (file) void registerUpload(file);
      return;
    }
    if (target.matches('[data-creation-field]')) {
      const field = target.dataset.creationField;
      if (field === 'kind' && (target.value === 'player' || target.value === 'enemy')) {
        creationForm = { ...creationForm, kind: target.value, template: target.value === 'player' ? 'player' : (creationForm.template === 'player' ? 'melee-enemy' : creationForm.template) };
      } else if (field === 'template' && (target.value === 'player' || target.value === 'melee-enemy' || target.value === 'ranged-enemy')) {
        creationForm = { ...creationForm, template: target.value };
      } else if (field === 'characterId' || field === 'displayName') {
        creationForm = { ...creationForm, [field]: target.value };
      }
      rerenderShelf();
      return;
    }
    if (!currentState) return;
    if (target.matches('[data-clip-fps], [data-clip-duration], [data-clip-loop], [data-clip-loop-mode]')) {
      stopPlayback();
      const loopMode: VisualLoopMode = container.querySelector<HTMLSelectElement>('[data-clip-loop-mode]')?.value === 'ping-pong' ? 'ping-pong' : 'wrap';
      const fps = Math.min(240, Math.max(1, integerValue(container.querySelector<HTMLInputElement>('[data-clip-fps]')?.value, 8)));
      const duration = Math.min(60, Math.max(0.01, Number(container.querySelector<HTMLInputElement>('[data-clip-duration]')?.value ?? 0)));
      const loop = container.querySelector<HTMLInputElement>('[data-clip-loop]')?.checked ?? true;
      currentState.updatePlayback(fps, loop, loopMode, Number.isFinite(duration) ? duration : undefined);
      return;
    }
    const booleanPath = target.dataset.booleanPath;
    if (booleanPath) {
      if (booleanPath === 'enemy.ai.isRanged') {
        const projectileAssetId = Object.entries(ASSET_MANIFEST.assets).find(([, entry]) => manifestTags(entry).includes('projectile'))?.[0] ?? '';
        currentState.setEnemyRanged(target.checked, projectileAssetId);
      } else if (booleanPath === 'enemy.ai.isLeaper') currentState.setEnemyLeaper(target.checked);
      else currentState.updateGameplay(booleanPath.split('.'), target.checked);
      return;
    }
    const selectPath = target.dataset.selectPath;
    if (selectPath) {
      if (selectPath === 'enemy.projectile.assetId') currentState.updateEnemyProjectileAsset(target.value);
      else currentState.updateGameplay(selectPath.split('.'), target.value);
      return;
    }
    const collisionShapePath = target.dataset.collisionShapePath;
    if (collisionShapePath) {
      const shape = target.value === 'circle' || target.value === 'ellipse' ? target.value : 'rectangle';
      const parts = collisionShapePath.split('.');
      if (parts[0] === 'body') currentState.updateBody({ shape });
      else if (parts[0] === 'hitbox' && parts[1]) currentState.updateHitbox(parts[1], { shape });
      return;
    }
    const path = target.dataset.numberPath;
    if (!path) return;
    const parts = path.split('.');
    const value = integerValue(target.value);
    if (parts[0] === 'body') currentState.updateBody({ [parts[1] ?? 'width']: value });
    else if (parts[0] === 'attributes') currentState.updateAttributes({ [parts[1] ?? 'strength']: value });
    else if (parts[0] === 'visual') {
      const axis = parts[3] === '1' ? 1 : 0;
      if (parts[1] === 'defaults') {
        const property = parts[2] === 'origin' || parts[2] === 'scale' || parts[2] === 'sourceOffset' ? parts[2] : 'scale';
        const current = currentState.value.visualSet.defaults[property];
        const next = [...current] as [number, number];
        next[axis] = value;
        if (property === 'origin') currentState.updateDefaults({ origin: next });
        else if (property === 'scale') currentState.updateDefaults({ scale: next });
        else currentState.updateDefaults({ sourceOffset: next });
      } else if (parts[1] === 'animation') {
        const clip = currentState.value.visualSet.clips[currentState.value.selectedClipId];
        const currentOffset = clip?.sourceOffset ?? currentState.value.visualSet.defaults.sourceOffset;
        const next = [...currentOffset] as [number, number];
        next[axis] = value;
        currentState.updateAnimationVisual(next);
      } else {
        const frame = currentState.value.selectedSourceFrame;
        const currentFrame = currentState.value.visualSet.frameVisuals?.[String(frame)];
        const currentOffset = currentFrame?.sourceOffset ?? currentState.value.visualSet.defaults.sourceOffset;
        const next = [...currentOffset] as [number, number];
        next[axis] = value;
        currentState.updateFrameVisual(frame, { sourceOffset: next });
      }
    } else if (parts[0] === 'hitbox') currentState.updateHitbox(parts[1] ?? '', { [parts[2] ?? 'width']: value });
    else currentState.updateGameplay(parts, value as JsonValue);
  };
  const onInput = (event: Event): void => { const target = event.target as HTMLInputElement; if (target.matches('[data-library-search]')) { const queryText = target.value.toLowerCase(); container.querySelectorAll<HTMLElement>('[data-character-id]').forEach((item) => { item.hidden = !(item.dataset.characterName ?? '').toLowerCase().includes(queryText); }); } };
  container.addEventListener('click', onClick);
  container.addEventListener('dragstart', onDragStart);
  container.addEventListener('dragover', onDragOver);
  container.addEventListener('drop', onDrop);
  container.addEventListener('dragend', onDragEnd);
  container.addEventListener('pointerdown', onPointerDown);
  container.addEventListener('pointermove', onPointerMove);
  container.addEventListener('pointerup', onPointerUp);
  container.addEventListener('pointercancel', onPointerCancel);
  container.addEventListener('change', onChange);
  container.addEventListener('submit', onSubmit);
  container.addEventListener('input', onInput);
  container.addEventListener('keydown', onKeydown);
  renderLoading('Loading Character Studio…');
  void choosePackage(currentId);
  return () => { activeModal?.resolve(undefined); activeModal = undefined; disposed = true; stopPlayback(); clearTimelineDrag(); unsubscribe?.(); container.removeEventListener('click', onClick); container.removeEventListener('dragstart', onDragStart); container.removeEventListener('dragover', onDragOver); container.removeEventListener('drop', onDrop); container.removeEventListener('dragend', onDragEnd); container.removeEventListener('pointerdown', onPointerDown); container.removeEventListener('pointermove', onPointerMove); container.removeEventListener('pointerup', onPointerUp); container.removeEventListener('pointercancel', onPointerCancel); container.removeEventListener('change', onChange); container.removeEventListener('submit', onSubmit); container.removeEventListener('input', onInput); container.removeEventListener('keydown', onKeydown); container.classList.remove('is-character-studio-host'); };
}
