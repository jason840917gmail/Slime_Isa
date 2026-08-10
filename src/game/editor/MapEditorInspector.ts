import {
  getObjectVisualChoices,
  type ColliderBounds,
  type DepthBounds,
} from '../content/objects/ObjectCatalog';
import {
  type ObjectTemplateEditorState,
  type ObjectTemplateViewState,
} from './ObjectTemplateEditorState';
import { EDITOR_GEOMETRY_STYLES, type EditorGeometryKey } from './EditorGeometryStyles';
import type { MapEditorState } from './MapEditorState';
import type { CollisionShape } from '../shared/collisionShapes';

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

function renderShapeField(shape: CollisionShape | undefined): string {
  const selected = shape ?? 'rectangle';
  return `<label class="editor-inspector-field"><span>Shape<small>collision primitive</small></span><select data-template-field="shape"><option value="rectangle" ${selected === 'rectangle' ? 'selected' : ''}>Rectangle</option><option value="circle" ${selected === 'circle' ? 'selected' : ''}>Circle</option><option value="ellipse" ${selected === 'ellipse' ? 'selected' : ''}>Ellipse</option></select></label>`;
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
  readonly mapDirty: boolean;
  readonly saveAsOpen: boolean;
  readonly saveAsVisualId: string;
  readonly saveAsDisplayName: string;
  readonly saveAsError: string;
}

function renderInspector(
  host: HTMLElement,
  state: ObjectTemplateViewState,
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
      <form class="editor-template-form" data-template-form>
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
          <p class="editor-inspector-help">Moves the art in source-frame pixels. The map anchor and collider stay fixed.</p>
          <div class="editor-inspector-grid">
            ${renderNumberField('Horizontal', 'visualOffsetX', draft.visualOffset.x, errors.visualOffsetX, 'template-offset-x')}
            ${renderNumberField('Vertical', 'visualOffsetY', draft.visualOffset.y, errors.visualOffsetY, 'template-offset-y')}
          </div>
          <button type="button" class="editor-inspector-secondary" data-command="reset-offset">Reset to 0, 0</button>
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
            <input type="checkbox" data-template-occlusion-toggle ${occlusion ? 'checked' : ''} ${frameGeometrySupported && !selected.visualSetId && !selected.animationClip ? '' : 'disabled'} />
            <span><strong>Occludes actors</strong><small>${frameGeometrySupported && !selected.visualSetId && !selected.animationClip ? 'Reveal only the hidden pixels of the player and engaged enemies' : 'Requires a static spritesheet frame'}</small></span>
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
            ${renderGeometryToggle('occlusion', state.showOcclusionOverlay, Boolean(occlusion && frameGeometrySupported && !selected.visualSetId && !selected.animationClip), 'Occlusion', 'Blue scan region and reveal shape')}
          </div>
        </section>
        <section class="editor-inspector-section editor-inspector-actions">
          <div class="editor-inspector-action-row">
            <button type="button" class="editor-inspector-secondary" data-command="reset-template" ${state.dirty ? '' : 'disabled'}>Reset changes</button>
            <button type="submit" class="editor-inspector-save" data-testid="save-template-button" ${state.dirty && !state.saving && Object.keys(errors).length === 0 ? '' : 'disabled'}>Save template</button>
            <button type="button" class="editor-inspector-secondary editor-inspector-save-as" data-command="save-as-template" ${!state.saving && !ui.mapDirty && Object.keys(errors).length === 0 ? '' : 'disabled'}>Save as new template</button>
          </div>
          ${ui.mapDirty ? '<p class="editor-inspector-help">Save the map before creating a new template.</p>' : ''}
          <p class="editor-inspector-status" aria-live="polite">${escapeHtml(state.status)}</p>
        </section>
      </form>
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
): () => void {
  let open = true;
  let saveAsOpen = false;
  let saveAsVisualId = '';
  let saveAsDisplayName = '';
  let saveAsError = '';
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
    renderInspector(host, templateEditor.value, previews, {
      mapDirty: mapEditor.value.dirty,
      saveAsOpen,
      saveAsVisualId,
      saveAsDisplayName,
      saveAsError,
    });
    const saveAsDialog = host.querySelector<HTMLDialogElement>('[data-save-as-dialog]');
    if (saveAsDialog && !saveAsDialog.open) saveAsDialog.showModal();
    const scroll = host.querySelector<HTMLElement>('.editor-inspector-scroll');
    if (scroll) scroll.scrollTop = scrollTop;
    if (activeField) {
      const inputs = host.querySelectorAll<HTMLInputElement>(
        activeField.kind === 'template' ? '[data-template-field]' : '[data-save-as-field]',
      );
      const replacement = [...inputs].find((input) => (
        activeField.kind === 'template'
          ? input.dataset.templateField === activeField.id
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
    const target = (event.target as HTMLElement).closest<HTMLElement>('[data-inspector-toggle], [data-command]');
    if (!target) return;
    if (target.dataset.inspectorToggle !== undefined || target.hasAttribute('data-inspector-toggle')) {
      open = !open;
      render();
      return;
    }
    if (target.dataset.command === 'reset-offset') {
      const draft = templateEditor.value.draft;
      if (draft) templateEditor.updateDraft({ visualOffset: { x: 0, y: 0 } });
    }
    if (target.dataset.command === 'reset-template') templateEditor.resetChanges();
    if (target.dataset.command === 'save-as-template' && !mapEditor.value.dirty) {
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
  };

  const changeHandler = (event: Event): void => {
    const target = event.target as HTMLInputElement;
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
    void templateEditor.save();
  };

  const inputHandler = (event: Event): void => {
    const target = event.target as HTMLInputElement;
    if (target.dataset.saveAsField === 'visualId') saveAsVisualId = target.value;
    if (target.dataset.saveAsField === 'displayName') saveAsDisplayName = target.value;
  };

  host.addEventListener('click', clickHandler);
  host.addEventListener('change', changeHandler);
  host.addEventListener('input', inputHandler);
  host.addEventListener('submit', submitHandler);
  const unsubscribe = templateEditor.subscribe(render);
  const unsubscribeMap = mapEditor.subscribe(render);

  return () => {
    unsubscribe();
    unsubscribeMap();
    host.removeEventListener('click', clickHandler);
    host.removeEventListener('change', changeHandler);
    host.removeEventListener('input', inputHandler);
    host.removeEventListener('submit', submitHandler);
    host.innerHTML = '';
  };
}
