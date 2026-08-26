import './character-studio.css';

import type { CharacterStudioAssetCatalog, CharacterStudioAssetEntry } from '../content/characters/characterAssetCatalog';
import type { ProjectileAnimationDocument, ProjectileAnimationSet, ProjectileDefinition, ProjectileVisualDocument } from '../content/projectiles/types';
import { ensureStudioModeTabs } from './StudioModeTabs';
import { resolveAssetUrl } from '../infrastructure/assets/assetUrls';
import { resolveCollisionShapeDimensions, type CollisionShape } from '../shared/collisionShapes';

type ProjectileAnimationId = 'move' | 'impact';

interface ProjectileCatalogEntry extends ProjectileDefinition {
  readonly revision: string;
}

interface ProjectileCatalogResponse {
  readonly version: 1;
  readonly revision: string;
  readonly projectiles: readonly ProjectileCatalogEntry[];
}

interface ProjectileImportForm {
  readonly assetId: string;
  readonly frameWidth: string;
  readonly frameHeight: string;
  readonly populatedCount: string;
}

interface ProjectileStudioState {
  readonly assets?: CharacterStudioAssetCatalog;
  readonly projectiles: readonly ProjectileCatalogEntry[];
  readonly selectedId: string;
  readonly selectedAnimation: ProjectileAnimationId;
  readonly selectedPreviewFrame: number;
  readonly draft?: ProjectileDefinition;
  readonly revision?: string;
  readonly dirty: boolean;
  readonly loading: boolean;
  readonly saving: boolean;
  readonly assetShelfOpen: boolean;
  readonly importing: boolean;
  readonly importForm: ProjectileImportForm;
  readonly notice?: string;
}

function escapeHtml(value: unknown): string {
  return String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}

function integerValue(value: unknown, fallback = 0): number {
  const numeric = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(numeric) ? Math.round(numeric) : fallback;
}

