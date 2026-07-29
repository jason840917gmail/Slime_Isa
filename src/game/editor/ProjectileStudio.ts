import './character-studio.css';

import type { CharacterStudioAssetCatalog, CharacterStudioAssetEntry } from '../content/characters/characterAssetCatalog';
import type { ProjectileDefinition } from '../content/projectiles/types';
import { resolveAssetUrl } from '../infrastructure/assets/assetUrls';
import { resolveCollisionShapeDimensions, type CollisionShape } from '../shared/collisionShapes';

interface ProjectileCatalogEntry extends ProjectileDefinition {
  readonly revision: string;
}

interface ProjectileCatalogResponse {
  readonly version: 1;
  readonly revision: string;
  readonly projectiles: readonly ProjectileCatalogEntry[];
}

interface ProjectileStudioState {
  readonly assets?: CharacterStudioAssetCatalog;
  readonly projectiles: readonly ProjectileCatalogEntry[];
  readonly selectedId: string;
  readonly draft?: ProjectileDefinition;
  readonly revision?: string;
  readonly dirty: boolean;
  readonly loading: boolean;
  readonly saving: boolean;
  readonly notice?: string;
}

function escapeHtml(value: unknown): string {
  return String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}

function isProjectileAsset(entry: CharacterStudioAssetEntry): boolean {
  return entry.tags.includes('projectile');
}

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function assetInfo(entry: CharacterStudioAssetEntry | undefined): { readonly url: string; readonly width: number; readonly height: number; readonly columns: number; readonly rows: number; readonly count: number } {
  if (!entry) return { url: '', width: 1, height: 1, columns: 1, rows: 1, count: 1 };
  if (!entry.frame) return { url: resolveAssetUrl(entry.sourcePath), width: entry.dimensions.width, height: entry.dimensions.height, columns: 1, rows: 1, count: 1 };
  return { url: resolveAssetUrl(entry.sourcePath), width: entry.frame.width, height: entry.frame.height, columns: entry.frame.columns, rows: entry.frame.rows, count: entry.frame.count };
}

function renderFrameTile(entry: CharacterStudioAssetEntry | undefined, frame: number, selected: boolean): string {
  const info = assetInfo(entry);
  const column = frame % info.columns;
  const row = Math.floor(frame / info.columns);
  return `<button type="button" class="studio-frame-tile${selected ? ' is-selected' : ''}" data-projectile-frame="${frame}" title="Source frame ${frame}"><span class="studio-frame-image" style="--thumb-w:${info.width}px;--thumb-h:${info.height}px;--sheet-thumb-w:${info.width * info.columns}px;--sheet-thumb-h:${info.height * info.rows}px;--sheet-offset-x:${-column * info.width}px;--sheet-offset-y:${-row * info.height}px"><img src="${escapeHtml(info.url)}" alt="" aria-hidden="true" draggable="false" /></span><small>${frame}</small></button>`;
}

function makeNewProjectile(asset: CharacterStudioAssetEntry | undefined): ProjectileDefinition {
  const info = assetInfo(asset);
  return {
    version: 1,
    projectileId: 'new-projectile',
    displayName: 'New Projectile',
    assetId: asset?.assetId ?? '',
    animation: { frames: [0], framesPerSecond: 12, loop: true, loopMode: 'wrap' },
    body: { shape: 'rectangle', width: Math.min(info.width, 16), height: Math.min(info.height, 16), centerOffsetX: 0, centerOffsetY: 0 },
    movement: { defaultSpeed: 180, lifetimeMs: 3000, rotateToVelocity: true },
  };
}

function renderAssetOption(entry: CharacterStudioAssetEntry, selectedAssetId: string): string {
  return `<option value="${escapeHtml(entry.assetId)}" ${entry.assetId === selectedAssetId ? 'selected' : ''}>${escapeHtml(entry.assetId)}</option>`;
}

