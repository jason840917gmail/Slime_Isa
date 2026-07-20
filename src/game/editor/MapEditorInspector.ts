import {
  getObjectVisualChoices,
  type ColliderBounds,
} from '../content/objects/ObjectCatalog';
import {
  type ObjectTemplateEditorState,
  type ObjectTemplateViewState,
} from './ObjectTemplateEditorState';

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

function renderInspector(host: HTMLElement, state: ObjectTemplateViewState, previews: InspectorPreviewUrls): void {
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
        <section class="editor-inspector-section">
          <div class="editor-inspector-section-title"><span>02</span><h3>Visual alignment</h3></div>
          <p class="editor-inspector-help">Moves the art in source-frame pixels. The map anchor and collider stay fixed.</p>
          <div class="editor-inspector-grid">
            ${renderNumberField('Horizontal', 'visualOffsetX', draft.visualOffset.x, errors.visualOffsetX, 'template-offset-x')}
            ${renderNumberField('Vertical', 'visualOffsetY', draft.visualOffset.y, errors.visualOffsetY, 'template-offset-y')}
          </div>
          <button type="button" class="editor-inspector-secondary" data-command="reset-offset">Reset to 0, 0</button>
        </section>
        <section class="editor-inspector-section">
          <div class="editor-inspector-section-title"><span>03</span><h3>Collider</h3></div>
          ${selected.physics === null
            ? '<p class="editor-inspector-no-physics">This object has no physics.</p>'
            : `<p class="editor-inspector-help">Source-frame pixels · ${state.frameDimensions ? `${state.frameDimensions.width} × ${state.frameDimensions.height}` : 'frame bounds unavailable'}</p>
              <div class="editor-inspector-grid">
                ${renderNumberField('Width', 'width', collider?.width ?? 1, errors.width, 'template-collider-width')}
                ${renderNumberField('Height', 'height', collider?.height ?? 1, errors.height, 'template-collider-height')}
                ${renderNumberField('Offset X', 'offsetX', collider?.offsetX ?? 0, errors.offsetX, 'template-collider-offset-x')}
                ${renderNumberField('Offset Y', 'offsetY', collider?.offsetY ?? 0, errors.offsetY, 'template-collider-offset-y')}
              </div>
              ${renderError(errors.collider)}`}
        </section>
        <section class="editor-inspector-section editor-inspector-actions">
          <div class="editor-inspector-action-row">
            <button type="button" class="editor-inspector-secondary" data-command="reset-template" ${state.dirty ? '' : 'disabled'}>Reset changes</button>
            <button type="submit" class="editor-inspector-save" data-testid="save-template-button" ${state.dirty && !state.saving && Object.keys(errors).length === 0 ? '' : 'disabled'}>Save template</button>
          </div>
          <p class="editor-inspector-status" aria-live="polite">${escapeHtml(state.status)}</p>
        </section>
      </form>
    </div>`;
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

export function mountMapEditorInspector(
  host: HTMLElement,
  templateEditor: ObjectTemplateEditorState,
  previews: InspectorPreviewUrls,
): () => void {
  let open = true;
  const render = (): void => {
    host.classList.toggle('is-closed', !open);
    if (!open) {
      host.innerHTML = '<button type="button" class="editor-inspector-reopen" data-inspector-toggle>Inspector <span>→</span></button>';
      return;
    }
    renderInspector(host, templateEditor.value, previews);
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
  };

  const changeHandler = (event: Event): void => {
    const target = event.target as HTMLInputElement;
    const field = target.dataset.templateField;
    if (!field) return;
    if (field === 'displayName') {
      templateEditor.updateDraft({ displayName: target.value });
      return;
    }
    const value = Number(target.value);
    if (field === 'visualOffsetX') templateEditor.updateDraft({ visualOffset: { x: value, y: templateEditor.value.draft?.visualOffset.y ?? 0 } });
    if (field === 'visualOffsetY') templateEditor.updateDraft({ visualOffset: { x: templateEditor.value.draft?.visualOffset.x ?? 0, y: value } });
    if (field === 'width' || field === 'height' || field === 'offsetX' || field === 'offsetY') {
      updateCollider(templateEditor, field, value);
    }
  };

  const submitHandler = (event: SubmitEvent): void => {
    event.preventDefault();
    void templateEditor.save();
  };

  host.addEventListener('click', clickHandler);
  host.addEventListener('change', changeHandler);
  host.addEventListener('submit', submitHandler);
  const unsubscribe = templateEditor.subscribe(render);

  return () => {
    unsubscribe();
    host.removeEventListener('click', clickHandler);
    host.removeEventListener('change', changeHandler);
    host.removeEventListener('submit', submitHandler);
    host.innerHTML = '';
  };
}
