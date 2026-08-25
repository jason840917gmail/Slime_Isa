import {
  getObjectArchetype,
  getObjectVisualChoices,
  isObjectArchetypeId,
  type ColliderBounds,
  type DepthBounds,
} from '../content/objects/ObjectCatalog';
import { getKnownItemIds } from '../content/items/ItemCatalog';
import { getAnimationPackages } from '../content/animations/AnimationCatalog';
import {
  type ObjectTemplateEditorState,
  type ObjectTemplateViewState,
} from './ObjectTemplateEditorState';
import { EDITOR_GEOMETRY_STYLES, type EditorGeometryKey } from './EditorGeometryStyles';
import type { EditableObjectInstance, MapEditorState } from './MapEditorState';
import type { CollisionShape } from '../shared/collisionShapes';
import {
  type GameplayAttributeEditorState,
  type GameplayAttributeViewState,
  type ResourceGameplayDraft,
} from './GameplayAttributeEditorState';

export interface InspectorPreviewUrls {
  readonly objects: Readonly<Record<string, string>>;
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>'"]/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    "'": '&#39;',
    '"': '&quot;',
  })[character] ?? character);
}

function titleFromId(id: string): string {
  return id.split(/[.-]/).map((part) => `${part[0]?.toUpperCase() ?? ''}${part.slice(1)}`).join(' ');
}

function renderError(error: string | undefined): string {
  return `<small class="editor-inspector-error"${error ? '' : ' aria-hidden="true"'}>${escapeHtml(error ?? '')}</small>`;
}

function renderNumberField(
  label: string,
  field: string,
  value: number,
  error: string | undefined,
  testId: string,
): string {
  return `<label class="editor-inspector-field">
    <span>${label}<small>px</small></span>
    <input type="number" step="1" data-template-field="${field}" data-testid="${testId}" value="${value}" />
    ${renderError(error)}
  </label>`;
}

function renderScaleField(value: number, error: string | undefined): string {
  return `<label class="editor-inspector-field">
    <span>Scale<small>multiplier</small></span>
    <input type="number" min="0.05" max="8" step="0.05" data-template-field="scale" data-testid="template-scale" value="${value}" />
    ${renderError(error)}
  </label>`;
}

function renderShapeField(shape: CollisionShape | undefined): string {
  const selected = shape ?? 'rectangle';
  return `<label class="editor-inspector-field"><span>Shape<small>collision primitive</small></span><select data-template-field="shape"><option value="rectangle" ${selected === 'rectangle' ? 'selected' : ''}>Rectangle</option><option value="circle" ${selected === 'circle' ? 'selected' : ''}>Circle</option><option value="ellipse" ${selected === 'ellipse' ? 'selected' : ''}>Ellipse</option></select></label>`;
}

type AnimationPickerField = 'idleAnimationId' | 'onHitAnimationId';

function renderAnimationField(
  label: string,
  field: AnimationPickerField,
  value: string | undefined,
  error: string | undefined,
): string {
  const selected = value ? getAnimationPackages().find((entry) => entry.animationId === value) : undefined;
  const commandSuffix = field === 'idleAnimationId' ? 'idle' : 'on-hit';
  return `<div class="editor-inspector-field editor-inspector-field-wide editor-animation-reference"><span>${label}<small>shared animation package</small></span><div class="editor-animation-reference-value"><div>${selected ? `<strong>${escapeHtml(selected.displayName)}</strong><small>${escapeHtml(selected.animationId)}</small>` : '<strong>None</strong><small>Static object visual</small>'}</div><button type="button" class="editor-inspector-secondary" data-command="browse-animation-${commandSuffix}">Browse</button><button type="button" class="editor-inspector-secondary" data-command="clear-animation-${commandSuffix}" ${value ? '' : 'disabled'}>Clear</button></div>${renderError(error)}</div>`;
}

function renderAnimationPreview(animationId: string | undefined): string {
  const entry = animationId ? getAnimationPackages().find((candidate) => candidate.animationId === animationId) : undefined;
  if (!entry) return '<div class="editor-animation-picker-preview is-empty"><strong>No animation selected</strong><p>The object will use its static visual for this slot.</p></div>';
  const frameCount = Math.max(1, Math.round(entry.animation.durationSeconds * entry.animation.framesPerSecond));
  return `<div class="editor-animation-picker-preview"><span class="editor-inspector-kicker">Package preview</span><h4>${escapeHtml(entry.displayName)}</h4><code>${escapeHtml(entry.animationId)}</code><p>${escapeHtml(entry.description)}</p><div class="editor-animation-preview-meta"><span>${entry.animation.loop ? 'Looping' : 'One shot'}</span><span>${entry.animation.framesPerSecond} FPS</span><span>${frameCount} frames</span></div><div class="editor-animation-preview-timeline">${entry.animation.layers.map((layer) => `<div><strong>${escapeHtml(layer.displayName)}</strong><span>${layer.blocks.map((block) => `<i style="--from:${block.from};--span:${block.through - block.from + 1};--frames:${frameCount}" title="Frame ${block.sourceFrame}"></i>`).join('')}</span></div>`).join('')}</div></div>`;
}

function renderAnimationPicker(ui: InspectorUiState): string {
  if (!ui.animationPickerField) return '';
  const loop = ui.animationPickerField === 'idleAnimationId';
  const search = ui.animationPickerSearch.trim().toLowerCase();
  const packages = getAnimationPackages().filter((entry) => entry.animation.loop === loop && (
    !search || [entry.displayName, entry.animationId, entry.description].some((value) => value.toLowerCase().includes(search))
  ));
  const grouped = new Map<string, typeof packages>();
  for (const entry of packages) {
    const folder = entry.animationId.split('.').slice(0, -1).join(' / ') || 'root';
    grouped.set(folder, [...(grouped.get(folder) ?? []), entry]);
  }
  return `<dialog class="editor-template-dialog editor-animation-picker" data-animation-picker-dialog><form data-animation-picker-form><header><span class="editor-inspector-kicker">Shared animation library</span><h3>${loop ? 'Choose idle animation' : 'Choose on-hit animation'}</h3><p>${loop ? 'Only looping packages are shown.' : 'Only one-shot packages are shown.'}</p></header><label class="editor-inspector-field"><span>Search<small>name, ID, or description</small></span><input type="search" value="${escapeHtml(ui.animationPickerSearch)}" data-animation-picker-search autofocus /></label><div class="editor-animation-picker-layout"><div class="editor-animation-picker-tree"><button type="button" class="editor-animation-picker-item${ui.animationPickerSelectedId ? '' : ' is-selected'}" data-animation-picker-id=""><strong>None</strong><small>Use the static visual</small></button>${[...grouped.entries()].map(([folder, entries]) => `<section><h4>${escapeHtml(folder)}</h4>${entries.map((entry) => `<button type="button" class="editor-animation-picker-item${entry.animationId === ui.animationPickerSelectedId ? ' is-selected' : ''}" data-animation-picker-id="${escapeHtml(entry.animationId)}"><strong>${escapeHtml(entry.displayName)}</strong><small>${escapeHtml(entry.animationId)}</small></button>`).join('')}</section>`).join('')}${packages.length === 0 ? '<p class="editor-inspector-help">No compatible packages match this search.</p>' : ''}</div>${renderAnimationPreview(ui.animationPickerSelectedId)}</div><footer><button type="button" class="editor-inspector-secondary" data-command="cancel-animation-picker">Cancel</button><button type="submit" class="editor-inspector-save">Use selection</button></footer></form></dialog>`;
}