function integerInputValue(value: unknown, fallback = 0): string {
  return String(integerValue(value, fallback));
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

function defaultProjectileAnimations(info: ReturnType<typeof assetInfo>): ProjectileAnimationSet {
  const moveFrames = info.count > 1 ? [0, 1] : [0];
  const impactFrame = info.count > 1 ? info.count - 1 : 0;
  return {
    move: { frames: moveFrames, framesPerSecond: 12, loop: true, loopMode: 'wrap' },
    impact: { frames: [impactFrame], framesPerSecond: 12, loop: false, loopMode: 'wrap' },
  };
}

function projectileAnimations(projectile: ProjectileDefinition | undefined): ProjectileAnimationSet {
  const fallback = defaultProjectileAnimations({ url: '', width: 1, height: 1, columns: 1, rows: 1, count: 1 });
  const legacy = projectile?.animation;
  const move = projectile?.animations?.move ?? legacy ?? fallback.move;
  const impact = projectile?.animations?.impact ?? {
    frames: [legacy?.frames.at(-1) ?? move.frames.at(-1) ?? 0],
    framesPerSecond: legacy?.framesPerSecond ?? move.framesPerSecond,
    loop: false,
    loopMode: 'wrap' as const,
  };
  return { move: clone(move), impact: clone(impact) };
}

function projectileAnimationsForFrameCount(projectile: ProjectileDefinition, frameCount: number): ProjectileAnimationSet {
  const lastFrame = Math.max(frameCount - 1, 0);
  const animations = projectileAnimations(projectile);
  const clamp = (clip: ProjectileAnimationDocument): ProjectileAnimationDocument => {
    const frames = clip.frames.map((frame) => Math.max(0, Math.min(integerValue(frame), lastFrame)));
    return { ...clip, frames: frames.length > 0 ? frames : [0] };
  };
  return { move: clamp(animations.move), impact: clamp(animations.impact) };
}

function projectileVisual(projectile: ProjectileDefinition | undefined): ProjectileVisualDocument {
  const sourceOffset = projectile?.visual?.sourceOffset ?? [0, 0];
  const frameOffsets = projectile?.visual?.frameOffsets ?? {};
  return {
    sourceOffset: [integerValue(sourceOffset[0]), integerValue(sourceOffset[1])] as [number, number],
    frameOffsets: clone(frameOffsets),
  };
}

function projectileVisualOffset(projectile: ProjectileDefinition | undefined, frame: number): readonly [number, number] {
  const visual = projectileVisual(projectile);
  const override = visual.frameOffsets?.[String(frame)];
  return override ?? visual.sourceOffset;
}

function renderFrameTile(entry: CharacterStudioAssetEntry | undefined, frame: number, selected: boolean): string {
  const info = assetInfo(entry);
  const column = frame % info.columns;
  const row = Math.floor(frame / info.columns);
  return `<button type="button" class="studio-frame-tile${selected ? ' is-selected' : ''}" data-projectile-frame="${frame}" title="Source frame ${frame}"><span class="studio-frame-image" style="--thumb-w:${info.width}px;--thumb-h:${info.height}px;--sheet-thumb-w:${info.width * info.columns}px;--sheet-thumb-h:${info.height * info.rows}px;--sheet-offset-x:${-column * info.width}px;--sheet-offset-y:${-row * info.height}px"><img src="${escapeHtml(info.url)}" alt="" aria-hidden="true" draggable="false" /></span><small>${frame}</small></button>`;
}

function renderAssetCard(entry: CharacterStudioAssetEntry, selected: boolean): string {
  const info = assetInfo(entry);
  const previewStyle = entry.frame
    ? `--sheet-url:url('${escapeHtml(info.url)}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:0px;--frame-y:0px`
    : `--sheet-url:url('${escapeHtml(info.url)}')`;
  const detail = entry.frame ? `${info.columns} x ${info.rows} x ${info.count} FRAMES` : `${info.width} x ${info.height} PX`;
  return `<button type="button" class="studio-asset-card${selected ? ' is-selected' : ''}" data-action="select-projectile-asset" data-projectile-asset-id="${escapeHtml(entry.assetId)}" aria-pressed="${selected}"><span class="studio-asset-card-preview${entry.frame ? ' is-sheet' : ''}" style="${previewStyle}"></span><span class="studio-asset-card-copy"><strong>${escapeHtml(entry.assetId)}</strong><small>${entry.kind.toUpperCase()} · ${entry.characterIds.length > 0 ? `USED BY ${entry.characterIds.length}` : 'UNUSED SOURCE'}</small><em>${detail}</em></span></button>`;
}

function renderAssetShelf(state: ProjectileStudioState): string {
  if (!state.assetShelfOpen) return '';
  const assets = state.assets?.assets.filter(isProjectileAsset) ?? [];
  const currentAssetId = state.draft?.assetId ?? '';
  return `<div class="studio-asset-shelf-backdrop" data-projectile-shelf-backdrop><section class="studio-asset-shelf" role="dialog" aria-modal="true" aria-labelledby="projectile-source-library-title" data-projectile-shelf-panel><header class="studio-asset-shelf-heading"><div><span class="studio-kicker">Projectile source library</span><h2 id="projectile-source-library-title">Select or import a sheet</h2><p>Choose a registered projectile source or import a PNG spritesheet for this profile.</p></div><button type="button" class="studio-icon-button" data-action="close-projectile-source-library" aria-label="Close source library">X</button></header><div class="studio-asset-shelf-grid">${assets.map((entry) => renderAssetCard(entry, entry.assetId === currentAssetId)).join('') || '<p class="studio-empty-note">No projectile-tagged source sheets are registered yet.</p>'}</div><section class="studio-asset-create-panel"><div class="studio-asset-create-heading"><span><span class="studio-kicker">Import source</span><strong>PNG spritesheet</strong></span><span class="studio-asset-create-status">${escapeHtml(state.notice ?? 'Frame dimensions must divide the PNG evenly.')}</span></div><div class="studio-asset-create-fields"><label class="studio-create-field"><span>Asset ID</span><input type="text" value="${escapeHtml(state.importForm.assetId)}" data-projectile-import-field="assetId" placeholder="projectile.enemy.spark" /></label><label class="studio-create-field"><span>Frame width</span><input type="number" min="1" step="1" inputmode="numeric" value="${escapeHtml(state.importForm.frameWidth)}" data-projectile-import-field="frameWidth" /></label><label class="studio-create-field"><span>Frame height</span><input type="number" min="1" step="1" inputmode="numeric" value="${escapeHtml(state.importForm.frameHeight)}" data-projectile-import-field="frameHeight" /></label><label class="studio-create-field"><span>Populated frames</span><input type="number" min="1" step="1" inputmode="numeric" value="${escapeHtml(state.importForm.populatedCount)}" data-projectile-import-field="populatedCount" placeholder="Full grid" /></label></div><div class="studio-asset-create-actions"><input type="file" accept="image/png" data-projectile-upload hidden /><button type="button" class="studio-button studio-button--save" data-action="upload-projectile-source" ${state.importing ? 'disabled' : ''}>${state.importing ? 'IMPORTING...' : 'IMPORT PNG + USE'}</button><button type="button" class="studio-button studio-button--quiet" data-action="close-projectile-source-library">CANCEL</button></div></section><footer class="studio-asset-shelf-footer"><span>${currentAssetId ? `CURRENT <b>${escapeHtml(currentAssetId)}</b>` : 'No source selected'}</span><small>Imported sources are tagged for Projectile Studio and available to future profiles.</small></footer></section></div>`;
}

function makeNewProjectile(asset: CharacterStudioAssetEntry | undefined, existingIds: ReadonlySet<string> = new Set()): ProjectileDefinition {
  const info = assetInfo(asset);
  let projectileId = 'new-projectile';
  let copyNumber = 2;
  while (existingIds.has(projectileId)) projectileId = `new-projectile-${copyNumber++}`;
  return {
    version: 1,
    projectileId,
    displayName: copyNumber === 2 ? 'New Projectile' : `New Projectile ${copyNumber - 1}`,
    assetId: asset?.assetId ?? '',
    animations: defaultProjectileAnimations(info),
    visual: { sourceOffset: [0, 0], frameOffsets: {} },
    body: { shape: 'rectangle', width: Math.max(1, Math.min(info.width, 16)), height: Math.max(1, Math.min(info.height, 16)), centerOffsetX: 0, centerOffsetY: 0 },
    movement: { defaultSpeed: 180, lifetimeMs: 3000, rotateToVelocity: true },
  };
}

function renderAssetOption(entry: CharacterStudioAssetEntry, selectedAssetId: string): string {
  return `<option value="${escapeHtml(entry.assetId)}" ${entry.assetId === selectedAssetId ? 'selected' : ''}>${escapeHtml(entry.assetId)}</option>`;
}

function renderCollisionShapeFields(projectile: ProjectileDefinition): string {
  const shape = projectile.body.shape ?? 'rectangle';
  const radiusFields = shape === 'circle'
    ? `<label class="studio-field"><span>Radius<small>world units</small></span><input type="number" min="1" step="1" inputmode="numeric" value="${integerInputValue(projectile.body.radius ?? Math.min(projectile.body.width, projectile.body.height) / 2, 1)}" data-projectile-field="body.radius" /></label>`
    : shape === 'ellipse'
      ? `<label class="studio-field"><span>Radius X<small>world units</small></span><input type="number" min="1" step="1" inputmode="numeric" value="${integerInputValue(projectile.body.radiusX ?? projectile.body.width / 2, 1)}" data-projectile-field="body.radiusX" /></label><label class="studio-field"><span>Radius Y<small>world units</small></span><input type="number" min="1" step="1" inputmode="numeric" value="${integerInputValue(projectile.body.radiusY ?? projectile.body.height / 2, 1)}" data-projectile-field="body.radiusY" /></label>`
      : '';
  return `<div class="studio-collision-shape-row"><label class="studio-field studio-field--shape"><span>Shape<small>collision primitive</small></span><select data-projectile-field="body.shape"><option value="rectangle" ${shape === 'rectangle' ? 'selected' : ''}>Rectangle</option><option value="circle" ${shape === 'circle' ? 'selected' : ''}>Circle</option><option value="ellipse" ${shape === 'ellipse' ? 'selected' : ''}>Ellipse</option></select></label>${radiusFields}</div><p class="studio-collision-note">Circles use native Arcade Physics. Ellipses stay precise in authored hitbox math and use a conservative rectangle for world movement.</p>`;
}

function renderProjectileVisualFields(projectile: ProjectileDefinition, frame: number): string {
  const visual = projectileVisual(projectile);
  const offset = projectileVisualOffset(projectile, frame);
  const hasOverride = Boolean(visual.frameOffsets?.[String(frame)]);
  return `<section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Visual</span><strong>Artwork alignment</strong></div><p class="studio-help">Artwork shifts around the fixed world anchor. It never moves or resizes the collision body.</p><div class="studio-field-grid"><label class="studio-field"><span>Default offset X<small>source pixels</small></span><input type="number" step="1" inputmode="numeric" value="${integerInputValue(visual.sourceOffset[0])}" data-projectile-field="visual.sourceOffset.0" /></label><label class="studio-field"><span>Default offset Y<small>source pixels</small></span><input type="number" step="1" inputmode="numeric" value="${integerInputValue(visual.sourceOffset[1])}" data-projectile-field="visual.sourceOffset.1" /></label></div><div class="studio-subheading">Frame ${frame} override <button type="button" class="studio-link-button" data-action="reset-projectile-frame-visual" ${hasOverride ? '' : 'disabled'}>reset</button></div><div class="studio-field-grid"><label class="studio-field"><span>Offset X<small>${hasOverride ? 'source pixels' : 'uses default'}</small></span><input type="number" step="1" inputmode="numeric" value="${integerInputValue(offset[0])}" data-projectile-field="visual.frameOffsets.${frame}.0" /></label><label class="studio-field"><span>Offset Y<small>${hasOverride ? 'source pixels' : 'uses default'}</small></span><input type="number" step="1" inputmode="numeric" value="${integerInputValue(offset[1])}" data-projectile-field="visual.frameOffsets.${frame}.1" /></label></div></section>`;
}

function applyProjectilePreviewGeometry(container: HTMLDivElement, projectile: ProjectileDefinition, previewFrame = 0): void {
  const stageBody = container.querySelector<HTMLElement>('.projectile-stage .stage-body');
  if (stageBody) {
    const dimensions = resolveCollisionShapeDimensions(projectile.body);
    stageBody.style.width = `${dimensions.width * 3}px`;
    stageBody.style.height = `${dimensions.height * 3}px`;
    stageBody.style.borderRadius = dimensions.shape === 'rectangle' ? '0' : '50%';
    stageBody.style.transform = `translate(-50%,-50%) translate(${projectile.body.centerOffsetX * 3}px,${projectile.body.centerOffsetY * 3}px)`;
  }
  const stageSprite = container.querySelector<HTMLElement>('.projectile-stage .stage-sprite');
  if (stageSprite) {
    const [offsetX, offsetY] = projectileVisualOffset(projectile, previewFrame);
    stageSprite.style.setProperty('--offset-x', `${offsetX * 2.2}px`);
    stageSprite.style.setProperty('--offset-y', `${offsetY * 2.2}px`);
  }
}

function reflowProjectileStudio(container: HTMLDivElement): void {
  const layout = container.querySelector<HTMLElement>('.studio-layout');
  const workbench = container.querySelector<HTMLElement>('.projectile-studio .studio-workbench');
  const inspector = container.querySelector<HTMLElement>('.projectile-inspector');
  const animation = inspector?.querySelector<HTMLElement>('.studio-inspector-section:nth-child(2)');
  if (!layout || !workbench || !inspector || !animation) return;
  if (!inspector.querySelector('.studio-inspector-heading')) inspector.insertAdjacentHTML('afterbegin', '<div class="studio-inspector-heading"><span class="studio-kicker">Inspector</span><h2>Projectile controls</h2><p>Identity, visual alignment, and flight physics</p></div>');
  workbench.append(animation);
  layout.append(inspector);
}

function renderStudio(state: ProjectileStudioState, returnEditor: string): string {
  const projectile = state.draft;
  const projectileAssets = state.assets?.assets.filter(isProjectileAsset) ?? [];
  const source = projectileAssets.find((entry) => entry.assetId === projectile?.assetId);
  const info = assetInfo(source);
  const animations = projectileAnimations(projectile);
  const animation = animations[state.selectedAnimation];
  const previewFrame = animation.frames.includes(state.selectedPreviewFrame) ? state.selectedPreviewFrame : animation.frames[0] ?? 0;
  const previewColumn = previewFrame % info.columns;
  const previewRow = Math.floor(previewFrame / info.columns);
  const animationPath = `animations.${state.selectedAnimation}`;
  return `<main class="character-studio projectile-studio" data-projectile-studio>
    <header class="studio-topbar"><a class="studio-brand" href="?" aria-label="Back to game"><span class="brand-mark">*</span><span><small>FIELD CARTOGRAPHER</small><strong>PROJECTILE STUDIO</strong></span></a><div class="studio-topbar-actions"><span class="studio-save-state${state.notice ? ' is-error' : ''}"><i></i>${escapeHtml(state.notice ?? (state.loading ? 'Loading catalog...' : state.dirty ? 'Unsaved projectile' : 'Saved library'))}</span><button type="button" class="studio-button studio-button--save" data-action="save-projectile" ${!projectile || !state.dirty || state.saving ? 'disabled' : ''}>${state.saving ? 'SAVING...' : 'SAVE PROJECTILE'}</button></div></header>
    <div class="studio-layout">
      <aside class="studio-library"><div class="studio-panel-title"><div><span class="studio-kicker">Reusable assets</span><h1>Projectiles</h1></div><span class="studio-count">${String(state.projectiles.length).padStart(2, '0')}</span></div><div class="studio-roster" data-projectile-roster>${state.projectiles.map((entry) => `<button type="button" class="studio-roster-item${entry.projectileId === state.selectedId ? ' is-active' : ''}" data-projectile-id="${escapeHtml(entry.projectileId)}"><span class="roster-glyph enemy">*</span><span><strong>${escapeHtml(entry.displayName)}</strong><small>${escapeHtml(entry.projectileId)}</small></span><em>${entry.projectileId === state.selectedId ? 'OPEN' : ''}</em></button>`).join('')}</div><div class="studio-library-footer"><button type="button" class="studio-button studio-button--outline studio-button--create" data-action="new-projectile">NEW PROJECTILE</button><a class="studio-button studio-button--outline studio-button--navigation" href="?studio=characters&editor=${encodeURIComponent(returnEditor)}">OPEN CHARACTER STUDIO</a></div></aside>
      <section class="studio-workbench"><div class="studio-workbench-heading"><div><span class="studio-kicker">Reusable projectile profile</span><h2>${escapeHtml(projectile?.displayName ?? 'Projectile library')}</h2></div><div class="studio-workbench-meta"><span>PROFILE <b>${escapeHtml(projectile?.projectileId ?? '-')}</b></span><span>ASSET <b>${escapeHtml(projectile?.assetId ?? '-')}</b></span><span>FRAMES <b>${info.count}</b></span></div></div>
        ${projectile ? `<section class="studio-preview-card"><div class="studio-preview-toolbar"><span class="studio-kicker">PROJECTILE PREVIEW</span><span class="studio-muted">${state.selectedAnimation.toUpperCase()} · frame ${previewFrame} · ${info.width} x ${info.height} px</span></div><div class="studio-stage projectile-stage"><span class="stage-axis stage-axis-x"></span><span class="stage-axis stage-axis-y"></span><span class="stage-anchor">+</span><span class="stage-label">WORLD ANCHOR</span><span class="stage-body" style="width:${projectile.body.width * 3}px;height:${projectile.body.height * 3}px;transform:translate(-50%,-50%) translate(${projectile.body.centerOffsetX * 3}px,${projectile.body.centerOffsetY * 3}px)"></span><span class="stage-sprite" style="--sheet-url:url('${escapeHtml(info.url)}');--frame-w:${info.width}px;--frame-h:${info.height}px;--sheet-w:${info.width * info.columns}px;--sheet-h:${info.height * info.rows}px;--frame-x:${previewColumn * info.width}px;--frame-y:${previewRow * info.height}px;--preview-scale:2.8"></span><span class="stage-caption"><b>${escapeHtml(projectile.displayName)}</b><span>${projectile.movement.defaultSpeed} WORLD UNITS/S · ${projectile.movement.lifetimeMs} MS LIFETIME</span></span></div></section>
        <section class="studio-inspector projectile-inspector"><div class="studio-inspector-scroll"><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Identity</span><strong>Reusable profile</strong></div><div class="studio-field-grid"><label class="studio-field"><span>Stable ID<small>lowercase</small></span><input type="text" value="${escapeHtml(projectile.projectileId)}" data-projectile-field="projectileId" /></label><label class="studio-field"><span>Display name<small>library label</small></span><input type="text" value="${escapeHtml(projectile.displayName)}" data-projectile-field="displayName" /></label></div><label class="studio-field studio-field--wide"><span>Source asset<small>projectile-tagged manifest source</small></span><div class="studio-source-picker"><select data-projectile-field="assetId"><option value="">Choose projectile source</option>${projectileAssets.map((entry) => renderAssetOption(entry, String(projectile.assetId))).join('')}</select><button type="button" class="studio-button studio-button--quiet" data-action="open-projectile-source-library">SOURCE LIBRARY</button></div></label></section><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Animation tracks</span><strong>Move and impact</strong></div><p class="studio-help">Author the looping flight clip and the one-shot clip shown when the projectile hits a target or solid world.</p><div class="studio-clip-tabs">${(['move', 'impact'] as const).map((animationId) => `<button type="button" class="studio-clip-tab${state.selectedAnimation === animationId ? ' is-active' : ''}" data-projectile-animation-id="${animationId}"><span>${animationId === 'move' ? 'MOVE' : 'IMPACT'}</span><small>${animations[animationId].frames.length}F</small></button>`).join('')}</div><div class="studio-sheet-grid projectile-frame-grid">${Array.from({ length: info.count }, (_, frame) => renderFrameTile(source, frame, animation.frames.includes(frame))).join('')}</div><label class="studio-field studio-field--wide"><span>${state.selectedAnimation.toUpperCase()} frames<small>comma-separated source IDs</small></span><input type="text" value="${escapeHtml(animation.frames.join(', '))}" data-projectile-field="${animationPath}.frames" /></label><div class="studio-field-grid"><label class="studio-field"><span>FPS<small>frames / second</small></span><input type="number" min="1" max="240" step="1" inputmode="numeric" value="${integerInputValue(animation.framesPerSecond, 1)}" data-projectile-field="${animationPath}.framesPerSecond" /></label><label class="studio-field"><span>Loop mode<small>playback</small></span><select data-projectile-field="${animationPath}.loopMode"><option value="wrap" ${animation.loopMode !== 'ping-pong' ? 'selected' : ''}>Wrap</option><option value="ping-pong" ${animation.loopMode === 'ping-pong' ? 'selected' : ''}>Ping-pong</option></select></label></div><label class="studio-toggle-field"><input type="checkbox" data-projectile-field="${animationPath}.loop" ${animation.loop ? 'checked' : ''} /><span><strong>Loop ${state.selectedAnimation === 'move' ? 'movement' : 'impact'}</strong><small>${state.selectedAnimation === 'move' ? 'Keep the projectile visual moving during flight' : 'Repeat the impact clip instead of recycling after it ends'}</small></span></label></section><section class="studio-inspector-section"><div class="studio-section-heading"><span class="studio-kicker">Physics</span><strong>Flight and collision</strong></div><div class="studio-field-grid"><label class="studio-field"><span>Body width<small>world units</small></span><input type="number" min="1" step="1" inputmode="numeric" value="${integerInputValue(projectile.body.width, 1)}" data-projectile-field="body.width" /></label><label class="studio-field"><span>Body height<small>world units</small></span><input type="number" min="1" step="1" inputmode="numeric" value="${integerInputValue(projectile.body.height, 1)}" data-projectile-field="body.height" /></label><label class="studio-field"><span>Center X<small>world units</small></span><input type="number" step="1" inputmode="numeric" value="${integerInputValue(projectile.body.centerOffsetX)}" data-projectile-field="body.centerOffsetX" /></label><label class="studio-field"><span>Center Y<small>world units</small></span><input type="number" step="1" inputmode="numeric" value="${integerInputValue(projectile.body.centerOffsetY)}" data-projectile-field="body.centerOffsetY" /></label><label class="studio-field"><span>Default speed<small>world units/s</small></span><input type="number" min="1" step="1" inputmode="numeric" value="${integerInputValue(projectile.movement.defaultSpeed, 1)}" data-projectile-field="movement.defaultSpeed" /></label><label class="studio-field"><span>Lifetime<small>milliseconds</small></span><input type="number" min="1" step="1" inputmode="numeric" value="${integerInputValue(projectile.movement.lifetimeMs, 1)}" data-projectile-field="movement.lifetimeMs" /></label></div><label class="studio-toggle-field"><input type="checkbox" data-projectile-field="movement.rotateToVelocity" ${projectile.movement.rotateToVelocity ? 'checked' : ''} /><span><strong>Rotate toward velocity</strong><small>Orient the projectile along its flight direction</small></span></label></section></div></section>` : '<section class="studio-empty-state"><span class="studio-loading-orb">*</span><h2>Select or create a projectile</h2><p>Projectiles combine a registered spritesheet, move animation, impact animation, and flight physics.</p></section>'}
      </section>
    </div>
    ${renderAssetShelf(state)}
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
  let state: ProjectileStudioState = {
    projectiles: [], selectedId: '', selectedAnimation: 'move', selectedPreviewFrame: 0, dirty: false, loading: true, saving: false,
    assetShelfOpen: false, importing: false,
    importForm: { assetId: 'projectile.enemy.new', frameWidth: '16', frameHeight: '16', populatedCount: '' },
  };
  const returnEditor = new URLSearchParams(window.location.search).get('editor') ?? 'level-1';
  const render = (): void => {
    container.innerHTML = renderStudio(state, returnEditor);
    ensureStudioModeTabs(container, returnEditor, 'projectiles');
    if (!state.draft) return;
    const sections = container.querySelectorAll<HTMLElement>('.projectile-inspector .studio-inspector-section');
    const animationSection = sections[1];
    const previewAnimation = projectileAnimations(state.draft)[state.selectedAnimation];
    const previewFrame = previewAnimation.frames.includes(state.selectedPreviewFrame) ? state.selectedPreviewFrame : previewAnimation.frames[0] ?? 0;
    if (animationSection) animationSection.insertAdjacentHTML('afterend', renderProjectileVisualFields(state.draft, previewFrame));
    const physicsSection = sections[2];
    const heading = physicsSection?.querySelector('.studio-section-heading');
    if (heading) heading.insertAdjacentHTML('afterend', renderCollisionShapeFields(state.draft));
    const source = state.assets?.assets.find((entry) => entry.assetId === state.draft?.assetId);
    const info = assetInfo(source);
    const stageSprite = container.querySelector<HTMLElement>('.projectile-stage .stage-sprite');
    stageSprite?.style.setProperty('--frame-x', `${(previewFrame % info.columns) * info.width}px`);
    stageSprite?.style.setProperty('--frame-y', `${Math.floor(previewFrame / info.columns) * info.height}px`);
    reflowProjectileStudio(container);
    applyProjectilePreviewGeometry(container, state.draft, previewFrame);
  };
  const select = (projectile: ProjectileDefinition, revision?: string, dirty = false): void => {
    state = { ...state, selectedId: projectile.projectileId, selectedAnimation: 'move', selectedPreviewFrame: 0, draft: clone(projectile), revision, dirty, assetShelfOpen: false, notice: undefined };
    render();
  };
  const importSource = async (file: File): Promise<void> => {
    const assetId = state.importForm.assetId.trim().toLowerCase();
    const frameWidth = state.importForm.frameWidth.trim();
    const frameHeight = state.importForm.frameHeight.trim();
    if (!assetId || !frameWidth || !frameHeight) {
      state = { ...state, notice: 'Enter an asset ID, frame width, and frame height first.' };
      render();
      return;
    }
    const metadata: Record<string, unknown> = { assetId, frameWidth, frameHeight, kind: 'enemy', tags: ['projectile'] };
    if (state.importForm.populatedCount.trim()) metadata.populatedCount = state.importForm.populatedCount.trim();
    const body = new FormData();
    body.append('metadata', JSON.stringify(metadata));
    body.append('file', file, file.name);
    state = { ...state, importing: true, notice: 'Registering projectile source...' };
    render();
    try {
      const response = await fetch('/__character-studio/asset/register', { method: 'POST', body });
      const payload = await response.json() as { ok: boolean; data?: { assetId: string }; error?: { message?: string } };
      if (!response.ok || !payload.ok || !payload.data) throw new Error(payload.error?.message ?? 'Projectile source import failed');
      const assets = await loadJson<CharacterStudioAssetCatalog>('/__character-studio/assets');
      const selectedAsset = assets.assets.find((entry) => entry.assetId === payload.data?.assetId);
      const draft = state.draft ? { ...state.draft, assetId: payload.data.assetId, animations: projectileAnimationsForFrameCount(state.draft, assetInfo(selectedAsset).count) } : undefined;
      state = { ...state, assets, draft, assetShelfOpen: false, importing: false, dirty: draft !== undefined, notice: 'Projectile source imported and selected' };
      render();
    } catch (error) {
      state = { ...state, importing: false, notice: error instanceof Error ? error.message : String(error) };
      render();
    }
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
      animation?: ProjectileAnimationDocument;
      animations?: ProjectileAnimationSet;
      visual?: ProjectileVisualDocument;
      body: { shape?: CollisionShape; width: number; height: number; radius?: number; radiusX?: number; radiusY?: number; centerOffsetX: number; centerOffsetY: number };
      movement: { defaultSpeed: number; lifetimeMs: number; rotateToVelocity: boolean };
    };
    const animationMatch = path.match(/^animations\.(move|impact)\.(frames|framesPerSecond|loop|loopMode)$/);
    const visualMatch = path.match(/^visual\.(sourceOffset|frameOffsets)\.(\d+)(?:\.(0|1))?$/);
    const numericPaths = new Set(['body.width', 'body.height', 'body.radius', 'body.radiusX', 'body.radiusY', 'body.centerOffsetX', 'body.centerOffsetY', 'movement.defaultSpeed', 'movement.lifetimeMs']);
    if (visualMatch) {
      const visual = clone(projectileVisual(draft)) as unknown as { sourceOffset: [number, number]; frameOffsets: Record<string, [number, number]> };
      const target = visualMatch[1];
      const frame = visualMatch[2];
      const axis = target === 'sourceOffset' ? Number(frame) : Number(visualMatch[3]);
      if (target === 'sourceOffset') visual.sourceOffset[axis] = integerValue(rawValue);
      else {
        visual.frameOffsets[frame] ??= [...visual.sourceOffset];
        visual.frameOffsets[frame][axis] = integerValue(rawValue);
      }
      draft.visual = visual;
    } else if (animationMatch) {
      const animationId = animationMatch[1] as ProjectileAnimationId;
      const field = animationMatch[2] as 'frames' | 'framesPerSecond' | 'loop' | 'loopMode';
      const animations = projectileAnimations(draft);
      const next = { ...animations[animationId] } as { frames: number[]; framesPerSecond: number; loop: boolean; loopMode?: 'wrap' | 'ping-pong' };
      if (field === 'frames') next.frames = String(rawValue).split(',').map((entry) => Number(entry.trim())).filter((entry) => Number.isInteger(entry) && entry >= 0);
      else if (field === 'framesPerSecond') next.framesPerSecond = Math.min(240, Math.max(1, integerValue(rawValue, 12)));
      else if (field === 'loop') next.loop = Boolean(rawValue);
      else next.loopMode = rawValue === 'ping-pong' ? 'ping-pong' : 'wrap';
      draft.animations = { ...animations, [animationId]: next };
      delete draft.animation;
    } else {
      const value: string | number | boolean = numericPaths.has(path) ? integerValue(rawValue) : rawValue;
      if (path === 'body.shape') {
        const shape: CollisionShape = value === 'circle' || value === 'ellipse' ? value : 'rectangle';
        draft.body.shape = shape;
        if (shape === 'circle') {
          draft.body.radius ??= integerValue(Math.min(draft.body.width, draft.body.height) / 2, 1);
          delete draft.body.radiusX;
          delete draft.body.radiusY;
        } else if (shape === 'ellipse') {
          draft.body.radiusX ??= integerValue(draft.body.width / 2, 1);
          draft.body.radiusY ??= integerValue(draft.body.height / 2, 1);
          delete draft.body.radius;
        } else {
          delete draft.body.radius;
          delete draft.body.radiusX;
          delete draft.body.radiusY;
        }
      } else if (path === 'body.width') draft.body.width = Number(value);
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
      else if (path === 'assetId') {
        draft.assetId = String(value);
        const selectedAsset = state.assets?.assets.find((entry) => entry.assetId === draft.assetId);
        draft.animations = projectileAnimationsForFrameCount(draft, assetInfo(selectedAsset).count);
        delete draft.animation;
      }
    }
    state = { ...state, draft, selectedId: draft.projectileId, dirty: true, notice: undefined };
  };
  const save = async (): Promise<void> => {
    if (!state.draft || !state.dirty) return;
    state = { ...state, saving: true, notice: 'Saving projectile...' };
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
    const shelfBackdrop = target.closest<HTMLElement>('[data-projectile-shelf-backdrop]');
    if (shelfBackdrop && target === shelfBackdrop) {
      state = { ...state, assetShelfOpen: false, notice: undefined };
      render();
      return;
    }
    const animationTab = target.closest<HTMLElement>('[data-projectile-animation-id]')?.dataset.projectileAnimationId;
    if (animationTab === 'move' || animationTab === 'impact') {
      state = { ...state, selectedAnimation: animationTab, selectedPreviewFrame: 0 };
      render();
      return;
    }
    const frameButton = target.closest<HTMLElement>('[data-projectile-frame]');
    if (frameButton && state.draft) {
      const frame = Number(frameButton.dataset.projectileFrame);
      const animation = projectileAnimations(state.draft)[state.selectedAnimation];
      const frames = [...animation.frames];
      const nextFrames = frames.includes(frame) ? frames.filter((candidate) => candidate !== frame) : [...frames, frame];
      updateDraft(`animations.${state.selectedAnimation}.frames`, nextFrames.join(', '));
      state = { ...state, selectedPreviewFrame: frame };
      render();
      return;
    }
    const projectileButton = target.closest<HTMLElement>('[data-projectile-id]');
    if (projectileButton) {
      const entry = state.projectiles.find((candidate) => candidate.projectileId === projectileButton.dataset.projectileId);
      if (entry) select(entry, entry.revision);
      return;
    }
    const actionElement = target.closest<HTMLElement>('[data-action]');
    const action = actionElement?.dataset.action;
    if (action === 'new-projectile') {
      const asset = state.assets?.assets.find(isProjectileAsset);
      select(makeNewProjectile(asset, new Set(state.projectiles.map((entry) => entry.projectileId))), undefined, true);
      return;
    }
    if (action === 'open-projectile-source-library') {
      state = { ...state, assetShelfOpen: true, notice: undefined };
      render();
      return;
    }
    if (action === 'close-projectile-source-library') {
      state = { ...state, assetShelfOpen: false, notice: undefined };
      render();
      return;
    }
    if (action === 'select-projectile-asset') {
      const assetId = actionElement?.dataset.projectileAssetId;
      if (assetId) {
        updateDraft('assetId', assetId);
        state = { ...state, assetShelfOpen: false, selectedPreviewFrame: 0 };
        render();
      }
      return;
    }
    if (action === 'reset-projectile-frame-visual' && state.draft) {
      const visual = projectileVisual(state.draft);
      const frame = String(state.selectedPreviewFrame);
      const frameOffsets = { ...(visual.frameOffsets ?? {}) };
      delete frameOffsets[frame];
      const draft = { ...state.draft, visual: { ...visual, frameOffsets } };
      state = { ...state, draft, dirty: true, notice: undefined };
      render();
      return;
    }
    if (action === 'upload-projectile-source') {
      container.querySelector<HTMLInputElement>('[data-projectile-upload]')?.click();
      return;
    }
    if (action === 'save-projectile') void save();
  };
  const onInput = (event: Event): void => {
    const target = event.target as HTMLInputElement | HTMLSelectElement;
    if (target.matches('[data-projectile-upload]')) {
      const upload = target instanceof HTMLInputElement ? target : undefined;
      const file = upload?.files?.[0];
      if (upload) upload.value = '';
      if (file) void importSource(file);
      return;
    }
    const importField = target.dataset.projectileImportField;
    if (importField && importField in state.importForm) {
      state = { ...state, importForm: { ...state.importForm, [importField]: target.value } };
      return;
    }
    const path = target.dataset.projectileField;
    if (!path) return;
    updateDraft(path, target instanceof HTMLInputElement && target.type === 'checkbox' ? target.checked : target.value);
    if (state.draft) applyProjectilePreviewGeometry(container, state.draft, state.selectedPreviewFrame);
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
