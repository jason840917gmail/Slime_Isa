import type {
  CharacterStudioAssetCatalog,
  CharacterStudioAssetEntry,
} from '../content/characters/characterAssetCatalog';
import type {
  AnimationPackageCatalog,
  AnimationPackageCatalogEntry,
} from '../content/animations/types';
import {
  getObjectArchetype,
  getObjectArchetypeIds,
  type ObjectArchetypeId,
} from '../content/objects/ObjectCatalog';
import { resolveAssetUrl } from '../infrastructure/assets/assetUrls';

interface ObjectAuthoringOptions {
  readonly mapId: string;
}

interface BoundsDraft {
  width: string;
  height: string;
  offsetX: string;
  offsetY: string;
}

interface ObjectAuthoringState {
  objectId: ObjectArchetypeId;
  assetId: string;
  frame: string;
  visualId: string;
  displayName: string;
  scale: string;
  visualOffsetX: string;
  visualOffsetY: string;
  collider: BoundsDraft;
  depth: BoundsDraft;
  occlusion: BoundsDraft;
  depthEnabled: boolean;
  occlusionEnabled: boolean;
  idleAnimationId: string;
  onHitAnimationId: string;
  assets?: CharacterStudioAssetCatalog;
  animations?: AnimationPackageCatalog;
  loading: boolean;
  importing: boolean;
  submitting: boolean;
  notice: string;
}

interface AssetInfo {
  readonly url: string;
  readonly width: number;
  readonly height: number;
  readonly columns: number;
  readonly rows: number;
  readonly count: number;
}