function renderIds(state: ObjectTemplateViewState, previewUrl: string): string {
  const selected = state.selected;
  if (!selected) return '';
  const dimensions = state.frameDimensions;
  const displayName = state.draft?.displayName ?? selected.displayName;
  const siblings = getObjectVisualChoices().filter((choice) => (
    choice.assetId === selected.assetId && choice.frame === selected.frame
  ));
  const archetype = selected.objectId;
  return `<div class="editor-inspector-identity">
    <div class="editor-inspector-art">
      <img src="${escapeHtml(previewUrl)}" alt="" />
    </div>
    <div class="editor-inspector-name">
      <span class="editor-inspector-kicker">Reusable template</span>
      <strong>${escapeHtml(displayName === selected.visualId ? titleFromId(selected.visualId) : displayName)}</strong>
      <small>${siblings.length} artwork sibling${siblings.length === 1 ? '' : 's'} · ${dimensions ? `${dimensions.width} × ${dimensions.height}px` : 'procedural frame'}</small>
    </div>
    <dl class="editor-inspector-meta">
      <div><dt>Object ID</dt><dd title="${escapeHtml(archetype)}">${escapeHtml(archetype)}</dd></div>
      <div><dt>Visual ID</dt><dd title="${escapeHtml(selected.visualId)}">${escapeHtml(selected.visualId)}</dd></div>
      <div><dt>Asset / frame</dt><dd title="${escapeHtml(`${selected.assetId} / ${selected.frame}`)}">${escapeHtml(selected.assetId)} / ${selected.frame}</dd></div>
      <div><dt>Physics</dt><dd>${selected.physics ? 'Static' : 'None'}</dd></div>
    </dl>
    <div class="editor-inspector-tags">${selected.tags.map((tag) => `<span>${escapeHtml(tag)}</span>`).join('')}</div>
  </div>`;
}

interface InspectorUiState {
  readonly mapId: string;
  readonly mapDirty: boolean;
  readonly saveAsOpen: boolean;
  readonly saveAsVisualId: string;
  readonly saveAsDisplayName: string;
  readonly saveAsError: string;
  readonly animationPickerField?: AnimationPickerField;
  readonly animationPickerSearch: string;
  readonly animationPickerSelectedId?: string;
  readonly activeTab: 'visuals' | 'gameplay';
}

