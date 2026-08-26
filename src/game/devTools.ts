import { saveSystem } from './core/SaveSystem';
import { gameEvents } from './core/EventBus';
import type { NamedSaveMetadata } from './infrastructure/persistence/SaveSchema';
import { formatCameraZoom } from './presentation/CameraZoom';
import { ModalStack } from './ui/ModalStack';
import { createTransientModalSession } from './ui/TransientModalSession';

export interface DevToolsState {
  enabled: boolean;
  worldBounds: boolean;
  visualBounds: boolean;
  hitBoxes: boolean;
  occlusionBounds: boolean;
  depthBounds: boolean;
  depthAnchors: boolean;
  interactionZones: boolean;
  attackBoxes: boolean;
  enemyBoundaries: boolean;
}

type DevToolKey = keyof Omit<DevToolsState, 'enabled'>;

const TOGGLES: Array<{ key: DevToolKey; label: string; description: string }> = [
  { key: 'worldBounds', label: 'World bounds', description: 'World and camera extents' },
  { key: 'visualBounds', label: 'Visual bounds', description: 'Rendered sprite rectangles, including objects' },
  { key: 'hitBoxes', label: 'Colliders', description: 'Arcade physics bodies' },
  { key: 'occlusionBounds', label: 'Occlusion bounds', description: 'Object scan regions that hide actors' },
  { key: 'depthBounds', label: 'Depth bounds', description: 'Object regions that set front/behind sorting' },
  { key: 'depthAnchors', label: 'Depth anchors', description: 'Ground points used for front/behind sorting' },
  { key: 'interactionZones', label: 'Interaction zones', description: 'Doors, pickups, transitions' },
  { key: 'attackBoxes', label: 'Active attack hitboxes', description: 'Live authored collision shapes and timing' },
  { key: 'enemyBoundaries', label: 'Enemy boundaries', description: 'Stay and pursue perimeters' },
];

export const devToolsState: DevToolsState = {
  enabled: false,
  worldBounds: false,
  visualBounds: true,
  hitBoxes: true,
  occlusionBounds: false,
  depthBounds: false,
  depthAnchors: false,
  interactionZones: true,
  attackBoxes: true,
  enemyBoundaries: false,
};

let displayedCameraZoom = 1;

export function updateDevToolsCameraZoom(zoom: number): void {
  if (!Number.isFinite(zoom) || zoom <= 0 || zoom === displayedCameraZoom) return;
  displayedCameraZoom = zoom;
  document.querySelectorAll<HTMLElement>('[data-dev-camera-zoom]').forEach((element) => {
    element.textContent = formatCameraZoom(zoom);
  });
}

export function createDevToolsPanel(): string {
  const rows = TOGGLES.map((toggle) => `
    <label class="dev-toggle-row">
      <input type="checkbox" data-dev-toggle="${toggle.key}" ${devToolsState[toggle.key] ? 'checked' : ''} />
      <span class="dev-checkbox" aria-hidden="true"></span>
      <span><strong>${toggle.label}</strong><small>${toggle.description}</small></span>
    </label>
  `).join('');

  return `
    <aside class="development-panel" aria-label="Development tools">
      <header class="development-panel__header">
        <span class="dev-status-dot"></span>
        <div><p>Debug Console</p><h2>Development Tools</h2></div>
      </header>
      <section class="dev-card">
        <h3>Runtime</h3>
        <div class="dev-runtime-metric"><span>Camera zoom</span><strong data-dev-camera-zoom>${formatCameraZoom(displayedCameraZoom)}</strong></div>
        <button class="dev-runtime-button" type="button" data-dev-enabled="true">Enable Overlays</button>
        <div class="dev-persistence-actions" aria-label="Save controls">
          <button class="dev-runtime-button dev-runtime-button--secondary" type="button" data-persistence-action="open-save">Save Game</button>
          <button class="dev-runtime-button dev-runtime-button--secondary" type="button" data-persistence-action="open-load">Load Game</button>
          <button class="dev-runtime-button dev-runtime-button--danger" type="button" data-persistence-action="open-reset">Reset Run</button>
        </div>
        <p class="dev-note">Named saves are independent snapshots. Recovery autosave is used for browser close.</p>
        <p class="dev-note">Visible only in Vite dev mode.</p>
      </section>
      <section class="dev-card"><h3>Bounds</h3>${rows}</section>
      <section class="dev-card dev-legend">
        <h3>Legend</h3>
        <p><span class="swatch swatch-world"></span> World/camera</p>
        <p><span class="swatch swatch-visual"></span> Visual bounds</p>
        <p><span class="swatch swatch-hit"></span> Colliders</p>
        <p><span class="swatch swatch-occlusion"></span> Occlusion bounds</p>
        <p><span class="swatch swatch-depth-bounds"></span> Depth bounds</p>
        <p><span class="swatch swatch-depth-anchor"></span> Depth anchors</p>
        <p><span class="swatch swatch-interaction"></span> Interactions</p>
        <p><span class="swatch swatch-attack"></span> Active attack hitboxes</p>
        <p><span class="swatch swatch-enemy-stay"></span> Enemy stay</p>
        <p><span class="swatch swatch-enemy-pursue"></span> Enemy pursue</p>
      </section>
    </aside>
  `;
}