function renderCollisionShapeFields(projectile: ProjectileDefinition): string {
  const shape = projectile.body.shape ?? 'rectangle';
  const radiusFields = shape === 'circle'
    ? `<label class="studio-field"><span>Radius<small>world units</small></span><input type="number" min="0.1" step="0.1" value="${projectile.body.radius ?? Math.min(projectile.body.width, projectile.body.height) / 2}" data-projectile-field="body.radius" /></label>`
    : shape === 'ellipse'
      ? `<label class="studio-field"><span>Radius X<small>world units</small></span><input type="number" min="0.1" step="0.1" value="${projectile.body.radiusX ?? projectile.body.width / 2}" data-projectile-field="body.radiusX" /></label><label class="studio-field"><span>Radius Y<small>world units</small></span><input type="number" min="0.1" step="0.1" value="${projectile.body.radiusY ?? projectile.body.height / 2}" data-projectile-field="body.radiusY" /></label>`
      : '';
  return `<div class="studio-collision-shape-row"><label class="studio-field studio-field--shape"><span>Shape<small>collision primitive</small></span><select data-projectile-field="body.shape"><option value="rectangle" ${shape === 'rectangle' ? 'selected' : ''}>Rectangle</option><option value="circle" ${shape === 'circle' ? 'selected' : ''}>Circle</option><option value="ellipse" ${shape === 'ellipse' ? 'selected' : ''}>Ellipse</option></select></label>${radiusFields}</div><p class="studio-collision-note">Circles use native Arcade Physics. Ellipses stay precise in authored hitbox math and use a conservative rectangle for world movement.</p>`;
}

function applyProjectilePreviewGeometry(container: HTMLDivElement, projectile: ProjectileDefinition): void {
  const stageBody = container.querySelector<HTMLElement>('.projectile-stage .stage-body');
  if (!stageBody) return;
  const dimensions = resolveCollisionShapeDimensions(projectile.body);
  stageBody.style.width = `${dimensions.width * 3}px`;
  stageBody.style.height = `${dimensions.height * 3}px`;
  stageBody.style.borderRadius = dimensions.shape === 'rectangle' ? '0' : '50%';
  stageBody.style.transform = `translate(-50%,-50%) translate(${projectile.body.centerOffsetX * 3}px,${projectile.body.centerOffsetY * 3}px)`;
}