function renderGameplayAttributes(state: GameplayAttributeViewState, instance?: EditableObjectInstance): string {
  const draft = state.draft;
  if (!draft) {
    return '<div class="editor-inspector-empty editor-inspector-empty-compact"><strong>No gameplay attributes</strong><p>Select a resource node or collectible to edit its gameplay data.</p></div>';
  }
  const error = (field: string): string => renderError(state.errors[field]);
  const collectiblePayload = (objectId: string) => isObjectArchetypeId(objectId)
    ? getObjectArchetype(objectId).collectible
    : undefined;
  if (draft.kind === 'collectible') {
    const overrideQuantity = typeof instance?.initialState?.quantity === 'number' ? instance.initialState.quantity : undefined;
    return `<form class="editor-gameplay-form" data-gameplay-form>
      <section class="editor-inspector-section"><div class="editor-inspector-section-title"><span>01</span><h3>Collectible defaults</h3></div>
        <p class="editor-inspector-help">Walk-over collectibles add this material to the player's inventory. Wood and stone are authored here, not as pickup resources.</p>
        <label class="editor-inspector-field editor-inspector-field-wide"><span>Material item</span><select data-gameplay-field="itemId">${getKnownItemIds().map((itemId) => `<option value="${escapeHtml(itemId)}" ${itemId === draft.itemId ? 'selected' : ''}>${escapeHtml(titleFromId(itemId))} · ${escapeHtml(itemId)}</option>`).join('')}</select>${error('itemId')}</label>
        <label class="editor-inspector-field"><span>Material quantity<small>per collectible</small></span><input type="number" min="1" step="1" data-gameplay-field="quantity" value="${draft.quantity}" />${error('quantity')}</label>
      </section>
      ${instance ? `<section class="editor-inspector-section"><div class="editor-inspector-section-title"><span>02</span><h3>Map instance override</h3></div><p class="editor-inspector-help">Blank means the shared value is inherited. Material identity stays owned by the shared collectible.</p><div class="editor-instance-override"><label class="editor-inspector-field"><span>Starting quantity<small>default ${draft.quantity}</small></span><input type="number" min="1" step="1" data-instance-field="quantity" value="${overrideQuantity ?? ''}" placeholder="${draft.quantity}" /></label><button type="button" class="editor-inspector-secondary" data-command="reset-instance-field" data-instance-reset-field="quantity" ${overrideQuantity === undefined ? 'disabled' : ''}>Use default</button></div><button type="button" class="editor-inspector-secondary" data-command="reset-instance-overrides">Use all shared defaults</button></section>` : ''}
      <section class="editor-inspector-section editor-inspector-actions"><div class="editor-inspector-action-row"><button type="button" class="editor-inspector-secondary" data-command="reset-gameplay" ${state.dirty ? '' : 'disabled'}>Reset changes</button><button type="submit" class="editor-inspector-save" ${state.dirty && !state.saving && Object.keys(state.errors).length === 0 ? '' : 'disabled'}>Save attributes</button></div><p class="editor-inspector-status" aria-live="polite">${escapeHtml(state.status)}</p></section>
    </form>`;
  }
  const resource = draft as ResourceGameplayDraft;
  const collectibleChoices = [...new Set(getObjectVisualChoices().filter((choice) => getObjectArchetype(choice.objectId).collectible).map((choice) => choice.objectId))];
  const dropVisuals = getObjectVisualChoices().filter((choice) => choice.objectId === resource.dropObjectId);
  const dropPayload = collectiblePayload(resource.dropObjectId);
  const sharedYield = resource.dropPieces * (dropPayload?.quantity ?? 0);
  const overrideHealth = typeof instance?.initialState?.health === 'number' ? instance.initialState.health : undefined;
  const overrideDropPieces = typeof instance?.initialState?.dropPieces === 'number' ? instance.initialState.dropPieces : undefined;
  const overrideDropObjectId = typeof instance?.initialState?.dropObjectId === 'string' ? instance.initialState.dropObjectId : undefined;
  const effectiveDropObjectId = overrideDropObjectId ?? resource.dropObjectId;
  const overrideDropVisualId = typeof instance?.initialState?.dropVisualId === 'string' ? instance.initialState.dropVisualId : undefined;
  const instanceDropVisuals = getObjectVisualChoices().filter((choice) => choice.objectId === effectiveDropObjectId);
  const resolvedDropVisualId = overrideDropVisualId ?? (overrideDropObjectId ? instanceDropVisuals[0]?.visualId : resource.dropVisualId);
  const effectivePieces = overrideDropPieces ?? resource.dropPieces;
  const effectivePayload = collectiblePayload(effectiveDropObjectId);
  const instanceYield = effectivePieces * (effectivePayload?.quantity ?? 0);
  return `<form class="editor-gameplay-form" data-gameplay-form>
    <section class="editor-inspector-section"><div class="editor-inspector-section-title"><span>01</span><h3>Resource defaults</h3></div>
      <p class="editor-inspector-help">Shared template values applied to every instance of this resource. Instance-specific changes belong in the optional section below.</p>
      <label class="editor-inspector-field"><span>Life points<small>damage to deplete</small></span><input type="number" min="1" step="1" data-gameplay-field="health" value="${resource.health}" />${error('health')}</label>
      <label class="editor-inspector-check"><input type="checkbox" data-gameplay-field="persistHealth" ${resource.persistHealth ? 'checked' : ''} /><span><strong>Persist damage between visits</strong><small>Save current life points while the node remains alive</small></span></label>
    </section>
    <section class="editor-inspector-section"><div class="editor-inspector-section-title"><span>02</span><h3>Death drops</h3></div>
      <label class="editor-inspector-field editor-inspector-field-wide"><span>Drop collectible<small>all collectible variants</small></span><select data-gameplay-field="dropObjectId">${collectibleChoices.map((objectId) => `<option value="${escapeHtml(objectId)}" ${objectId === resource.dropObjectId ? 'selected' : ''}>${escapeHtml(titleFromId(objectId))} · ${escapeHtml(collectiblePayload(objectId)?.itemId ?? 'unknown')} × ${collectiblePayload(objectId)?.quantity ?? 0}</option>`).join('')}</select>${error('dropObjectId')}</label>
      <div class="editor-inspector-grid"><label class="editor-inspector-field"><span>Drop visual</span><select data-gameplay-field="dropVisualId">${dropVisuals.map((choice) => `<option value="${escapeHtml(choice.visualId)}" ${choice.visualId === resource.dropVisualId ? 'selected' : ''}>${escapeHtml(choice.displayName)}</option>`).join('')}</select>${error('dropVisualId')}</label><label class="editor-inspector-field"><span>Number of collectibles<small>pieces on death</small></span><input type="number" min="1" step="1" data-gameplay-field="dropPieces" value="${resource.dropPieces}" />${error('dropPieces')}</label></div>
      <p class="editor-yield-preview"><strong>Total material yield</strong><span>${resource.dropPieces} pieces × ${dropPayload?.quantity ?? 0} ${escapeHtml(dropPayload?.itemId ?? 'items')} = ${sharedYield}</span></p>
    </section>
    <section class="editor-inspector-section"><div class="editor-inspector-section-title"><span>03</span><h3>Effects and requirements</h3></div>
      <label class="editor-inspector-field"><span>Hit effect ID</span><input type="text" data-gameplay-field="hitEffectId" value="${escapeHtml(resource.hitEffectId)}" placeholder="stone-impact" /></label>
      <label class="editor-inspector-field editor-inspector-field-wide"><span>Depletion message</span><input type="text" data-gameplay-field="depletionMessage" value="${escapeHtml(resource.depletionMessage)}" placeholder="Resource depleted" /></label>
      <div class="editor-inspector-grid"><label class="editor-inspector-field"><span>Required tool tag</span><input type="text" data-gameplay-field="harvestTargetTag" value="${escapeHtml(resource.harvestTargetTag)}" placeholder="axe" /></label><label class="editor-inspector-field"><span>Minimum tool tier</span><input type="number" min="1" step="1" data-gameplay-field="harvestMinimumTier" value="${resource.harvestMinimumTier}" />${error('harvestMinimumTier')}</label></div>
      <label class="editor-inspector-field editor-inspector-field-wide"><span>Tool failure message</span><input type="text" data-gameplay-field="harvestFailureMessage" value="${escapeHtml(resource.harvestFailureMessage)}" placeholder="Requires a better tool" />${error('harvestFailureMessage')}</label>
    </section>
    ${instance ? `<section class="editor-inspector-section"><div class="editor-inspector-section-title"><span>04</span><h3>Map instance override</h3></div><p class="editor-inspector-help">Blank fields inherit the shared resource. Each default can be restored independently.</p><div class="editor-instance-override"><label class="editor-inspector-field"><span>Starting life<small>default ${resource.health}</small></span><input type="number" min="0" max="${resource.health}" step="1" data-instance-field="health" value="${overrideHealth ?? ''}" placeholder="${resource.health}" /></label><button type="button" class="editor-inspector-secondary" data-command="reset-instance-field" data-instance-reset-field="health" ${overrideHealth === undefined ? 'disabled' : ''}>Use default</button></div><div class="editor-instance-override"><label class="editor-inspector-field editor-inspector-field-wide"><span>Drop collectible<small>default ${escapeHtml(resource.dropObjectId)}</small></span><select data-instance-field="dropObjectId"><option value="" ${overrideDropObjectId === undefined ? 'selected' : ''}>Use shared default</option>${collectibleChoices.map((objectId) => `<option value="${escapeHtml(objectId)}" ${objectId === overrideDropObjectId ? 'selected' : ''}>${escapeHtml(titleFromId(objectId))} · ${escapeHtml(collectiblePayload(objectId)?.itemId ?? 'unknown')} × ${collectiblePayload(objectId)?.quantity ?? 0}</option>`).join('')}</select></label><button type="button" class="editor-inspector-secondary" data-command="reset-instance-field" data-instance-reset-field="dropObjectId" ${overrideDropObjectId === undefined ? 'disabled' : ''}>Use default</button></div><div class="editor-instance-override"><label class="editor-inspector-field"><span>Drop visual<small>resolved ${escapeHtml(resolvedDropVisualId ?? '')}</small></span><select data-instance-field="dropVisualId"><option value="">Use resolved default</option>${instanceDropVisuals.map((choice) => `<option value="${escapeHtml(choice.visualId)}" ${choice.visualId === overrideDropVisualId ? 'selected' : ''}>${escapeHtml(choice.displayName)}</option>`).join('')}</select></label><button type="button" class="editor-inspector-secondary" data-command="reset-instance-field" data-instance-reset-field="dropVisualId" ${overrideDropVisualId === undefined ? 'disabled' : ''}>Use default</button></div><div class="editor-instance-override"><label class="editor-inspector-field"><span>Drop pieces<small>default ${resource.dropPieces}</small></span><input type="number" min="1" step="1" data-instance-field="dropPieces" value="${overrideDropPieces ?? ''}" placeholder="${resource.dropPieces}" /></label><button type="button" class="editor-inspector-secondary" data-command="reset-instance-field" data-instance-reset-field="dropPieces" ${overrideDropPieces === undefined ? 'disabled' : ''}>Use default</button></div><p class="editor-yield-preview"><strong>Resolved instance yield</strong><span>${effectivePieces} pieces × ${effectivePayload?.quantity ?? 0} ${escapeHtml(effectivePayload?.itemId ?? 'items')} = ${instanceYield}</span></p><button type="button" class="editor-inspector-secondary" data-command="reset-instance-overrides">Use all shared defaults</button></section>` : ''}
    <section class="editor-inspector-section editor-inspector-actions"><div class="editor-inspector-action-row"><button type="button" class="editor-inspector-secondary" data-command="reset-gameplay" ${state.dirty ? '' : 'disabled'}>Reset changes</button><button type="submit" class="editor-inspector-save" ${state.dirty && !state.saving && Object.keys(state.errors).length === 0 ? '' : 'disabled'}>Save attributes</button></div><p class="editor-inspector-status" aria-live="polite">${escapeHtml(state.status)}</p></section>
  </form>`;
}