type PersistenceMode = 'save' | 'load' | 'reset';
interface PersistenceModalState {
  mode: PersistenceMode;
  createNew: boolean;
  overwriteId?: string;
  conflictId?: string;
  busy: boolean;
  message?: string;
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>'"]/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[character] ?? character));
}

function formatTimestamp(value: number): string {
  return Number.isFinite(value) ? new Date(value).toLocaleString() : 'Unknown time';
}

function renderSaveRecord(record: NamedSaveMetadata, mode: 'save' | 'load'): string {
  const actions = mode === 'save'
    ? `<button type="button" class="dev-modal-button" data-persistence-action="overwrite" data-save-id="${escapeHtml(record.saveId)}">Overwrite</button>`
    : `<button type="button" class="dev-modal-button" data-persistence-action="load" data-save-id="${escapeHtml(record.saveId)}">Load</button>
       <button type="button" class="dev-modal-button dev-modal-button--quiet" data-persistence-action="delete" data-save-id="${escapeHtml(record.saveId)}">Delete</button>`;
  return `<article class="dev-save-record"><div><strong>${escapeHtml(record.name)}</strong><small>${escapeHtml(formatTimestamp(record.updatedAt))} · ${escapeHtml(record.currentMapId)} · Level ${record.playerLevel}</small></div><div class="dev-save-record__actions">${actions}</div></article>`;
}