function renderStudio(state: ProjectileStudioState, returnEditor: string): string {
  const projectile = state.draft;
  const projectileAssets = state.assets?.assets.filter(isProjectileAsset) ?? [];
  const source = projectileAssets.find((entry) => entry.assetId === projectile?.assetId);
  const info = assetInfo(source);
  const animation = projectile?.animation ?? { frames: [0], framesPerSecond: 12, loop: true, loopMode: 'wrap' as const };
  const previewFrame = animation.frames[0] ?? 0;
  const previewColumn = previewFrame % info.columns;
  const previewRow = Math.floor(previewFrame / info.columns);
  return `<main class="character-studio projectile-studio" data-projectile-studio>
    <header class="studio-topbar"><a class="studio-brand" href="?" aria-label="Back to game"><span class="brand-mark">✦</span><span><small>FIELD CARTOGRAPHER</small><strong>PROJECTILE STUDIO</strong></span></a><div class="studio-topbar-actions"><span class="studio-save-state${state.notice ? ' is-error' : ''}"><i></i>${escapeHtml(state.notice ?? (state.loading ? 'Loading catalog…' : state.dirty ? 'Unsaved projectile' : 'Saved library'))}</span><button type="button" class="studio-button studio-button--save" data-action="save-projectile" ${!projectile || !state.dirty || state.saving ? 'disabled' : ''}>${state.saving ? 'SAVING…' : 'SAVE PROJECTILE'}</button></div></header>
    <div class="studio-layout">
      <aside class="studio-library"><div class="studio-panel-title"><div><span class="studio-kicker">Reusable assets</span><h1>Projectiles</h1></div><span class="studio-count">${String(state.projectiles.length).padStart(2, '0')}</span></div><div class="studio-roster" data-projectile-roster>${state.projectiles.map((entry) => `<button type="button" class="studio-roster-item${entry.projectileId === state.selectedId ? ' is-active' : ''}" data-projectile-id="${escapeHtml(entry.projectileId)}"><span class="roster-glyph enemy">◆</span><span><strong>${escapeHtml(entry.displayName)}</strong><small>${escapeHtml(entry.projectileId)}</small></span><em>${entry.projectileId === state.selectedId ? 'OPEN' : ''}</em></button>`).join('')}</div><div class="studio-library-footer"><button type="button" class="studio-button studio-button--outline studio-button--create" data-action="new-projectile">NEW PROJECTILE</button><a class="studio-button studio-button--outline studio-button--navigation" href="?studio=characters&editor=${encodeURIComponent(returnEditor)}">↗ CHARACTER STUDIO</a></div></aside>
      <section class="studio-workbench"><div class="studio-workbench-heading"><div><span class="studio-kicker">Reusable projectile profile</span><h2>${escapeHtml(projectile?.displayName ?? 'Projectile library')}</h2></div><div class="studio-workbench-meta"><span>PROFILE <b>${escapeHtml(projectile?.projectileId ?? '—')}</b></span><span>ASSET <b>${escapeHtml(projectile?.assetId ?? '—')}</b></span><span>FRAMES <b>${info.count}</b></span></div></div>
        ${projectile ? `<section class="studio-preview-card"><div class="studio-preview-toolbar"><span class="studio-kicker">FLIGHT PREVIEW</span><span class="studio-muted">Frame ${previewFrame} · ${info.width} × ${info.height} px</span></div><div class="studio-stage projectile-stage"><span class="stage-axis stage-axis-x"></span><span class="stage-axis stage-axis-y"></span><span class="stage-anchor">+</span><span class="stage-body" style="width:${projectile.body.width * 3}px;height:${projectile.body.height * 3}px;transform:translate(-50%,-50%) translate(${projectile.body.centerOffsetX * 3}px,${projectile.body.centerOffsetY * 3}px)"></span><span class="stage-sprite" style="--sheet-url:url('${escapeHtml(info.url)}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:${previewColumn * info.width}px;--frame-y:${previewRow * info.height}px;--preview-scale:2.8"></span><span class="stage-caption"><b>${escapeHtml(projectile.displayName)}</b><span>${projectile.movement.defaultSpeed} WORLD UNITS/S · ${projectile.movement.lifetimeMs} MS LIFETIME</span></span></div></section>
        <section class="studio-inspector projectile-inspector"><div class="studio-inspector-scroll"><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Identity</span><strong>Reusable profile</strong></div><div class="studio-field-grid"><label class="studio-field"><span>Stable ID<small>lowercase</small></span><input type="text" value="${escapeHtml(projectile.projectileId)}" data-projectile-field="projectileId" /></label><label class="studio-field"><span>Display name<small>library label</small></span><input type="text" value="${escapeHtml(projectile.displayName)}" data-projectile-field="displayName" /></label></div><label class="studio-field studio-field--wide"><span>Source asset<small>projectile-tagged manifest source</small></span><select data-projectile-field="assetId"><option value="">Choose projectile source</option>${projectileAssets.map((entry) => renderAssetOption(entry, String(projectile.assetId))).join('')}</select></label></section><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Animation</span><strong>Frame sequence</strong></div><p class="studio-help">Choose frames from the source sheet, then author their order here. Runtime playback supports wrap and ping-pong loops.</p><div class="studio-sheet-grid projectile-frame-grid">${Array.from({ length: info.count }, (_, frame) => renderFrameTile(source, frame, animation.frames.includes(frame))).join('')}</div><label class="studio-field studio-field--wide"><span>Timeline frames<small>comma-separated source IDs</small></span><input type="text" value="${escapeHtml(animation.frames.join(', '))}" data-projectile-field="animation.frames" /></label><div class="studio-field-grid"><label class="studio-field"><span>FPS<small>frames / second</small></span><input type="number" min="0.1" max="240" step="0.5" value="${animation.framesPerSecond}" data-projectile-field="animation.framesPerSecond" /></label><label class="studio-field"><span>Loop mode<small>playback</small></span><select data-projectile-field="animation.loopMode"><option value="wrap" ${animation.loopMode !== 'ping-pong' ? 'selected' : ''}>Wrap</option><option value="ping-pong" ${animation.loopMode === 'ping-pong' ? 'selected' : ''}>Ping-pong</option></select></label></div><label class="studio-toggle-field"><input type="checkbox" data-projectile-field="animation.loop" ${animation.loop ? 'checked' : ''} /><span><strong>Loop animation</strong><small>Keep the projectile visual moving during flight</small></span></label></section><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Physics</span><strong>Flight and collision</strong></div><div class="studio-field-grid"><label class="studio-field"><span>Body width<small>world units</small></span><input type="number" min="0.1" step="0.1" value="${projectile.body.width}" data-projectile-field="body.width" /></label><label class="studio-field"><span>Body height<small>world units</small></span><input type="number" min="0.1" step="0.1" value="${projectile.body.height}" data-projectile-field="body.height" /></label><label class="studio-field"><span>Center X<small>world units</small></span><input type="number" step="0.1" value="${projectile.body.centerOffsetX}" data-projectile-field="body.centerOffsetX" /></label><label class="studio-field"><span>Center Y<small>world units</small></span><input type="number" step="0.1" value="${projectile.body.centerOffsetY}" data-projectile-field="body.centerOffsetY" /></label><label class="studio-field"><span>Default speed<small>world units/s</small></span><input type="number" min="0.1" step="1" value="${projectile.movement.defaultSpeed}" data-projectile-field="movement.defaultSpeed" /></label><label class="studio-field"><span>Lifetime<small>milliseconds</small></span><input type="number" min="1" step="1" value="${projectile.movement.lifetimeMs}" data-projectile-field="movement.lifetimeMs" /></label></div><label class="studio-toggle-field"><input type="checkbox" data-projectile-field="movement.rotateToVelocity" ${projectile.movement.rotateToVelocity ? 'checked' : ''} /><span><strong>Rotate toward velocity</strong><small>Orient the projectile along its flight direction</small></span></label></section></div></section>` : '<section class="studio-empty-state"><span class="studio-loading-orb">✦</span><h2>Select or create a projectile</h2><p>Reusable projectile profiles keep art, animation, and flight behavior in one shared library.</p></section>'}
      </section>
    </div>
  </main>`;
}

