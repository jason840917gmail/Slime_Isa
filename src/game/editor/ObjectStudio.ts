import './object-studio.css';

import {
  getObjectVisualChoice,
  isObjectArchetypeId,
  type ObjectArchetypeId,
  type ObjectVisualChoice,
} from '../content/objects/ObjectCatalog';
import { getAsset } from '../infrastructure/assets/manifest';
import { resolveAssetUrl } from '../infrastructure/assets/assetUrls';
import { ensureStudioModeTabs } from './StudioModeTabs';

interface ObjectStudioFrame {
  readonly visualId: string;
  readonly frame: number;
  readonly displayName?: string;
  readonly visualSetId?: string;
  readonly animationClip?: string;
  readonly assetId?: string;
}

interface ObjectStudioDefinition {
  readonly objectId: string;
  readonly variants: readonly { readonly assetId: string; readonly frames: readonly ObjectStudioFrame[] }[];
  readonly resourceNode?: { readonly hitEffectId?: string };
}

interface ObjectStudioClip {
  readonly frames: readonly number[];
  readonly framesPerSecond: number;
  readonly loop: boolean;
  readonly loopMode?: 'wrap' | 'ping-pong';
}

interface ObjectStudioVisualSet {
  readonly version?: 1;
  readonly visualSetId: string;
  readonly assetId: string;
  readonly defaults?: { readonly origin: readonly [number, number]; readonly scale: readonly [number, number]; readonly sourceOffset: readonly [number, number] };
  readonly frameVisuals?: Readonly<Record<string, unknown>>;
  readonly clips: Readonly<Record<string, ObjectStudioClip>>;
}

interface ObjectStudioEffect {
  readonly effectId: string;
  readonly displayName?: string;
}

interface ObjectStudioCatalog {
  readonly objects: readonly ObjectStudioDefinition[];
  readonly visualSets: readonly ObjectStudioVisualSet[];
  readonly effects: readonly ObjectStudioEffect[];
}

async function loadObjectStudioCatalog(): Promise<ObjectStudioCatalog> {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetch('/__object-studio/catalog', {
      cache: 'no-store',
      signal: controller.signal,
    });
    const payload = await response.json() as { ok?: boolean; data?: ObjectStudioCatalog; error?: string };
    if (!response.ok || !payload.ok || !payload.data) throw new Error(payload.error ?? 'Object Studio catalog failed');
    return payload.data;
  } catch (error: unknown) {
    if (error instanceof DOMException && error.name === 'AbortError') {
      throw new Error('Object Studio catalog timed out. Restart the Vite dev server and reopen Object Studio.');
    }
    throw error;
  } finally {
    window.clearTimeout(timeout);
  }
}