function renderPersistenceModal(state: PersistenceModalState): string {
  const records = saveSystem.listNamedSaves();
  const validationIssues = saveSystem.namedSaveValidationIssues();
  const issueMarkup = validationIssues.length > 0
    ? `<div class="dev-save-warning" role="status"><strong>${validationIssues.length} save ${validationIssues.length === 1 ? 'record needs' : 'records need'} attention.</strong>${validationIssues.map((issue) => `<small>${escapeHtml(issue.saveId ? `${issue.saveId}: ${issue.reason}` : issue.reason)}</small>`).join('')}</div>`
    : '';
  const target = state.overwriteId ? records.find((record) => record.saveId === state.overwriteId) : undefined;
  if (state.mode === 'reset') {
    return `<div class="dev-modal-backdrop" data-persistence-backdrop><section class="dev-modal" role="dialog" aria-modal="true" aria-labelledby="dev-modal-title"><header><p>Persistence</p><h2 id="dev-modal-title">Reset this run?</h2></header><p>Active progress will return to authored Level 1 and the initial player state. Your named saves will remain untouched.</p>${state.message ? `<p class="dev-modal-status">${escapeHtml(state.message)}</p>` : ''}<footer><button type="button" class="dev-modal-button dev-modal-button--quiet" data-persistence-action="close">Cancel</button><button type="button" class="dev-modal-button dev-modal-button--danger" data-persistence-action="confirm-reset" ${state.busy ? 'disabled' : ''}>${state.busy ? 'Resetting…' : 'Reset Run'}</button></footer></section></div>`;
  }
  if (state.overwriteId && target) {
    return `<div class="dev-modal-backdrop" data-persistence-backdrop><section class="dev-modal" role="dialog" aria-modal="true" aria-labelledby="dev-modal-title"><header><p>Save Game</p><h2 id="dev-modal-title">Overwrite “${escapeHtml(target.name)}”?</h2></header><p>This replaces the snapshot last saved ${escapeHtml(formatTimestamp(target.updatedAt))}. Its name and creation time stay the same.</p>${state.message ? `<p class="dev-modal-status">${escapeHtml(state.message)}</p>` : ''}<footer><button type="button" class="dev-modal-button dev-modal-button--quiet" data-persistence-action="cancel-overwrite">Cancel</button><button type="button" class="dev-modal-button" data-persistence-action="confirm-overwrite" ${state.busy ? 'disabled' : ''}>${state.busy ? 'Saving…' : 'Confirm Overwrite'}</button></footer></section></div>`;
  }
  if (state.createNew) {
    return `<div class="dev-modal-backdrop" data-persistence-backdrop><section class="dev-modal" role="dialog" aria-modal="true" aria-labelledby="dev-modal-title"><header><p>Save Game</p><h2 id="dev-modal-title">Create a named snapshot</h2></header><label class="dev-modal-field"><span>Name</span><input type="text" maxlength="32" data-save-name autofocus placeholder="e.g. Before the forest" /></label>${state.conflictId ? `<p class="dev-modal-status">That name already exists. Choose Overwrite for the matching record or enter another name.</p><div class="dev-modal-inline-actions"><button type="button" class="dev-modal-button" data-persistence-action="overwrite" data-save-id="${escapeHtml(state.conflictId)}">Review matching save</button></div>` : ''}${state.message ? `<p class="dev-modal-status">${escapeHtml(state.message)}</p>` : ''}<footer><button type="button" class="dev-modal-button dev-modal-button--quiet" data-persistence-action="cancel-create">Cancel</button><button type="button" class="dev-modal-button" data-persistence-action="create" ${state.busy ? 'disabled' : ''}>${state.busy ? 'Saving…' : 'Create New Save'}</button></footer></section></div>`;
  }
  const recordMode: 'save' | 'load' = state.mode === 'save' ? 'save' : 'load';
  return `<div class="dev-modal-backdrop" data-persistence-backdrop><section class="dev-modal dev-modal--wide" role="dialog" aria-modal="true" aria-labelledby="dev-modal-title"><header><p>Persistence</p><h2 id="dev-modal-title">${state.mode === 'save' ? 'Save Game' : 'Load Game'}</h2></header>${issueMarkup}<div class="dev-save-list">${records.length > 0 ? records.map((record) => renderSaveRecord(record, recordMode)).join('') : '<p class="dev-modal-empty">No valid named saves yet.</p>'}</div>${state.message ? `<p class="dev-modal-status">${escapeHtml(state.message)}</p>` : ''}<footer>${state.mode === 'save' ? '<button type="button" class="dev-modal-button" data-persistence-action="create-new">Create New Save</button>' : ''}<button type="button" class="dev-modal-button dev-modal-button--quiet" data-persistence-action="close">Cancel</button></footer></section></div>`;
}