async function loadJson<T>(url: string): Promise<T> {
  const response = await fetch(url);
  const payload = await response.json() as { ok: boolean; data?: T; error?: { message?: string } };
  if (!response.ok || !payload.ok || !payload.data) throw new Error(payload.error?.message ?? 'Projectile studio request failed');
  return payload.data;
}

export function mountProjectileStudio(container: HTMLDivElement): () => void {
  container.classList.add('is-character-studio-host');
  let state: ProjectileStudioState = { projectiles: [], selectedId: '', dirty: false, loading: true, saving: false };
  const returnEditor = new URLSearchParams(window.location.search).get('editor') ?? 'meadow-crossing';
  const render = (): void => {
    container.innerHTML = renderStudio(state, returnEditor);
    if (!state.draft) return;
    const physicsSection = container.querySelectorAll<HTMLElement>('.projectile-inspector .studio-inspector-section')[2];
    const heading = physicsSection?.querySelector('.studio-section-heading');
    if (heading) heading.insertAdjacentHTML('afterend', renderCollisionShapeFields(state.draft));
    applyProjectilePreviewGeometry(container, state.draft);
  };
  const select = (projectile: ProjectileDefinition, revision?: string): void => {
    state = { ...state, selectedId: projectile.projectileId, draft: clone(projectile), revision, dirty: false, notice: undefined };
    render();
  };
  const load = async (): Promise<void> => {
    try {
      const [assets, catalog] = await Promise.all([
        loadJson<CharacterStudioAssetCatalog>('/__character-studio/assets'),
        loadJson<ProjectileCatalogResponse>('/__character-studio/projectiles'),
      ]);
      const first = catalog.projectiles[0];
      state = { ...state, assets, projectiles: catalog.projectiles, selectedId: first?.projectileId ?? '', loading: false };
      if (first) select(first, first.revision);
      else render();
    } catch (error) {
      state = { ...state, loading: false, notice: error instanceof Error ? error.message : String(error) };
      render();
    }
  };
  const updateDraft = (path: string, rawValue: string | boolean): void => {
    if (!state.draft) return;
    const draft = clone(state.draft) as {
      version: 1;
      projectileId: string;
      displayName: string;
      assetId: string;
      animation: { frames: number[]; framesPerSecond: number; loop: boolean; loopMode?: 'wrap' | 'ping-pong' };
      body: { shape?: CollisionShape; width: number; height: number; radius?: number; radiusX?: number; radiusY?: number; centerOffsetX: number; centerOffsetY: number };
      movement: { defaultSpeed: number; lifetimeMs: number; rotateToVelocity: boolean };
    };
    draft.animation ??= { frames: [0], framesPerSecond: 12, loop: true, loopMode: 'wrap' };
    const numericPaths = new Set(['animation.framesPerSecond', 'body.width', 'body.height', 'body.radius', 'body.radiusX', 'body.radiusY', 'body.centerOffsetX', 'body.centerOffsetY', 'movement.defaultSpeed', 'movement.lifetimeMs']);
    const value: string | number | boolean = numericPaths.has(path) ? Number(rawValue) : rawValue;
    if (path === 'animation.frames') draft.animation.frames = String(rawValue).split(',').map((entry) => Number(entry.trim())).filter((entry) => Number.isInteger(entry) && entry >= 0);
    else if (path === 'animation.framesPerSecond') draft.animation.framesPerSecond = Number(value);
    else if (path === 'animation.loop') draft.animation.loop = Boolean(value);
    else if (path === 'animation.loopMode') draft.animation.loopMode = value === 'ping-pong' ? 'ping-pong' : 'wrap';
    else if (path === 'body.shape') {
      const shape: CollisionShape = value === 'circle' || value === 'ellipse' ? value : 'rectangle';
      draft.body.shape = shape;
      if (shape === 'circle') {
        draft.body.radius ??= Math.min(draft.body.width, draft.body.height) / 2;
        delete draft.body.radiusX;
        delete draft.body.radiusY;
      } else if (shape === 'ellipse') {
        draft.body.radiusX ??= draft.body.width / 2;
        draft.body.radiusY ??= draft.body.height / 2;
        delete draft.body.radius;
      } else {
        delete draft.body.radius;
        delete draft.body.radiusX;
        delete draft.body.radiusY;
      }
    }
    else if (path === 'body.width') draft.body.width = Number(value);
    else if (path === 'body.height') draft.body.height = Number(value);
    else if (path === 'body.radius') draft.body.radius = Number(value);
    else if (path === 'body.radiusX') draft.body.radiusX = Number(value);
    else if (path === 'body.radiusY') draft.body.radiusY = Number(value);
    else if (path === 'body.centerOffsetX') draft.body.centerOffsetX = Number(value);
    else if (path === 'body.centerOffsetY') draft.body.centerOffsetY = Number(value);
    else if (path === 'movement.defaultSpeed') draft.movement.defaultSpeed = Number(value);
    else if (path === 'movement.lifetimeMs') draft.movement.lifetimeMs = Number(value);
    else if (path === 'movement.rotateToVelocity') draft.movement.rotateToVelocity = Boolean(value);
    else if (path === 'projectileId') draft.projectileId = String(value).trim().toLowerCase();
    else if (path === 'displayName') draft.displayName = String(value);
    else if (path === 'assetId') draft.assetId = String(value);
    state = { ...state, draft, selectedId: draft.projectileId, dirty: true, notice: undefined };
  };
  const save = async (): Promise<void> => {
    if (!state.draft || !state.dirty) return;
    state = { ...state, saving: true, notice: 'Saving projectile…' };
    render();
    const isNew = !state.projectiles.some((entry) => entry.projectileId === state.draft?.projectileId);
    try {
      const response = await fetch(`/__character-studio/projectile/${isNew ? 'create' : 'update'}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ projectile: state.draft, ...(isNew ? {} : { expectedRevision: state.revision }) }) });
      const payload = await response.json() as { ok: boolean; data?: { projectile: ProjectileDefinition; revision: string }; error?: { message?: string } };
      if (!response.ok || !payload.ok || !payload.data) throw new Error(payload.error?.message ?? 'Projectile save failed');
      const next = state.projectiles.filter((entry) => entry.projectileId !== payload.data?.projectile.projectileId).concat({ ...payload.data.projectile, revision: payload.data.revision });
      state = { ...state, projectiles: next, selectedId: payload.data.projectile.projectileId, draft: clone(payload.data.projectile), revision: payload.data.revision, dirty: false, saving: false, notice: 'Saved projectile' };
      render();
    } catch (error) {
      state = { ...state, saving: false, notice: error instanceof Error ? error.message : String(error) };
      render();
    }
  };
  const onClick = (event: MouseEvent): void => {
    const target = event.target as HTMLElement;
    const frameButton = target.closest<HTMLElement>('[data-projectile-frame]');
    if (frameButton && state.draft) {
      const frame = Number(frameButton.dataset.projectileFrame);
      const frames = [...(state.draft.animation?.frames ?? [0])];
      const nextFrames = frames.includes(frame) ? frames.filter((candidate) => candidate !== frame) : [...frames, frame];
      updateDraft('animation.frames', nextFrames.join(', '));
      render();
      return;
    }
    const projectileButton = target.closest<HTMLElement>('[data-projectile-id]');
    if (projectileButton) {
      const entry = state.projectiles.find((candidate) => candidate.projectileId === projectileButton.dataset.projectileId);
      if (entry) select(entry, entry.revision);
      return;
    }
    const action = target.closest<HTMLElement>('[data-action]')?.dataset.action;
    if (action === 'new-projectile') {
      const asset = state.assets?.assets.find(isProjectileAsset);
      select(makeNewProjectile(asset));
      return;
    }
    if (action === 'save-projectile') void save();
  };
  const onInput = (event: Event): void => {
    const target = event.target as HTMLInputElement | HTMLSelectElement;
    const path = target.dataset.projectileField;
    if (!path) return;
    updateDraft(path, target instanceof HTMLInputElement && target.type === 'checkbox' ? target.checked : target.value);
    if (target instanceof HTMLSelectElement || (target instanceof HTMLInputElement && target.type === 'checkbox')) render();
  };
  container.addEventListener('click', onClick);
  container.addEventListener('change', onInput);
  container.addEventListener('input', onInput);
  render();
  void load();
  return () => {
    container.removeEventListener('click', onClick);
    container.removeEventListener('change', onInput);
    container.removeEventListener('input', onInput);
    container.classList.remove('is-character-studio-host');
  };
}