function renderInspector(
  host: HTMLElement,
  state: ObjectTemplateViewState,
  gameplayState: GameplayAttributeViewState,
  instance: EditableObjectInstance | undefined,
  previews: InspectorPreviewUrls,
  ui: InspectorUiState,
): void {
  if (!state.selected || !state.draft) {
    host.innerHTML = `
      <header class="map-editor-inspector-header">
        <div><span class="editor-inspector-kicker">Instrument panel</span><h2>Template inspector</h2></div>
        <button type="button" class="editor-inspector-toggle" data-inspector-toggle aria-label="Close inspector">×</button>
      </header>
      <div class="editor-inspector-empty">
        <span class="editor-inspector-empty-mark">+</span>
        <strong>Select a template</strong>
        <p>Select an entry from Object Content to inspect its shared definition.</p>
      </div>`;
    return;
  }

  const { selected, draft, errors } = state;
  const imagePreview = previews.objects[selected.key] ?? '';
  const collider = draft.collider;
  const occlusion = draft.occlusionBounds;
  const depthBounds = draft.depthBounds;
  const frameGeometrySupported = Boolean(state.frameDimensions);
  host.innerHTML = `
    <header class="map-editor-inspector-header">
      <div><span class="editor-inspector-kicker">Instrument panel</span><h2>Template inspector</h2></div>
      <button type="button" class="editor-inspector-toggle" data-inspector-toggle aria-label="Close inspector">×</button>
    </header>
    <div class="editor-inspector-scroll">
      ${renderIds(state, imagePreview)}
      <div class="editor-inspector-warning">
        <span>Shared template</span>
        <p>Saved changes affect every existing and future map object using this visual.</p>
      </div>
      <div class="editor-inspector-tabs" role="tablist" aria-label="Object attributes">
        <button id="inspector-visuals-tab" type="button" role="tab" tabindex="${ui.activeTab === 'visuals' ? '0' : '-1'}" aria-selected="${ui.activeTab === 'visuals'}" aria-controls="inspector-visuals-panel" data-inspector-tab="visuals"><span>Visuals &amp; collisions</span>${state.dirty ? '<small>Unsaved</small>' : Object.keys(errors).length > 0 ? '<small>Error</small>' : ''}</button>
        <button id="inspector-gameplay-tab" type="button" role="tab" tabindex="${ui.activeTab === 'gameplay' ? '0' : '-1'}" aria-selected="${ui.activeTab === 'gameplay'}" aria-controls="inspector-gameplay-panel" data-inspector-tab="gameplay"><span>Gameplay attributes</span>${gameplayState.dirty ? '<small>Unsaved</small>' : Object.keys(gameplayState.errors).length > 0 ? '<small>Error</small>' : ''}</button>
      </div>
      <form id="inspector-visuals-panel" role="tabpanel" aria-labelledby="inspector-visuals-tab" class="editor-template-form" data-template-form ${ui.activeTab === 'visuals' ? '' : 'hidden'}>
        <section class="editor-inspector-section">
          <div class="editor-inspector-section-title"><span>01</span><h3>Template label</h3></div>
          <label class="editor-inspector-field editor-inspector-field-wide">
            <span>Display name</span>
            <input type="text" data-template-field="displayName" data-testid="template-display-name" value="${escapeHtml(draft.displayName)}" maxlength="80" />
            ${renderError(errors.displayName)}
          </label>
        </section>
        <section class="editor-inspector-section editor-geometry-section editor-geometry-frame">
          <div class="editor-inspector-section-title"><span>02</span><h3><span class="editor-geometry-swatch" aria-hidden="true"></span>Visual alignment</h3></div>
          <p class="editor-inspector-help">Scale the complete object uniformly, or move its art in source-frame pixels. The map anchor stays fixed and collision/depth/occlusion geometry follows the scale.</p>
          <div class="editor-inspector-grid">
            ${renderScaleField(draft.scale, errors.scale)}
            ${renderNumberField('Horizontal', 'visualOffsetX', draft.visualOffset.x, errors.visualOffsetX, 'template-offset-x')}
            ${renderNumberField('Vertical', 'visualOffsetY', draft.visualOffset.y, errors.visualOffsetY, 'template-offset-y')}
          </div>
          <div class="editor-inspector-inline-actions">
            <button type="button" class="editor-inspector-secondary" data-command="reset-scale">Reset scale to 1</button>
            <button type="button" class="editor-inspector-secondary" data-command="reset-offset">Reset offset to 0, 0</button>
          </div>
        </section>
        <section class="editor-inspector-section editor-geometry-section editor-geometry-collider">
          <div class="editor-inspector-section-title"><span>03</span><h3><span class="editor-geometry-swatch" aria-hidden="true"></span>Collider</h3></div>
          ${selected.physics === null
            ? '<p class="editor-inspector-no-physics">This object has no physics.</p>'
            : `<p class="editor-inspector-help">Source-frame pixels · ${state.frameDimensions ? `${state.frameDimensions.width} × ${state.frameDimensions.height}` : 'frame bounds unavailable'}</p>
              <div class="editor-inspector-grid">
                ${renderNumberField('Width', 'width', collider?.width ?? 1, errors.width, 'template-collider-width')}
                ${renderNumberField('Height', 'height', collider?.height ?? 1, errors.height, 'template-collider-height')}
                ${renderNumberField('Offset X', 'offsetX', collider?.offsetX ?? 0, errors.offsetX, 'template-collider-offset-x')}
                ${renderNumberField('Offset Y', 'offsetY', collider?.offsetY ?? 0, errors.offsetY, 'template-collider-offset-y')}
              </div>
              <div class="editor-inspector-grid">
                ${renderShapeField(collider?.shape)}
                ${collider?.shape === 'circle' ? renderNumberField('Radius', 'radius', collider.radius ?? Math.min(collider.width, collider.height) / 2, errors.radius, 'template-collider-radius') : collider?.shape === 'ellipse' ? `${renderNumberField('Radius X', 'radiusX', collider.radiusX ?? collider.width / 2, errors.radiusX, 'template-collider-radius-x')}${renderNumberField('Radius Y', 'radiusY', collider.radiusY ?? collider.height / 2, errors.radiusY, 'template-collider-radius-y')}` : ''}
              </div>
              ${renderError(errors.collider)}`}
        </section>
        <section class="editor-inspector-section">
          <div class="editor-inspector-section-title"><span>03</span><h3>Object animations</h3></div>
          <p class="editor-inspector-help">Choose reusable shared packages. Idle loops; on-hit plays once after accepted damage.</p>
          ${renderAnimationField('Idle animation', 'idleAnimationId', draft.idleAnimationId, errors.idleAnimationId)}
          ${renderAnimationField('On-hit animation', 'onHitAnimationId', draft.onHitAnimationId, errors.onHitAnimationId)}
        </section>
        <section class="editor-inspector-section editor-geometry-section editor-geometry-depth">
          <div class="editor-inspector-section-title"><span>04</span><h3><span class="editor-geometry-swatch" aria-hidden="true"></span>Depth bound</h3></div>
          <p class="editor-inspector-help">A separate source-frame rectangle for front/behind sorting. Its lower edge becomes the object's depth anchor; it does not change the tile size, art, or collider.</p>
          <label class="editor-inspector-check">
            <input type="checkbox" data-template-depth-toggle ${depthBounds ? 'checked' : ''} ${frameGeometrySupported ? '' : 'disabled'} />
            <span><strong>Use custom depth bound</strong><small>${frameGeometrySupported ? 'Edit the sorting region in source-frame pixels' : 'Requires an authoritative spritesheet frame'}</small></span>
          </label>
          ${depthBounds ? `<div class="editor-inspector-grid">
            ${renderNumberField('Width', 'depthWidth', depthBounds.width, errors.depthWidth, 'template-depth-width')}
            ${renderNumberField('Height', 'depthHeight', depthBounds.height, errors.depthHeight, 'template-depth-height')}
            ${renderNumberField('Offset X', 'depthOffsetX', depthBounds.offsetX, errors.depthOffsetX, 'template-depth-offset-x')}
            ${renderNumberField('Offset Y', 'depthOffsetY', depthBounds.offsetY, errors.depthOffsetY, 'template-depth-offset-y')}
          </div>${renderError(errors.depthBounds)}` : ''}
        </section>
        <section class="editor-inspector-section editor-geometry-section editor-geometry-occlusion">
          <div class="editor-inspector-section-title"><span>05</span><h3><span class="editor-geometry-swatch" aria-hidden="true"></span>Occlusion</h3></div>
          <p class="editor-inspector-help">The art's opaque pixels define the reveal shape. These bounds only crop the source-alpha scan for performance.</p>
          <label class="editor-inspector-check">
            <input type="checkbox" data-template-occlusion-toggle ${occlusion ? 'checked' : ''} ${frameGeometrySupported && !draft.idleAnimationId && !draft.onHitAnimationId ? '' : 'disabled'} />
            <span><strong>Occludes actors</strong><small>${frameGeometrySupported && !draft.idleAnimationId && !draft.onHitAnimationId ? 'Reveal only the hidden pixels of the player and engaged enemies' : 'Requires a static spritesheet frame'}</small></span>
          </label>
          ${occlusion ? `<div class="editor-inspector-grid">
            ${renderNumberField('Width', 'occlusionWidth', occlusion.width, errors.occlusionWidth, 'template-occlusion-width')}
            ${renderNumberField('Height', 'occlusionHeight', occlusion.height, errors.occlusionHeight, 'template-occlusion-height')}
            ${renderNumberField('Offset X', 'occlusionOffsetX', occlusion.offsetX, errors.occlusionOffsetX, 'template-occlusion-offset-x')}
            ${renderNumberField('Offset Y', 'occlusionOffsetY', occlusion.offsetY, errors.occlusionOffsetY, 'template-occlusion-offset-y')}
          </div>${renderError(errors.occlusionBounds)}` : ''}
        </section>
        <section class="editor-inspector-section">
          <div class="editor-inspector-section-title"><span>06</span><h3>Canvas boxes</h3></div>
          <p class="editor-inspector-help">Colors and line styles match the guides on the map. Toggle individual layers when boxes overlap.</p>
          <label class="editor-inspector-check">
            <input type="checkbox" data-overlay-scope="all-matching" ${state.showAllMatchingOverlays ? 'checked' : ''} />
            <span><strong>Show boxes for all matching instances</strong><small>Visual frame, depth, collision, and occlusion geometry</small></span>
          </label>
          <div class="editor-geometry-toggle-list">
            ${renderGeometryToggle('frame', state.showFrameOverlay, true, 'Visual frame', 'Yellow frame and anchor guide')}
            ${renderGeometryToggle('collider', state.showColliderOverlay, selected.physics !== null && Boolean(collider), 'Collider', 'Red solid geometry used for physics')}
            ${renderGeometryToggle('depth', state.showDepthOverlay, Boolean(depthBounds && frameGeometrySupported), 'Depth bound', 'Orange rectangle and sorting edge')}
            ${renderGeometryToggle('occlusion', state.showOcclusionOverlay, Boolean(occlusion && frameGeometrySupported && !draft.idleAnimationId && !draft.onHitAnimationId), 'Occlusion', 'Blue scan region and reveal shape')}
          </div>
        </section>
        <section class="editor-inspector-section editor-inspector-actions">
          <div class="editor-inspector-action-row">
            <button type="button" class="editor-inspector-secondary" data-command="reset-template" ${state.dirty ? '' : 'disabled'}>Reset changes</button>
            <button type="submit" class="editor-inspector-save" data-testid="save-template-button" ${state.dirty && !state.saving && Object.keys(errors).length === 0 ? '' : 'disabled'}>Save template</button>
            <button type="button" class="editor-inspector-secondary editor-inspector-save-as" data-command="save-as-template" ${!state.saving && !ui.mapDirty && !gameplayState.hasDirtyDrafts && Object.keys(errors).length === 0 ? '' : 'disabled'}>Save as new template</button>
          </div>
          ${ui.mapDirty || gameplayState.hasDirtyDrafts ? `<p class="editor-inspector-help">${ui.mapDirty ? 'Save the map' : 'Save or reset gameplay drafts'} before creating a new template.</p>` : ''}
          <p class="editor-inspector-status" aria-live="polite">${escapeHtml(state.status)}</p>
        </section>
      </form>
      <div id="inspector-gameplay-panel" role="tabpanel" aria-labelledby="inspector-gameplay-tab" ${ui.activeTab === 'gameplay' ? '' : 'hidden'}>${renderGameplayAttributes(gameplayState, instance)}</div>
      ${ui.saveAsOpen ? `
        <dialog class="editor-template-dialog" data-save-as-dialog>
          <form data-save-as-form>
            <header><span class="editor-inspector-kicker">Preserve original</span><h3>Save as new template</h3></header>
            <p>Creates an independent visual template under <code>${escapeHtml(selected.objectId)}</code> using the current offset and collider.</p>
            <label class="editor-inspector-field">
              <span>Visual ID</span>
              <input type="text" data-save-as-field="visualId" value="${escapeHtml(ui.saveAsVisualId)}" required />
            </label>
            <label class="editor-inspector-field">
              <span>Display name</span>
              <input type="text" data-save-as-field="displayName" value="${escapeHtml(ui.saveAsDisplayName)}" maxlength="80" required />
            </label>
            <small class="editor-inspector-error">${escapeHtml(ui.saveAsError)}</small>
            <footer>
              <button type="button" class="editor-inspector-secondary" data-command="cancel-save-as">Cancel</button>
              <button type="submit" class="editor-inspector-save" ${state.saving ? 'disabled' : ''}>Create template</button>
            </footer>
          </form>
        </dialog>` : ''}
      ${renderAnimationPicker(ui)}
    </div>`;
}