function bindPersistenceModal(root: HTMLElement, mode: PersistenceMode, restoreFocus: HTMLElement | null, modalStack: ModalStack): void {
  const state: PersistenceModalState = { mode, createNew: false, busy: false };
  const modal = document.createElement('div');
  modal.dataset.persistenceModal = 'true';
  const canClose = (): boolean => !state.busy;
  const session = createTransientModalSession({
    modalStack,
    id: 'persistence',
    canClose,
    onClosed: () => {
      gameEvents.emit('persistence.modal', { open: false });
      modal.remove();
      restoreFocus?.focus();
    },
  });
  const close = (): boolean => session.requestClose();

  root.appendChild(modal);
  gameEvents.emit('persistence.modal', { open: true });

  const render = (): void => {
    modal.innerHTML = renderPersistenceModal(state);
    const autofocus = modal.querySelector<HTMLInputElement>('[data-save-name]');
    (autofocus ?? modal.querySelector<HTMLElement>('button'))?.focus();
  };

  const onKeyDown = (event: KeyboardEvent): void => {
    if (event.key !== 'Tab') return;
    const focusable = [...modal.querySelectorAll<HTMLElement>('button:not(:disabled), input:not(:disabled)')];
    if (focusable.length === 0) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  };
  modal.addEventListener('keydown', onKeyDown);
  modal.addEventListener('click', (event) => {
    const target = event.target instanceof HTMLElement ? event.target.closest<HTMLElement>('[data-persistence-action]') : null;
    if (!target || state.busy) return;
    const action = target.dataset.persistenceAction;
    const saveId = target.dataset.saveId;
    if (action === 'close' || action === 'cancel-create') { close(); return; }
    if (action === 'create-new') { state.createNew = true; state.message = undefined; render(); return; }
    if (action === 'cancel-overwrite') { state.overwriteId = undefined; state.message = undefined; render(); return; }
    if (action === 'overwrite' && saveId) { state.overwriteId = saveId; state.createNew = false; state.message = undefined; render(); return; }
    if (action === 'create') {
      const input = modal.querySelector<HTMLInputElement>('[data-save-name]');
      const result = saveSystem.createNamedSave(input?.value ?? '');
      if (result.ok) { state.createNew = false; state.conflictId = undefined; state.message = `Saved “${result.metadata.name}”.`; }
      else { state.message = result.message; state.conflictId = result.saveId; }
      render();
      return;
    }
    if (action === 'confirm-overwrite' && state.overwriteId) {
      state.busy = true; render();
      const result = saveSystem.overwriteNamedSave(state.overwriteId);
      state.busy = false;
      state.overwriteId = undefined;
      state.message = result.ok ? `Saved “${result.metadata.name}”.` : result.message;
      render();
      return;
    }
    if (action === 'load' && saveId) {
      state.busy = true; state.message = 'Validating the selected snapshot…'; render();
      void saveSystem.loadNamedSave(saveId).then((result) => {
        if (!result.ok) { state.busy = false; state.message = result.message; render(); }
      });
      return;
    }
    if (action === 'delete' && saveId) {
      const record = saveSystem.listNamedSaves().find((entry) => entry.saveId === saveId);
      if (record && window.confirm(`Delete the named save “${record.name}”?`)) {
        state.message = saveSystem.deleteNamedSave(saveId) ? `Deleted “${record.name}”.` : 'That save could not be deleted.';
        render();
      }
      return;
    }
    if (action === 'confirm-reset') {
      state.busy = true; render();
      const result = saveSystem.resetRun();
      if (!result.ok) { state.busy = false; state.message = result.message; render(); }
    }
  });
  modal.addEventListener('click', (event) => {
    if (event.target instanceof HTMLElement && event.target.matches('[data-persistence-backdrop]') && !state.busy) close();
  });
  render();
}

export function bindDevToolsPanel(root: ParentNode, modalStack: ModalStack): void {
  const rootElement = root instanceof HTMLElement ? root : document.body;
  const button = root.querySelector<HTMLButtonElement>('[data-dev-enabled]');
  const syncButton = () => {
    if (!button) return;
    button.textContent = devToolsState.enabled ? 'Disable Overlays' : 'Enable Overlays';
    button.classList.toggle('is-active', devToolsState.enabled);
  };
  root.querySelectorAll<HTMLElement>('[data-dev-camera-zoom]').forEach((element) => {
    element.textContent = formatCameraZoom(displayedCameraZoom);
  });
  button?.addEventListener('click', () => { devToolsState.enabled = !devToolsState.enabled; syncButton(); });
  root.querySelectorAll<HTMLInputElement>('[data-dev-toggle]').forEach((input) => {
    const key = input.dataset.devToggle as DevToolKey | undefined;
    if (!key) return;
    input.checked = devToolsState[key];
    input.addEventListener('change', () => {
      devToolsState[key] = input.checked;
      if (input.checked && !devToolsState.enabled) { devToolsState.enabled = true; syncButton(); }
    });
  });
  rootElement.addEventListener('click', (event) => {
    const target = event.target instanceof HTMLElement ? event.target.closest<HTMLElement>('[data-persistence-action]') : null;
    if (!target || target.closest('[data-persistence-modal]')) return;
    const action = target.dataset.persistenceAction;
    if (action !== 'open-save' && action !== 'open-load' && action !== 'open-reset') return;
    const mode = action === 'open-save' ? 'save' : action === 'open-load' ? 'load' : 'reset';
    bindPersistenceModal(rootElement, mode, target as HTMLElement, modalStack);
  });
  syncButton();
}