interface SelectedVisual {
  readonly definition: ObjectStudioDefinition;
  readonly frame: ObjectStudioFrame;
  readonly choice: ObjectVisualChoice;
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

function titleFromId(value: string): string {
  return value.split(/[.-]/).map((part) => `${part[0]?.toUpperCase() ?? ''}${part.slice(1)}`).join(' ');
}

function selectedVisual(catalog: ObjectStudioCatalog, objectId: string, visualId: string): SelectedVisual | undefined {
  if (!isObjectArchetypeId(objectId)) return undefined;
  const definition = catalog.objects.find((candidate) => candidate.objectId === objectId);
  const frame = definition?.variants.flatMap((variant) => variant.frames).find((candidate) => candidate.visualId === visualId);
  const choice = getObjectVisualChoice(objectId as ObjectArchetypeId, visualId);
  return definition && frame && choice ? { definition, frame, choice } : undefined;
}

function assetFrameInfo(choice: ObjectVisualChoice): { readonly url?: string; readonly width: number; readonly height: number; readonly columns: number; readonly rows: number; readonly count: number } {
  const asset = getAsset(choice.assetId);
  if (asset.source.kind !== 'spritesheet' || !('frame' in asset.source)) {
    return { width: 128, height: 128, columns: 1, rows: 1, count: 1 };
  }
  return {
    url: resolveAssetUrl(asset.source.path),
    width: asset.source.frame.w,
    height: asset.source.frame.h,
    columns: asset.source.frame.cols,
    rows: asset.source.frame.rows,
    count: asset.source.frame.cols * asset.source.frame.rows,
  };
}

function renderFrame(choice: ObjectVisualChoice, frame: number, className = ''): string {
  const info = assetFrameInfo(choice);
  const clamped = Math.max(0, Math.min(frame, info.count - 1));
  const column = clamped % info.columns;
  const row = Math.floor(clamped / info.columns);
  const positionX = info.columns <= 1 ? 0 : (column / (info.columns - 1)) * 100;
  const positionY = info.rows <= 1 ? 0 : (row / (info.rows - 1)) * 100;
  return `<div class="object-studio-frame ${className}" style="width:${info.width}px;height:${info.height}px;background-image:url('${escapeHtml(info.url ?? '')}');background-size:${info.columns * 100}% ${info.rows * 100}%;background-position:${positionX}% ${positionY}%" aria-label="Source frame ${clamped}"></div>`;
}

function objectVisuals(catalog: ObjectStudioCatalog): readonly SelectedVisual[] {
  return catalog.objects.flatMap((definition) => definition.variants.flatMap((variant) => variant.frames.flatMap((frame) => {
    if (!isObjectArchetypeId(definition.objectId)) return [];
    const choice = getObjectVisualChoice(definition.objectId as ObjectArchetypeId, frame.visualId);
    return choice ? [{ definition, frame, choice }] : [];
  })));
}

export function mountObjectStudio(container: HTMLDivElement): () => void {
  let catalog: ObjectStudioCatalog | undefined;
  let selectedObjectId = new URLSearchParams(window.location.search).get('object') ?? '';
  let selectedVisualId = new URLSearchParams(window.location.search).get('visual') ?? '';
  let selectedSetId: string | undefined;
  let selectedClipId: string | undefined;
  let draftVisualSet: ObjectStudioVisualSet | undefined;
  let draftFrames: number[] | undefined;
  let draftFps: number | undefined;
  let draftHitEffectId: string | undefined;
  let selectedFrame = 0;
  let playing = false;
  let playTimer: number | undefined;
  let notice = 'Loading Object Studio…';
  const returnEditor = new URLSearchParams(window.location.search).get('editor') ?? '';

  const selected = (): SelectedVisual | undefined => catalog ? selectedVisual(catalog, selectedObjectId, selectedVisualId) : undefined;
  const selectedSet = (): ObjectStudioVisualSet | undefined => draftVisualSet ?? catalog?.visualSets.find((visualSet) => visualSet.visualSetId === selectedSetId);
  const selectedClip = (): ObjectStudioClip | undefined => {
    const clip = selectedSet()?.clips[selectedClipId ?? ''];
    if (!clip) return undefined;
    const frames = draftFrames ?? clip.frames;
    return frames.length > 0 ? { ...clip, frames, framesPerSecond: draftFps ?? clip.framesPerSecond } : undefined;
  };
  const cloneVisualSet = (visualSet: ObjectStudioVisualSet | undefined): ObjectStudioVisualSet | undefined => (
    visualSet ? JSON.parse(JSON.stringify(visualSet)) as ObjectStudioVisualSet : undefined
  );
  const selectVisualSet = (visualSetId: string | undefined, clipId: string | undefined): void => {
    selectedSetId = visualSetId;
    draftVisualSet = cloneVisualSet(catalog?.visualSets.find((visualSet) => visualSet.visualSetId === visualSetId));
    selectedClipId = clipId ?? (visualSetId ? Object.keys(selectedSet()?.clips ?? {})[0] : undefined);
    const clip = selectedSet()?.clips[selectedClipId ?? ''];
    draftFrames = clip ? [...clip.frames] : undefined;
    draftFps = clip?.framesPerSecond;
    selectedFrame = 0;
  };
  const returnUrl = (): string => {
    const params = new URLSearchParams();
    if (returnEditor) params.set('editor', returnEditor);
    if (selectedObjectId) params.set('templateObject', selectedObjectId);
    if (selectedVisualId) params.set('templateVisual', selectedVisualId);
    const query = params.toString();
    return query ? `?${query}` : '?';
  };

  const stopPlayback = (): void => {
    if (playTimer !== undefined) window.clearInterval(playTimer);
    playTimer = undefined;
    playing = false;
  };

  const updatePreview = (): void => {
    const target = container.querySelector<HTMLElement>('[data-object-preview]');
    const current = selected();
    if (!target || !current) return;
    const clip = selectedClip();
    const frame = clip?.frames[selectedFrame] ?? current.frame.frame;
    target.innerHTML = renderFrame(current.choice, frame, 'is-preview');
    container.querySelectorAll<HTMLElement>('[data-object-frame]').forEach((button) => {
      button.classList.toggle('is-active', Number(button.dataset.objectFrame) === selectedFrame);
    });
    const playButton = container.querySelector<HTMLButtonElement>('[data-action="toggle-play"]');
    if (playButton) playButton.textContent = playing ? 'PAUSE' : 'PLAY IDLE';
  };

  const startPlayback = (): void => {
    const clip = selectedClip();
    if (!clip) return;
    if (playing) {
      stopPlayback();
      updatePreview();
      return;
    }
    playing = true;
    playTimer = window.setInterval(() => {
      const activeClip = selectedClip();
      if (!activeClip) { stopPlayback(); updatePreview(); return; }
      selectedFrame += 1;
      if (selectedFrame >= activeClip.frames.length) {
        if (!activeClip.loop) { selectedFrame = activeClip.frames.length - 1; stopPlayback(); }
        else selectedFrame = 0;
      }
      updatePreview();
    }, 1000 / Math.max(1, clip.framesPerSecond));
    updatePreview();
  };

  const renderContent = (): void => {
    if (!catalog) {
      container.innerHTML = `<main class="object-studio"><p class="object-studio-notice">${escapeHtml(notice)}</p></main>`;
      return;
    }
    const visuals = objectVisuals(catalog);
    const current = selected() ?? visuals[0];
    if (!current) {
      container.innerHTML = '<main class="object-studio"><p class="object-studio-notice">No authored object visuals found.</p></main>';
      return;
    }
    selectedObjectId = current.definition.objectId;
    selectedVisualId = current.frame.visualId;
    const matchingSets = [
      ...catalog.visualSets.filter((visualSet) => visualSet.assetId === current.choice.assetId),
      ...(draftVisualSet && !catalog.visualSets.some((visualSet) => visualSet.visualSetId === draftVisualSet!.visualSetId) ? [draftVisualSet] : []),
    ];
    if (selectedSetId && !matchingSets.some((visualSet) => visualSet.visualSetId === selectedSetId)) selectedSetId = undefined;
    const currentClip = selectedClip();
    selectedFrame = currentClip ? Math.min(selectedFrame, currentClip.frames.length - 1) : 0;
    const effectOptions = catalog.effects.map((effect) => `<option value="${escapeHtml(effect.effectId)}" ${draftHitEffectId === effect.effectId ? 'selected' : ''}>${escapeHtml(effect.displayName ?? titleFromId(effect.effectId))}</option>`).join('');
    const visualButtons = visuals.map((entry) => `<button type="button" class="object-studio-library-item${entry.definition.objectId === current.definition.objectId && entry.frame.visualId === current.frame.visualId ? ' is-active' : ''}" data-object="${escapeHtml(entry.definition.objectId)}" data-visual="${escapeHtml(entry.frame.visualId)}"><span>${escapeHtml(entry.frame.displayName ?? titleFromId(entry.frame.visualId))}</span><small>${escapeHtml(entry.definition.objectId)} · frame ${entry.frame.frame}</small></button>`).join('');
    const setOptions = matchingSets.map((visualSet) => `<option value="${escapeHtml(visualSet.visualSetId)}" ${visualSet.visualSetId === selectedSetId ? 'selected' : ''}>${escapeHtml(visualSet.visualSetId)}</option>`).join('');
    const clipOptions = selectedSet() ? Object.keys(selectedSet()!.clips).map((clipId) => `<option value="${escapeHtml(clipId)}" ${clipId === selectedClipId ? 'selected' : ''}>${escapeHtml(clipId)}</option>`).join('') : '';
    const timeline = currentClip ? currentClip.frames.map((frame, index) => `<button type="button" class="object-studio-timeline-frame${index === selectedFrame ? ' is-active' : ''}" data-object-frame="${index}">${renderFrame(current.choice, frame)}<small>${index + 1} · ${frame}</small></button>`).join('') : '<p class="object-studio-empty">No idle clip selected. Runtime will use the static image.</p>';
    container.innerHTML = `
      <main class="object-studio">
        <header class="object-studio-topbar"><a class="object-studio-brand" href="${escapeHtml(returnUrl())}"><span>✦</span><strong>OBJECT STUDIO</strong></a><div class="studio-topbar-actions"><span class="object-studio-status">${escapeHtml(notice)}</span></div></header>
        <section class="object-studio-body">
          <aside class="object-studio-library"><div class="object-studio-heading"><span>Shared templates</span><strong>Objects</strong></div><div class="object-studio-library-list">${visualButtons}</div><a class="object-studio-return" href="${escapeHtml(returnUrl())}">← RETURN TO MAP STUDIO</a></aside>
          <section class="object-studio-workbench"><div class="object-studio-section-heading"><div><span>Shared visual template</span><h1>${escapeHtml(current.frame.displayName ?? titleFromId(current.frame.visualId))}</h1><small>${escapeHtml(current.definition.objectId)} / ${escapeHtml(current.frame.visualId)}</small></div><span class="object-studio-badge">ALL INSTANCES</span></div>
            <div class="object-studio-preview-shell"><div data-object-preview>${renderFrame(current.choice, currentClip?.frames[selectedFrame] ?? current.frame.frame, 'is-preview')}</div><p>Static base image remains the fallback whenever the optional idle package is missing or invalid.</p></div>
            <section class="object-studio-timeline"><div class="object-studio-section-heading"><div><span>Shared idle animation</span><strong>${currentClip ? `${currentClip.frames.length} keyframes` : 'Static image fallback'}</strong></div><div class="object-studio-timeline-actions"><button type="button" class="object-studio-button" data-action="toggle-play" ${currentClip ? '' : 'disabled'}>${playing ? 'PAUSE' : 'PLAY IDLE'}</button><button type="button" class="object-studio-button" data-action="add-frame" ${selectedClipId ? '' : 'disabled'}>ADD SOURCE FRAME</button><button type="button" class="object-studio-button" data-action="remove-frame" ${currentClip && currentClip.frames.length > 1 ? '' : 'disabled'}>REMOVE</button></div></div><div class="object-studio-timeline-strip">${timeline}</div></section>
          </section>
          <aside class="object-studio-inspector"><div class="object-studio-heading"><span>Object-owned presentation</span><strong>Animation</strong></div><label>Visual set<select data-field="visualSetId"><option value="">None — static image</option>${setOptions}</select></label><label>Idle clip<select data-field="animationClip" ${selectedSetId ? '' : 'disabled'}><option value="">Select clip</option>${clipOptions}</select></label>${selectedClipId ? `<label>Frames per second<input type="number" min="1" max="240" step="1" value="${draftFps ?? currentClip?.framesPerSecond ?? 8}" data-field="clipFps" /></label>` : ''}<button type="button" class="object-studio-button" data-action="create-idle-package" ${selectedSetId ? 'disabled' : ''}>CREATE IDLE PACKAGE</button><p class="object-studio-help">Idle animation uses the shared visual-set frame clips also used by Character Studio. Every placed instance follows this same template.</p><div class="object-studio-divider"></div><div class="object-studio-heading"><span>Material feedback</span><strong>Resource hit effect</strong></div>${current.definition.resourceNode ? `<label>On positive damage<select data-field="hitEffectId"><option value="">None</option>${effectOptions}</select></label><p class="object-studio-help">The resource owns this effect. Any tool that deals positive damage receives the same material feedback.</p>` : '<p class="object-studio-help">This object is not a resource node. Add resource behavior before assigning a material hit effect.</p>'}<button type="button" class="object-studio-button object-studio-button--save" data-action="save">SAVE OBJECT TEMPLATE</button></aside>
        </section>
      </main>`;
    ensureStudioModeTabs(container, returnEditor, 'objects', { object: selectedObjectId, visual: selectedVisualId });
  };

  const render = (): void => {
    try {
      renderContent();
    } catch (error: unknown) {
      stopPlayback();
      notice = error instanceof Error ? error.message : String(error);
      container.innerHTML = `<main class="object-studio"><p class="object-studio-notice">Object Studio could not render: ${escapeHtml(notice)}</p></main>`;
    }
  };

  const clickHandler = (event: MouseEvent): void => {
    const target = (event.target as HTMLElement).closest<HTMLElement>('[data-object], [data-action], [data-object-frame]');
    if (!target || !catalog) return;
    if (target.dataset.object && target.dataset.visual) {
      stopPlayback();
      selectedObjectId = target.dataset.object;
      selectedVisualId = target.dataset.visual;
      const current = selected();
      selectVisualSet(current?.frame.visualSetId, current?.frame.animationClip);
      draftHitEffectId = current?.definition.resourceNode?.hitEffectId;
      selectedFrame = 0;
      notice = 'Ready';
      render();
      return;
    }
    if (target.dataset.objectFrame !== undefined) {
      selectedFrame = Number(target.dataset.objectFrame);
      updatePreview();
      return;
    }
    if (target.dataset.action === 'create-idle-package') {
      const current = selected();
      if (!current) return;
      const visualSetId = `${current.definition.objectId}.${current.frame.visualId}`;
      draftVisualSet = {
        version: 1,
        visualSetId,
        assetId: current.choice.assetId,
        defaults: { origin: [0.5, 1], scale: [1, 1], sourceOffset: [0, 0] },
        clips: { idle: { frames: [current.frame.frame], framesPerSecond: 8, loop: true, loopMode: 'wrap' } },
      };
      selectedSetId = visualSetId;
      selectedClipId = 'idle';
      draftFrames = [current.frame.frame];
      draftFps = 8;
      selectedFrame = 0;
      notice = 'Idle package ready to author';
      render();
      return;
    }
    if (target.dataset.action === 'add-frame') {
      const current = selected();
      const clip = selectedClip();
      if (!current || !clip) return;
      const info = assetFrameInfo(current.choice);
      const nextFrame = Math.max(0, Math.min(info.count - 1, Number(window.prompt(`Source frame (0-${info.count - 1})`, String(current.frame.frame)) ?? current.frame.frame)));
      draftFrames = [...clip.frames, Number.isFinite(nextFrame) ? Math.round(nextFrame) : current.frame.frame];
      selectedFrame = draftFrames.length - 1;
      render();
      return;
    }
    if (target.dataset.action === 'remove-frame') {
      const clip = selectedClip();
      if (!clip || clip.frames.length <= 1) return;
      draftFrames = clip.frames.filter((_, index) => index !== selectedFrame);
      selectedFrame = Math.max(0, Math.min(selectedFrame, draftFrames.length - 1));
      render();
      return;
    }
    if (target.dataset.action === 'toggle-play') { startPlayback(); return; }
    if (target.dataset.action === 'save') {
      const current = selected();
      if (!current) return;
      const idleSet = selectedSetId ?? null;
      const idleClip = idleSet && selectedClipId ? selectedClipId : null;
      const hitEffect = current.definition.resourceNode ? (draftHitEffectId || null) : undefined;
      const visualSet = draftVisualSet && selectedClipId && selectedClip()
        ? {
            ...draftVisualSet,
            version: 1 as const,
            clips: {
              ...draftVisualSet.clips,
              [selectedClipId]: {
                ...draftVisualSet.clips[selectedClipId],
                frames: [...selectedClip()!.frames],
                framesPerSecond: selectedClip()!.framesPerSecond,
              },
            },
          }
        : undefined;
      notice = 'Saving…';
      render();
      void fetch('/__object-studio/save', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ objectId: current.definition.objectId, visualId: current.frame.visualId, visualSetId: idleSet, animationClip: idleClip, ...(visualSet ? { visualSet } : {}), ...(hitEffect !== undefined ? { hitEffectId: hitEffect } : {}) }) })
        .then(async (response) => {
          const result = await response.json() as { ok?: boolean; error?: string };
          if (!response.ok || !result.ok) throw new Error(result.error ?? 'Object template save failed');
          notice = 'Saved. Reload the map to apply shared changes.';
          render();
        })
        .catch((error: unknown) => { notice = error instanceof Error ? error.message : String(error); render(); });
    }
  };

  const changeHandler = (event: Event): void => {
    const target = event.target as HTMLSelectElement;
    const field = target.dataset.field;
    if (!field || !catalog) return;
    if (field === 'visualSetId') {
      selectVisualSet(target.value || undefined, undefined);
    } else if (field === 'animationClip') {
      selectedClipId = target.value || undefined;
      const clip = selectedSet()?.clips[selectedClipId ?? ''];
      draftFrames = clip ? [...clip.frames] : undefined;
      draftFps = clip?.framesPerSecond;
      selectedFrame = 0;
    }
    if (field === 'clipFps') draftFps = Math.max(1, Math.min(240, Math.round(Number(target.value))));
    if (field === 'hitEffectId') {
      draftHitEffectId = target.value || undefined;
    }
    render();
  };

  container.addEventListener('click', clickHandler);
  container.addEventListener('change', changeHandler);
  container.classList.add('is-object-studio-host');
  render();
  void loadObjectStudioCatalog()
    .then((loadedCatalog) => {
      catalog = loadedCatalog;
      const visuals = objectVisuals(catalog);
      const initial = selectedVisual(catalog, selectedObjectId, selectedVisualId) ?? visuals[0];
      if (initial) {
        selectedObjectId = initial.definition.objectId;
        selectedVisualId = initial.frame.visualId;
        selectVisualSet(initial.frame.visualSetId, initial.frame.animationClip);
        draftHitEffectId = initial.definition.resourceNode?.hitEffectId;
      }
      notice = 'Ready';
      render();
    })
    .catch((error: unknown) => { notice = error instanceof Error ? error.message : String(error); render(); });

  return () => {
    stopPlayback();
    container.removeEventListener('click', clickHandler);
    container.removeEventListener('change', changeHandler);
    container.classList.remove('is-object-studio-host');
    container.innerHTML = '';
  };
}