function renderGeometryToggle(
  key: EditorGeometryKey,
  checked: boolean,
  enabled: boolean,
  label: string,
  description: string,
): string {
  const style = EDITOR_GEOMETRY_STYLES[key];
  return `<label class="editor-inspector-check editor-geometry-toggle editor-geometry-${key}" style="--editor-geometry-color: ${style.css}">
    <input type="checkbox" data-overlay-geometry="${key}" ${checked ? 'checked' : ''} ${enabled ? '' : 'disabled'} />
    <span class="editor-geometry-swatch" aria-hidden="true"></span>
    <span><strong>${label}</strong><small>${description}</small></span>
  </label>`;
}

function updateCollider(
  templateEditor: ObjectTemplateEditorState,
  field: keyof ColliderBounds,
  value: number,
): void {
  const draft = templateEditor.value.draft;
  if (!draft?.collider) return;
  templateEditor.updateDraft({ collider: { ...draft.collider, [field]: value } });
}

function updateOcclusion(
  templateEditor: ObjectTemplateEditorState,
  field: 'width' | 'height' | 'offsetX' | 'offsetY',
  value: number,
): void {
  const draft = templateEditor.value.draft;
  if (!draft?.occlusionBounds) return;
  templateEditor.updateDraft({
    occlusionBounds: { ...draft.occlusionBounds, [field]: value },
  });
}