function escapeHtml(value: unknown): string {
  return String(value).replace(/[&<>'"]/g, (character) => ({
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

function integerValue(value: unknown, fallback = 0): number {
  const result = Number(value);
  return Number.isFinite(result) ? Math.round(result) : fallback;
}

function decimalValue(value: unknown, fallback = 1): number {
  const result = Number(value);
  return Number.isFinite(result) ? result : fallback;
}

function assetInfo(entry: CharacterStudioAssetEntry | undefined): AssetInfo {
  if (!entry) return { url: '', width: 1, height: 1, columns: 1, rows: 1, count: 1 };
  let url = `/asset/${entry.sourcePath}`;
  try {
    url = resolveAssetUrl(entry.sourcePath);
  } catch {
    // Newly imported assets are available from the dev server before the
    // manifest-driven Vite glob is refreshed.
  }
  if (!entry.frame) return { url, width: entry.dimensions.width, height: entry.dimensions.height, columns: 1, rows: 1, count: 1 };
  return {
    url,
    width: entry.frame.width,
    height: entry.frame.height,
    columns: entry.frame.columns,
    rows: entry.frame.rows,
    count: entry.frame.count,
  };
}

function selectedAsset(state: ObjectAuthoringState): CharacterStudioAssetEntry | undefined {
  return state.assets?.assets.find((entry) => entry.assetId === state.assetId);
}

function geometryDefaults(entry: CharacterStudioAssetEntry | undefined, solid: boolean): BoundsDraft {
  const info = assetInfo(entry);
  const height = Math.max(1, Math.round(info.height * (solid ? 0.24 : 0.2)));
  const width = Math.max(1, Math.round(info.width * (solid ? 0.42 : 0.4)));
  return {
    width: String(Math.min(info.width, width)),
    height: String(Math.min(info.height, height)),
    offsetX: String(Math.max(0, Math.round((info.width - width) / 2))),
    offsetY: String(Math.max(0, info.height - height - Math.round(info.height * 0.04))),
  };
}

function initialState(): ObjectAuthoringState {
  const objectId = getObjectArchetypeIds().find((candidate) => candidate === 'decoration.world.solid') ?? getObjectArchetypeIds()[0];
  return {
    objectId,
    assetId: '',
    frame: '0',
    visualId: '',
    displayName: '',
    scale: '1',
    visualOffsetX: '0',
    visualOffsetY: '0',
    collider: { width: '1', height: '1', offsetX: '0', offsetY: '0' },
    depth: { width: '1', height: '1', offsetX: '0', offsetY: '0' },
    occlusion: { width: '1', height: '1', offsetX: '0', offsetY: '0' },
    depthEnabled: false,
    occlusionEnabled: false,
    idleAnimationId: '',
    onHitAnimationId: '',
    loading: false,
    importing: false,
    submitting: false,
    notice: 'Choose a behavior family and a registered visual source.',
  };
}

function frameInfo(state: ObjectAuthoringState): { readonly info: AssetInfo; readonly frame: number } {
  const info = assetInfo(selectedAsset(state));
  const frame = Math.max(0, Math.min(info.count - 1, integerValue(state.frame)));
  return { info, frame };
}

function renderFramePreview(state: ObjectAuthoringState): string {
  const { info, frame } = frameInfo(state);
  const column = frame % info.columns;
  const row = Math.floor(frame / info.columns);
  const x = info.columns === 1 ? 0 : Math.round((column / (info.columns - 1)) * 10000) / 100;
  const y = info.rows === 1 ? 0 : Math.round((row / (info.rows - 1)) * 10000) / 100;
  if (!selectedAsset(state)) {
    return '<div class="object-authoring-preview object-authoring-preview--empty"><span>Choose a source sheet</span></div>';
  }
  return `<div class="object-authoring-preview" style="--object-source-image:url('${escapeHtml(info.url)}');--object-source-cols:${info.columns};--object-source-rows:${info.rows};--object-source-position-x:${x}%;--object-source-position-y:${y}%;--object-source-ratio:${info.width}/${info.height}" role="img" aria-label="Source frame ${frame}"></div>`;
}

function renderBoundsFields(prefix: string, label: string, bounds: BoundsDraft): string {
  return `<fieldset class="object-authoring-bounds"><legend>${label}</legend>
    <label><span>Width</span><input type="number" min="1" step="1" name="${prefix}Width" value="${escapeHtml(bounds.width)}" /></label>
    <label><span>Height</span><input type="number" min="1" step="1" name="${prefix}Height" value="${escapeHtml(bounds.height)}" /></label>
    <label><span>Offset X</span><input type="number" min="0" step="1" name="${prefix}OffsetX" value="${escapeHtml(bounds.offsetX)}" /></label>
    <label><span>Offset Y</span><input type="number" min="0" step="1" name="${prefix}OffsetY" value="${escapeHtml(bounds.offsetY)}" /></label>
  </fieldset>`;
}

function renderAnimationOptions(
  packages: readonly AnimationPackageCatalogEntry[] | undefined,
  loop: boolean,
  selected: string,
): string {
  const options = packages
    ?.filter((entry) => entry.animation.loop === loop)
    .map((entry) => `<option value="${escapeHtml(entry.animationId)}" ${entry.animationId === selected ? 'selected' : ''}>${escapeHtml(entry.displayName)} · ${escapeHtml(entry.animationId)}</option>`)
    .join('') ?? '';
  return `<option value="">None</option>${options}`;
}

function renderDialog(dialog: HTMLDialogElement, state: ObjectAuthoringState): void {
  const object = getObjectArchetype(state.objectId);
  const solid = object.physics !== null;
  const assets = state.assets?.assets ?? [];
  const info = frameInfo(state).info;
  const frame = frameInfo(state).frame;
  const visibleAssets = assets.map((entry) => {
    const detail = assetInfo(entry);
    const descriptor = entry.frame ? `${entry.frame.width}×${entry.frame.height} · ${entry.frame.count} frames` : `${detail.width}×${detail.height}`;
    return `<option value="${escapeHtml(entry.assetId)}" ${entry.assetId === state.assetId ? 'selected' : ''}>${escapeHtml(entry.assetId)} · ${descriptor}</option>`;
  }).join('');
  const objectOptions = getObjectArchetypeIds().map((objectId) => {
    const candidate = getObjectArchetype(objectId);
    const behavior = candidate.behavior ?? (candidate.resourceNode ? 'gameplay-backed' : candidate.physics ? 'solid' : 'walkable');
    return `<option value="${escapeHtml(objectId)}" ${objectId === state.objectId ? 'selected' : ''}>${escapeHtml(titleFromId(objectId))} · ${behavior}</option>`;
  }).join('');
  const assetOptions = visibleAssets || '<option value="">No registered sources yet</option>';
  const loading = state.loading && !state.assets;
  const noticeClass = state.notice.startsWith('Created') ? 'is-success' : state.notice.includes('failed') || state.notice.includes('required') || state.notice.includes('must') ? 'is-error' : '';
  dialog.innerHTML = `<form class="object-authoring-form" data-object-authoring-form>
    <header class="object-authoring-header">
      <div><span class="editor-inspector-kicker">Map Studio / object content</span><h2>New object visual</h2><p>Author a reusable visual under an existing behavior family. The family keeps its gameplay rules, physics, tags, and resource behavior.</p></div>
      <button type="button" class="editor-icon-button" data-object-authoring-command="close" aria-label="Close">×</button>
    </header>
    ${loading ? '<div class="object-authoring-loading"><span>Reading the source library…</span></div>' : `<div class="object-authoring-layout">
      <div class="object-authoring-main">
        <section class="object-authoring-section"><div class="object-authoring-section-title"><span>01</span><div><h3>Behavior family</h3><p>Choose what the object is allowed to do in the world.</p></div></div>
          <label class="object-authoring-field object-authoring-field--wide"><span>Inherited object family</span><select name="objectId" data-object-authoring-select="objectId">${objectOptions}</select></label>
          <p class="object-authoring-callout"><strong>${escapeHtml(object.physics ? 'Solid placement' : 'Walkable decoration')}</strong> · ${escapeHtml(object.tags.join(' / '))}${object.resourceNode ? ' · this family also owns resource/damage behavior' : ''}</p>
        </section>
        <section class="object-authoring-section"><div class="object-authoring-section-title"><span>02</span><div><h3>Source artwork</h3><p>Select an existing sheet, or import a new PNG source.</p></div></div>
          <label class="object-authoring-field object-authoring-field--wide"><span>Registered source</span><select name="assetId" data-object-authoring-select="assetId">${assetOptions}</select></label>
          <div class="object-authoring-source-row"><div>${renderFramePreview(state)}</div><div class="object-authoring-source-controls">
            <label class="object-authoring-field"><span>Frame <small>${info.count} available</small></span><input name="frame" type="number" min="0" max="${Math.max(0, info.count - 1)}" step="1" value="${frame}" data-object-authoring-frame /></label>
            <input type="file" accept="image/png" data-object-authoring-upload hidden />
            <button type="button" class="editor-inspector-secondary" data-object-authoring-command="import" ${state.importing ? 'disabled' : ''}>${state.importing ? 'IMPORTING…' : 'Import PNG source'}</button>
            <small>For a sheet, frame width and height are captured during import and become the authoritative tile size.</small>
          </div></div>
        </section>
        <section class="object-authoring-section"><div class="object-authoring-section-title"><span>03</span><div><h3>Identity</h3><p>Stable IDs are used by maps and animation references.</p></div></div>
          <div class="object-authoring-grid"><label class="object-authoring-field"><span>Visual ID</span><input name="visualId" required pattern="[a-z0-9]+([.-][a-z0-9-]+)*" maxlength="80" value="${escapeHtml(state.visualId)}" placeholder="autumn-tree-hit" /></label><label class="object-authoring-field"><span>Display name</span><input name="displayName" required maxlength="80" value="${escapeHtml(state.displayName)}" placeholder="Autumn tree hit" /></label></div>
        </section>
        <section class="object-authoring-section"><div class="object-authoring-section-title"><span>04</span><div><h3>World geometry</h3><p>These values are in source-frame pixels before the visual scale is applied.</p></div></div>
          <div class="object-authoring-grid"><label class="object-authoring-field"><span>Visual scale</span><input name="scale" type="number" min="0.05" max="8" step="0.05" value="${escapeHtml(state.scale)}" /></label><label class="object-authoring-field"><span>Visual offset X / Y</span><div class="object-authoring-inline"><input name="visualOffsetX" type="number" step="1" value="${escapeHtml(state.visualOffsetX)}" aria-label="Visual offset X" /><input name="visualOffsetY" type="number" step="1" value="${escapeHtml(state.visualOffsetY)}" aria-label="Visual offset Y" /></div></label></div>
          ${solid ? renderBoundsFields('collider', 'Solid collider', state.collider) : '<p class="object-authoring-callout">This family is walkable, so it cannot receive a collider.</p>'}
          <label class="object-authoring-check"><input type="checkbox" name="depthEnabled" ${state.depthEnabled ? 'checked' : ''} data-object-authoring-toggle="depth" /><span><strong>Add a depth bound</strong><small>Controls the sort anchor when the artwork is taller than its footprint.</small></span></label>
          ${state.depthEnabled ? renderBoundsFields('depth', 'Depth bound', state.depth) : ''}
          <label class="object-authoring-check"><input type="checkbox" name="occlusionEnabled" ${state.occlusionEnabled ? 'checked' : ''} data-object-authoring-toggle="occlusion" /><span><strong>Add an occlusion region</strong><small>Use for tall solid artwork when actors should pass behind the upper portion.</small></span></label>
          ${state.occlusionEnabled ? renderBoundsFields('occlusion', 'Occlusion region', state.occlusion) : ''}
        </section>
        <section class="object-authoring-section"><div class="object-authoring-section-title"><span>05</span><div><h3>Animation hooks</h3><p>Animation Studio authors packages; Map Studio assigns them to this object visual.</p></div></div>
          <div class="object-authoring-grid"><label class="object-authoring-field"><span>Idle animation <small>looping packages</small></span><select name="idleAnimationId">${renderAnimationOptions(state.animations?.packages, true, state.idleAnimationId)}</select></label><label class="object-authoring-field"><span>On-hit animation <small>one-shot packages</small></span><select name="onHitAnimationId">${renderAnimationOptions(state.animations?.packages, false, state.onHitAnimationId)}</select></label></div>
          <p class="object-authoring-callout">Animated templates cannot also define occlusion. If you assign an animation, leave the occlusion checkbox off.</p>
        </section>
      </div>
      <aside class="object-authoring-summary"><span class="editor-inspector-kicker">Ready to create</span><h3>${escapeHtml(state.displayName || 'Untitled object')}</h3><p>${escapeHtml(titleFromId(state.objectId))}</p><div class="object-authoring-summary-preview">${renderFramePreview(state)}</div><dl><div><dt>Source</dt><dd>${escapeHtml(state.assetId || 'Not selected')}</dd></div><div><dt>Frame</dt><dd>${frame} / ${Math.max(0, info.count - 1)}</dd></div><div><dt>Physics</dt><dd>${solid ? 'Static collider' : 'Walkable'}</dd></div></dl></aside>
    </div>`}
    <p class="object-authoring-notice ${noticeClass}" data-object-authoring-notice aria-live="polite">${escapeHtml(state.notice)}</p>
    <footer class="object-authoring-footer"><button type="button" class="editor-inspector-secondary" data-object-authoring-command="cancel">Cancel</button><button type="submit" class="editor-inspector-save" ${state.submitting || loading ? 'disabled' : ''}>${state.submitting ? 'Creating…' : 'Create object visual'}</button></footer>
  </form>`;
}

function numberField(form: HTMLFormElement, name: string, fallback: number): number {
  return integerValue((form.elements.namedItem(name) as HTMLInputElement | null)?.value, fallback);
}

function boundsFromForm(form: HTMLFormElement, prefix: string): BoundsDraft {
  return {
    width: String(numberField(form, `${prefix}Width`, 1)),
    height: String(numberField(form, `${prefix}Height`, 1)),
    offsetX: String(numberField(form, `${prefix}OffsetX`, 0)),
    offsetY: String(numberField(form, `${prefix}OffsetY`, 0)),
  };
}

function boundsPayload(bounds: BoundsDraft): Record<string, number> {
  return {
    width: integerValue(bounds.width),
    height: integerValue(bounds.height),
    offsetX: integerValue(bounds.offsetX),
    offsetY: integerValue(bounds.offsetY),
  };
}

async function fetchCatalog<T>(url: string): Promise<T> {
  const response = await fetch(url);
  const payload = await response.json() as { readonly ok?: boolean; readonly data?: T; readonly error?: { readonly message?: string } };
  if (!response.ok || !payload.ok || payload.data === undefined) throw new Error(payload.error?.message ?? `Could not load ${url}`);
  return payload.data;
}

function updateStateFromForm(state: ObjectAuthoringState, form: HTMLFormElement): ObjectAuthoringState {
  const objectIdValue = (form.elements.namedItem('objectId') as HTMLSelectElement | null)?.value;
  const assetId = (form.elements.namedItem('assetId') as HTMLSelectElement | null)?.value ?? state.assetId;
  const objectId = objectIdValue && getObjectArchetypeIds().includes(objectIdValue as ObjectArchetypeId)
    ? objectIdValue as ObjectArchetypeId
    : state.objectId;
  return {
    ...state,
    objectId,
    assetId,
    frame: (form.elements.namedItem('frame') as HTMLInputElement | null)?.value ?? state.frame,
    visualId: (form.elements.namedItem('visualId') as HTMLInputElement | null)?.value ?? state.visualId,
    displayName: (form.elements.namedItem('displayName') as HTMLInputElement | null)?.value ?? state.displayName,
    scale: (form.elements.namedItem('scale') as HTMLInputElement | null)?.value ?? state.scale,
    visualOffsetX: (form.elements.namedItem('visualOffsetX') as HTMLInputElement | null)?.value ?? state.visualOffsetX,
    visualOffsetY: (form.elements.namedItem('visualOffsetY') as HTMLInputElement | null)?.value ?? state.visualOffsetY,
    collider: boundsFromForm(form, 'collider'),
    depth: boundsFromForm(form, 'depth'),
    occlusion: boundsFromForm(form, 'occlusion'),
    depthEnabled: (form.elements.namedItem('depthEnabled') as HTMLInputElement | null)?.checked ?? state.depthEnabled,
    occlusionEnabled: (form.elements.namedItem('occlusionEnabled') as HTMLInputElement | null)?.checked ?? state.occlusionEnabled,
    idleAnimationId: (form.elements.namedItem('idleAnimationId') as HTMLSelectElement | null)?.value ?? state.idleAnimationId,
    onHitAnimationId: (form.elements.namedItem('onHitAnimationId') as HTMLSelectElement | null)?.value ?? state.onHitAnimationId,
  };
}

function payloadFromForm(form: HTMLFormElement, state: ObjectAuthoringState): Record<string, unknown> {
  const values = new FormData(form);
  const objectId = values.get('objectId');
  const assetId = values.get('assetId');
  const payload: Record<string, unknown> = {
    objectId,
    assetId,
    frame: integerValue(values.get('frame')),
    visualId: values.get('visualId'),
    displayName: values.get('displayName'),
    scale: decimalValue(values.get('scale')),
    visualOffset: { x: integerValue(values.get('visualOffsetX')), y: integerValue(values.get('visualOffsetY')) },
    ...(getObjectArchetype(state.objectId).physics !== null ? { collider: boundsPayload(boundsFromForm(form, 'collider')) } : {}),
    ...(values.get('depthEnabled') === 'on' ? { depthBounds: boundsPayload(boundsFromForm(form, 'depth')) } : {}),
    ...(values.get('occlusionEnabled') === 'on' ? { occlusionBounds: boundsPayload(boundsFromForm(form, 'occlusion')) } : {}),
    ...(values.get('idleAnimationId') ? { idleAnimationId: values.get('idleAnimationId') } : {}),
    ...(values.get('onHitAnimationId') ? { onHitAnimationId: values.get('onHitAnimationId') } : {}),
  };
  return payload;
}

export function mountMapEditorObjectAuthoring(host: HTMLElement, options: ObjectAuthoringOptions): () => void {
  const dialog = document.createElement('dialog');
  dialog.className = 'object-authoring-dialog';
  dialog.setAttribute('data-object-authoring-dialog', '');
  host.append(dialog);
  let state = initialState();

  const render = (): void => renderDialog(dialog, state);
  const open = (): void => {
    if (!dialog.open) dialog.showModal();
    state = { ...state, loading: state.assets === undefined, notice: state.assets ? state.notice : 'Loading registered sources and shared animation packages…' };
    render();
    if (!state.assets || !state.animations) {
      state = { ...state, loading: true };
      render();
      void Promise.all([
        state.assets ? Promise.resolve(state.assets) : fetchCatalog<CharacterStudioAssetCatalog>('/__character-studio/assets'),
        state.animations ? Promise.resolve(state.animations) : fetchCatalog<AnimationPackageCatalog>('/__animation-library/catalog'),
      ]).then(([assets, animations]) => {
        const firstAsset = assets.assets[0];
        const object = getObjectArchetype(state.objectId);
        const defaults = geometryDefaults(firstAsset, object.physics !== null);
        state = {
          ...state,
          assets,
          animations,
          assetId: state.assetId || firstAsset?.assetId || '',
          collider: object.physics !== null ? defaults : state.collider,
          depth: defaults,
          occlusion: defaults,
          loading: false,
          notice: firstAsset ? 'Choose a source frame, then complete the object identity.' : 'No source assets are registered yet. Import a PNG to continue.',
        };
        render();
      }).catch((error: unknown) => {
        state = { ...state, loading: false, notice: error instanceof Error ? error.message : String(error) };
        render();
      });
    }
  };

  const close = (): void => {
    if (state.submitting) return;
    dialog.close();
  };

  const clickHandler = (event: MouseEvent): void => {
    const target = (event.target as HTMLElement).closest<HTMLElement>('[data-object-authoring-command]');
    if (!target) return;
    const command = target.dataset.objectAuthoringCommand;
    if (command === 'open') open();
    if (command === 'close' || command === 'cancel') close();
    if (command === 'import') dialog.querySelector<HTMLInputElement>('[data-object-authoring-upload]')?.click();
  };
  host.addEventListener('click', clickHandler);

  const changeHandler = (event: Event): void => {
    const target = event.target as HTMLElement;
    const form = target.closest<HTMLFormElement>('[data-object-authoring-form]');
    if (!form) return;
    if (target.matches('[data-object-authoring-upload]')) {
      const file = (target as HTMLInputElement).files?.[0];
      if (file) void importSource(file);
      return;
    }
    const selectName = target.getAttribute('data-object-authoring-select');
    if (selectName === 'objectId' || selectName === 'assetId') {
      const next = updateStateFromForm(state, form);
      const objectChanged = next.objectId !== state.objectId;
      const assetChanged = next.assetId !== state.assetId;
      state = {
        ...next,
        ...(objectChanged || assetChanged ? {
          collider: geometryDefaults(selectedAsset(next), getObjectArchetype(next.objectId).physics !== null),
          depth: geometryDefaults(selectedAsset(next), getObjectArchetype(next.objectId).physics !== null),
          occlusion: geometryDefaults(selectedAsset(next), getObjectArchetype(next.objectId).physics !== null),
        } : {}),
        visualId: objectChanged || assetChanged ? next.visualId : state.visualId,
        displayName: objectChanged || assetChanged ? next.displayName : state.displayName,
      };
      render();
      return;
    }
    if (target.matches('[data-object-authoring-toggle]')) {
      state = updateStateFromForm(state, form);
      render();
      return;
    }
    if (target.matches('[data-object-authoring-frame]')) {
      state = updateStateFromForm(state, form);
      render();
    }
  };
  dialog.addEventListener('change', changeHandler);

  const importSource = async (file: File): Promise<void> => {
    const form = dialog.querySelector<HTMLFormElement>('[data-object-authoring-form]');
    if (!form) return;
    const assetId = ((form.elements.namedItem('assetId') as HTMLSelectElement | null)?.value || `object.world.${file.name.replace(/\.png$/i, '').replace(/[^a-z0-9]+/gi, '-').toLowerCase()}`).replace(/-+$/, '');
    const frameWidth = window.prompt('Frame width in pixels', '128');
    const frameHeight = window.prompt('Frame height in pixels', '170');
    if (!frameWidth || !frameHeight) return;
    const metadata: Record<string, unknown> = {
      assetId: assetId.includes('.') ? assetId : `object.${assetId}`,
      frameWidth: integerValue(frameWidth),
      frameHeight: integerValue(frameHeight),
      kind: 'object',
      tags: ['map', 'object'],
    };
    const populatedCount = window.prompt('Populated frames (optional)', '');
    if (populatedCount?.trim()) metadata.populatedCount = integerValue(populatedCount);
    const body = new FormData();
    body.append('metadata', JSON.stringify(metadata));
    body.append('file', file, file.name);
    state = { ...state, importing: true, notice: 'Registering the PNG source…' };
    render();
    try {
      const response = await fetch('/__character-studio/asset/register', { method: 'POST', body });
      const result = await response.json() as { readonly ok?: boolean; readonly data?: { readonly assetId?: string }; readonly error?: { readonly message?: string } };
      if (!response.ok || !result.ok || !result.data?.assetId) throw new Error(result.error?.message ?? 'Source import failed');
      const assets = await fetchCatalog<CharacterStudioAssetCatalog>('/__character-studio/assets');
      const imported = assets.assets.find((entry) => entry.assetId === result.data?.assetId);
      state = { ...state, assets, assetId: imported?.assetId ?? state.assetId, frame: '0', importing: false, notice: 'Source imported. Choose its frame and finish the visual identity.' };
      render();
    } catch (error: unknown) {
      state = { ...state, importing: false, notice: error instanceof Error ? error.message : String(error) };
      render();
    }
  };

  const submitHandler = (event: SubmitEvent): void => {
    event.preventDefault();
    const form = dialog.querySelector<HTMLFormElement>('[data-object-authoring-form]');
    if (!form) return;
    state = updateStateFromForm(state, form);
    if (!state.assetId) { state = { ...state, notice: 'A registered source is required.' }; render(); return; }
    if (state.occlusionEnabled && (state.idleAnimationId || state.onHitAnimationId)) {
      state = { ...state, notice: 'Animated object visuals cannot define an occlusion region. Turn off occlusion or remove the animation hooks.' };
      render();
      return;
    }
    state = { ...state, submitting: true, notice: 'Writing the object visual definition…' };
    render();
    void fetch('/__map-editor/object-template/create', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payloadFromForm(form, state)),
    }).then(async (response) => {
      const result = await response.json() as { readonly ok?: boolean; readonly objectId?: string; readonly visualId?: string; readonly error?: string };
      if (!response.ok || !result.ok || !result.objectId || !result.visualId) throw new Error(result.error ?? 'Object creation failed');
      const url = new URL(window.location.href);
      url.searchParams.delete('studio');
      url.searchParams.set('editor', options.mapId);
      url.searchParams.set('templateObject', result.objectId);
      url.searchParams.set('templateVisual', result.visualId);
      window.location.assign(url.toString());
    }).catch((error: unknown) => {
      state = { ...state, submitting: false, notice: error instanceof Error ? error.message : String(error) };
      render();
    });
  };
  dialog.addEventListener('submit', submitHandler);

  render();
  return () => {
    host.removeEventListener('click', clickHandler);
    dialog.removeEventListener('change', changeHandler);
    dialog.removeEventListener('submit', submitHandler);
    dialog.remove();
  };
}