function updateDepthBounds(
  templateEditor: ObjectTemplateEditorState,
  field: keyof DepthBounds,
  value: number,
): void {
  const draft = templateEditor.value.draft;
  if (!draft?.depthBounds) return;
  templateEditor.updateDraft({
    depthBounds: { ...draft.depthBounds, [field]: value },
  });
}

export function mountMapEditorInspector(
  host: HTMLElement,
  templateEditor: ObjectTemplateEditorState,
  previews: InspectorPreviewUrls,
  mapEditor: MapEditorState,
  gameplayEditor: GameplayAttributeEditorState,
): () => void {
  let open = true;
  let saveAsOpen = false;
  let saveAsVisualId = '';
  let saveAsDisplayName = '';
  let saveAsError = '';
  let animationPickerField: AnimationPickerField | undefined;
  let animationPickerSearch = '';
  let animationPickerSelectedId: string | undefined;
  let activeTab: 'visuals' | 'gameplay' = 'visuals';
  const render = (): void => {
    const scrollTop = host.querySelector<HTMLElement>('.editor-inspector-scroll')?.scrollTop ?? 0;
    const activeInput = document.activeElement instanceof HTMLInputElement
      && host.contains(document.activeElement)
      ? document.activeElement
      : undefined;
    const activeField = activeInput?.dataset.templateField
      ? { kind: 'template' as const, id: activeInput.dataset.templateField }
      : activeInput?.dataset.saveAsField
        ? { kind: 'save-as' as const, id: activeInput.dataset.saveAsField }
      : activeInput?.dataset.gameplayField
          ? { kind: 'gameplay' as const, id: activeInput.dataset.gameplayField }
        : activeInput?.dataset.instanceField
          ? { kind: 'instance' as const, id: activeInput.dataset.instanceField }
        : undefined;
    let selection: { start: number; end: number } | undefined;
    if (activeInput && activeInput.type !== 'number') {
      try {
        if (activeInput.selectionStart !== null && activeInput.selectionEnd !== null) {
          selection = { start: activeInput.selectionStart, end: activeInput.selectionEnd };
        }
      } catch {
        selection = undefined;
      }
    }
    host.classList.toggle('is-closed', !open);
    if (!open) {
      host.innerHTML = '<button type="button" class="editor-inspector-reopen" data-inspector-toggle>Inspector <span>→</span></button>';
      return;
    }
    const selectedObjectId = templateEditor.value.selected?.objectId;
    if (gameplayEditor.value.selectedObjectId !== selectedObjectId) gameplayEditor.select(selectedObjectId);
    const selectedInstance = mapEditor.value.selectedInstanceId
      ? mapEditor.value.map.objects.find((object) => object.instanceId === mapEditor.value.selectedInstanceId)
      : undefined;
    renderInspector(host, templateEditor.value, gameplayEditor.value, selectedInstance, previews, {
      mapId: mapEditor.value.map.mapId,
      mapDirty: mapEditor.value.dirty,
      saveAsOpen,
      saveAsVisualId,
      saveAsDisplayName,
      saveAsError,
      animationPickerField,
      animationPickerSearch,
      animationPickerSelectedId,
      activeTab,
    });
    const saveAsDialog = host.querySelector<HTMLDialogElement>('[data-save-as-dialog]');
    if (saveAsDialog && !saveAsDialog.open) saveAsDialog.showModal();
    const animationPickerDialog = host.querySelector<HTMLDialogElement>('[data-animation-picker-dialog]');
    if (animationPickerDialog && !animationPickerDialog.open) animationPickerDialog.showModal();
    const scroll = host.querySelector<HTMLElement>('.editor-inspector-scroll');
    if (scroll) scroll.scrollTop = scrollTop;
    if (activeField) {
      const inputs = host.querySelectorAll<HTMLInputElement>(
        activeField.kind === 'template' ? '[data-template-field]' : activeField.kind === 'gameplay' ? '[data-gameplay-field]' : activeField.kind === 'instance' ? '[data-instance-field]' : '[data-save-as-field]',
      );
      const replacement = [...inputs].find((input) => (
        activeField.kind === 'template'
          ? input.dataset.templateField === activeField.id
          : activeField.kind === 'gameplay'
            ? input.dataset.gameplayField === activeField.id
            : activeField.kind === 'instance'
              ? input.dataset.instanceField === activeField.id
              : input.dataset.saveAsField === activeField.id
      ));
      replacement?.focus({ preventScroll: true });
      if (replacement && selection && replacement.type !== 'number') {
        try {
          replacement.setSelectionRange(selection.start, selection.end);
        } catch {
          // Selection ranges are not available for every browser/input type.
        }
      }
    }
  };

  const clickHandler = (event: MouseEvent): void => {
    const target = (event.target as HTMLElement).closest<HTMLElement>('[data-inspector-toggle], [data-command], [data-animation-picker-id], [data-inspector-tab]');
    if (!target) return;
    if (target.dataset.inspectorTab === 'visuals' || target.dataset.inspectorTab === 'gameplay') {
      activeTab = target.dataset.inspectorTab;
      render();
      return;
    }
    if (target.dataset.inspectorToggle !== undefined || target.hasAttribute('data-inspector-toggle')) {
      open = !open;
      render();
      return;
    }
    if (target.dataset.command === 'reset-offset') {
      const draft = templateEditor.value.draft;
      if (draft) templateEditor.updateDraft({ visualOffset: { x: 0, y: 0 } });
    }
    if (target.dataset.command === 'reset-scale') templateEditor.updateDraft({ scale: 1 });
    if (target.dataset.command === 'reset-template') templateEditor.resetChanges();
    if (target.dataset.command === 'reset-gameplay') gameplayEditor.resetChanges();
    if (target.dataset.command === 'reset-instance-field' && mapEditor.value.selectedInstanceId && target.dataset.instanceResetField) {
      const keys = target.dataset.instanceResetField === 'dropObjectId'
        ? ['dropObjectId', 'dropVisualId']
        : [target.dataset.instanceResetField];
      mapEditor.clearObjectInitialStateKeys(mapEditor.value.selectedInstanceId, keys);
    }
    if (target.dataset.command === 'reset-instance-overrides' && mapEditor.value.selectedInstanceId) {
      mapEditor.clearObjectInitialStateKeys(mapEditor.value.selectedInstanceId);
    }
    if (target.dataset.command === 'save-as-template' && !mapEditor.value.dirty && !gameplayEditor.value.hasDirtyDrafts) {
      const state = templateEditor.value;
      if (!state.selected || !state.draft) return;
      saveAsOpen = true;
      saveAsVisualId = `${state.selected.visualId}-copy`;
      saveAsDisplayName = `${state.draft.displayName} Copy`;
      saveAsError = '';
      render();
    }
    if (target.dataset.command === 'cancel-save-as') {
      saveAsOpen = false;
      saveAsError = '';
      render();
    }
    const browseField = target.dataset.command === 'browse-animation-idle'
      ? 'idleAnimationId'
      : target.dataset.command === 'browse-animation-on-hit'
        ? 'onHitAnimationId'
        : undefined;
    if (browseField) {
      animationPickerField = browseField;
      animationPickerSearch = '';
      animationPickerSelectedId = templateEditor.value.draft?.[browseField];
      render();
      return;
    }
    const clearField = target.dataset.command === 'clear-animation-idle'
      ? 'idleAnimationId'
      : target.dataset.command === 'clear-animation-on-hit'
        ? 'onHitAnimationId'
        : undefined;
    if (clearField) {
      templateEditor.updateDraft({ [clearField]: '' });
      return;
    }
    if (target.dataset.command === 'cancel-animation-picker') {
      animationPickerField = undefined;
      animationPickerSearch = '';
      animationPickerSelectedId = undefined;
      render();
      return;
    }
    if (target.dataset.animationPickerId !== undefined) {
      animationPickerSelectedId = target.dataset.animationPickerId || undefined;
      render();
    }
  };

  const changeHandler = (event: Event): void => {
    const target = event.target as HTMLInputElement;
    const instanceField = target.dataset.instanceField;
    const instanceId = mapEditor.value.selectedInstanceId;
    if (instanceField && instanceId) {
      const selectedObject = mapEditor.value.map.objects.find((object) => object.instanceId === instanceId);
      const isCollectible = selectedObject ? getObjectArchetype(selectedObject.objectId as Parameters<typeof getObjectArchetype>[0]).collectible !== undefined : false;
      if (instanceField === 'quantity' && isCollectible) {
        if (target.value === '') mapEditor.clearObjectInitialStateKeys(instanceId, ['quantity']);
        else mapEditor.updateObjectInitialState(instanceId, { quantity: Number(target.value) });
      }
      if (instanceField === 'health' && !isCollectible) {
        if (target.value === '') mapEditor.clearObjectInitialStateKeys(instanceId, ['health']);
        else mapEditor.updateObjectInitialState(instanceId, { health: Number(target.value) });
      }
      if (instanceField === 'dropPieces' && !isCollectible) {
        if (target.value === '') mapEditor.clearObjectInitialStateKeys(instanceId, ['dropPieces']);
        else mapEditor.updateObjectInitialState(instanceId, { dropPieces: Number(target.value) });
      }
      if (instanceField === 'dropObjectId' && !isCollectible) {
        if (target.value === '') mapEditor.clearObjectInitialStateKeys(instanceId, ['dropObjectId', 'dropVisualId']);
        else {
          const firstVisual = getObjectVisualChoices().find((choice) => choice.objectId === target.value)?.visualId;
          mapEditor.updateObjectInitialState(instanceId, { dropObjectId: target.value, ...(firstVisual ? { dropVisualId: firstVisual } : {}) });
        }
      }
      if (instanceField === 'dropVisualId' && !isCollectible) {
        if (target.value === '') mapEditor.clearObjectInitialStateKeys(instanceId, ['dropVisualId']);
        else mapEditor.updateObjectInitialState(instanceId, { dropVisualId: target.value });
      }
      return;
    }
    const gameplayField = target.dataset.gameplayField;
    if (gameplayField) {
      const draft = gameplayEditor.value.draft;
      if (!draft) return;
      if (gameplayField === 'persistHealth' && draft.kind === 'resource') gameplayEditor.updateDraft({ persistHealth: target.checked });
      else if (gameplayField === 'itemId' && draft.kind === 'collectible') gameplayEditor.updateDraft({ itemId: target.value });
      else if (gameplayField === 'quantity' && draft.kind === 'collectible') gameplayEditor.updateDraft({ quantity: Number(target.value) });
      else if (draft.kind === 'resource') {
        if (gameplayField === 'health') gameplayEditor.updateDraft({ health: Number(target.value) });
        if (gameplayField === 'dropObjectId') {
          const firstVisual = getObjectVisualChoices().find((choice) => choice.objectId === target.value)?.visualId;
          gameplayEditor.updateDraft({ dropObjectId: target.value, ...(firstVisual ? { dropVisualId: firstVisual } : {}) });
        }
        if (gameplayField === 'dropVisualId') gameplayEditor.updateDraft({ dropVisualId: target.value });
        if (gameplayField === 'dropPieces') gameplayEditor.updateDraft({ dropPieces: Number(target.value) });
        if (gameplayField === 'hitEffectId') gameplayEditor.updateDraft({ hitEffectId: target.value });
        if (gameplayField === 'depletionMessage') gameplayEditor.updateDraft({ depletionMessage: target.value });
        if (gameplayField === 'harvestTargetTag') gameplayEditor.updateDraft({ harvestTargetTag: target.value });
        if (gameplayField === 'harvestMinimumTier') gameplayEditor.updateDraft({ harvestMinimumTier: Number(target.value) });
        if (gameplayField === 'harvestFailureMessage') gameplayEditor.updateDraft({ harvestFailureMessage: target.value });
      }
      return;
    }
    const field = target.dataset.templateField;
    if (!field) {
      if (target.dataset.templateOcclusionToggle !== undefined) {
        const current = templateEditor.value.draft?.occlusionBounds;
        const dimensions = templateEditor.value.frameDimensions;
        templateEditor.updateDraft({
          occlusionBounds: target.checked
            ? current ?? {
              width: dimensions?.width ?? 1,
              height: dimensions?.height ?? 1,
              offsetX: 0,
              offsetY: 0,
            }
            : undefined,
        });
        return;
      }
      if (target.dataset.templateDepthToggle !== undefined) {
        const current = templateEditor.value.draft?.depthBounds;
        const dimensions = templateEditor.value.frameDimensions;
        templateEditor.updateDraft({
          depthBounds: target.checked
            ? current ?? {
              width: dimensions?.width ?? 1,
              height: dimensions?.height ?? 1,
              offsetX: 0,
              offsetY: 0,
            }
            : undefined,
        });
        return;
      }
      if (target.dataset.overlayScope === 'all-matching') {
        templateEditor.setShowAllMatchingOverlays(target.checked);
        return;
      }
      const geometryKey = target.dataset.overlayGeometry;
      if (geometryKey === 'frame' || geometryKey === 'collider' || geometryKey === 'occlusion' || geometryKey === 'depth') {
        templateEditor.setOverlayVisibility(geometryKey, target.checked);
      }
      return;
    }
    if (field === 'displayName') {
      templateEditor.updateDraft({ displayName: target.value });
      return;
    }
    if (field === 'scale') {
      templateEditor.updateDraft({ scale: Number(target.value) });
      return;
    }
    if (field === 'idleAnimationId' || field === 'onHitAnimationId') {
      templateEditor.updateDraft({ [field]: target.value });
      return;
    }
    if (field === 'shape') {
      const draft = templateEditor.value.draft;
      if (!draft?.collider) return;
      const shape: CollisionShape = target.value === 'circle' || target.value === 'ellipse' ? target.value : 'rectangle';
      const collider = { ...draft.collider, shape };
      if (shape === 'circle') {
        collider.radius ??= Math.min(collider.width, collider.height) / 2;
        delete collider.radiusX;
        delete collider.radiusY;
      } else if (shape === 'ellipse') {
        collider.radiusX ??= collider.width / 2;
        collider.radiusY ??= collider.height / 2;
        delete collider.radius;
      } else {
        delete collider.radius;
        delete collider.radiusX;
        delete collider.radiusY;
      }
      templateEditor.updateDraft({ collider });
      return;
    }
    const value = Number(target.value);
    if (field === 'visualOffsetX') templateEditor.updateDraft({ visualOffset: { x: value, y: templateEditor.value.draft?.visualOffset.y ?? 0 } });
    if (field === 'visualOffsetY') templateEditor.updateDraft({ visualOffset: { x: templateEditor.value.draft?.visualOffset.x ?? 0, y: value } });
    if (field === 'width' || field === 'height' || field === 'offsetX' || field === 'offsetY' || field === 'radius' || field === 'radiusX' || field === 'radiusY') {
      updateCollider(templateEditor, field, value);
    }
    if (field === 'occlusionWidth') updateOcclusion(templateEditor, 'width', value);
    if (field === 'occlusionHeight') updateOcclusion(templateEditor, 'height', value);
    if (field === 'occlusionOffsetX') updateOcclusion(templateEditor, 'offsetX', value);
    if (field === 'occlusionOffsetY') updateOcclusion(templateEditor, 'offsetY', value);
    if (field === 'depthWidth') updateDepthBounds(templateEditor, 'width', value);
    if (field === 'depthHeight') updateDepthBounds(templateEditor, 'height', value);
    if (field === 'depthOffsetX') updateDepthBounds(templateEditor, 'offsetX', value);
    if (field === 'depthOffsetY') updateDepthBounds(templateEditor, 'offsetY', value);
  };

  const submitHandler = (event: SubmitEvent): void => {
    event.preventDefault();
    const form = event.target as HTMLFormElement;
    if (form.hasAttribute('data-save-as-form')) {
      if (mapEditor.value.dirty) {
        saveAsError = 'Save the map before creating a new template.';
        render();
        return;
      }
      void (async () => {
        const originalUrl = window.location.href;
        const targetUrl = new URL(originalUrl);
        const selected = templateEditor.value.selected;
        if (selected) targetUrl.searchParams.set('templateObject', selected.objectId);
        targetUrl.searchParams.set('templateVisual', saveAsVisualId.trim());
        window.history.replaceState({}, '', targetUrl);
        try {
          const created = await templateEditor.saveAsNewTemplate(
            saveAsVisualId.trim(),
            saveAsDisplayName.trim(),
          );
          if (!created) {
            window.history.replaceState({}, '', originalUrl);
            saveAsError = templateEditor.value.status;
            render();
            return;
          }
          targetUrl.searchParams.set('templateObject', created.objectId);
          targetUrl.searchParams.set('templateVisual', created.visualId);
          window.location.assign(targetUrl);
        } catch {
          window.history.replaceState({}, '', originalUrl);
          saveAsError = templateEditor.value.status;
          render();
        }
      })();
      return;
    }
    if (form.hasAttribute('data-animation-picker-form')) {
      if (animationPickerField) templateEditor.updateDraft({ [animationPickerField]: animationPickerSelectedId ?? '' });
      animationPickerField = undefined;
      animationPickerSearch = '';
      animationPickerSelectedId = undefined;
      render();
      return;
    }
    if (form.hasAttribute('data-gameplay-form')) {
      void gameplayEditor.save();
      return;
    }
    void templateEditor.save();
  };

  const inputHandler = (event: Event): void => {
    const target = event.target as HTMLInputElement;
    if (target.dataset.saveAsField === 'visualId') saveAsVisualId = target.value;
    if (target.dataset.saveAsField === 'displayName') saveAsDisplayName = target.value;
    if (target.dataset.animationPickerSearch !== undefined) {
      animationPickerSearch = target.value;
      render();
      host.querySelector<HTMLInputElement>('[data-animation-picker-search]')?.focus();
    }
  };

  const keydownHandler = (event: KeyboardEvent): void => {
    const tab = (event.target as HTMLElement).closest<HTMLElement>('[data-inspector-tab]');
    if (!tab || !['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault();
    activeTab = event.key === 'ArrowLeft' || event.key === 'Home' ? 'visuals' : 'gameplay';
    render();
    host.querySelector<HTMLElement>(`[data-inspector-tab="${activeTab}"]`)?.focus();
  };

  host.addEventListener('click', clickHandler);
  host.addEventListener('change', changeHandler);
  host.addEventListener('input', inputHandler);
  host.addEventListener('submit', submitHandler);
  host.addEventListener('keydown', keydownHandler);
  const unsubscribe = templateEditor.subscribe(render);
  const unsubscribeMap = mapEditor.subscribe(render);
  const unsubscribeGameplay = gameplayEditor.subscribe(render);

  return () => {
    unsubscribe();
    unsubscribeMap();
    unsubscribeGameplay();
    host.removeEventListener('click', clickHandler);
    host.removeEventListener('change', changeHandler);
    host.removeEventListener('input', inputHandler);
    host.removeEventListener('submit', submitHandler);
    host.removeEventListener('keydown', keydownHandler);
    host.innerHTML = '';
  };
}
