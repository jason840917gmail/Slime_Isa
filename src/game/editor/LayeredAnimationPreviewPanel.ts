export interface LayeredAnimationPreviewPanelOptions {
  readonly kicker: string;
  readonly summaryHtml: string;
  readonly previewZoom: number;
  readonly playing: boolean;
  readonly sceneHtml: string;
  readonly footerHtml: string;
}

/**
 * The single preview frame used by Weapon Studio for weapon-owned and shared animations.
 * Callers provide only scene-specific sprites and labels; dimensions, zoom, playback, and
 * visual framing intentionally stay identical.
 */
export function renderLayeredAnimationPreviewPanel(options: LayeredAnimationPreviewPanelOptions): string {
  const zoomPercent = Math.round(options.previewZoom * 100);
  const playbackLabel = options.playing ? 'Stop preview' : 'Play preview';
  return `<section class="studio-preview-card weapon-preview-card layered-preview-card"><div class="studio-preview-toolbar"><span class="studio-kicker">${options.kicker}</span><span class="studio-muted">${options.summaryHtml}</span><div class="layered-preview-toolbar-actions"><div class="layered-preview-zoom-controls" aria-label="Preview zoom"><button type="button" class="studio-button studio-button--quiet" data-action="preview-zoom-out" aria-label="Zoom preview out" title="Zoom preview out">−</button><span>${zoomPercent}%</span><button type="button" class="studio-button studio-button--quiet" data-action="preview-zoom-in" aria-label="Zoom preview in" title="Zoom preview in">+</button><button type="button" class="studio-link-button" data-action="preview-zoom-reset">RESET</button></div><button type="button" class="studio-button studio-button--quiet" data-action="play-preview" aria-label="${playbackLabel}" aria-pressed="${options.playing}">${options.playing ? '■ STOP' : '▶ PLAY'}</button></div></div><div class="studio-stage weapon-stage layered-preview" style="--preview-zoom:${options.previewZoom}" title="Use the mouse wheel to zoom the preview"><div class="layered-preview-scene">${options.sceneHtml}</div></div><div class="studio-preview-footer">${options.footerHtml}</div></section>`;
}

/** Update playback-only DOM without replacing the workbench on every frame. */
export function updateLayeredAnimationPreviewPlayback(
  container: HTMLElement,
  previewHtml: string,
  playhead: number,
  playheadTimeSeconds?: number,
): void {
  const currentCard = container.querySelector<HTMLElement>('.layered-preview-card');
  if (currentCard) {
    const template = document.createElement('template');
    template.innerHTML = previewHtml.trim();
    const nextCard = template.content.firstElementChild;
    if (nextCard instanceof HTMLElement) {
      const currentScene = currentCard.querySelector<HTMLElement>('.layered-preview-scene');
      const nextScene = nextCard.querySelector<HTMLElement>('.layered-preview-scene');
      if (currentScene && nextScene) currentScene.replaceWith(nextScene);

      const currentSummary = currentCard.querySelector<HTMLElement>('.studio-preview-toolbar > .studio-muted');
      const nextSummary = nextCard.querySelector<HTMLElement>('.studio-preview-toolbar > .studio-muted');
      if (currentSummary && nextSummary) currentSummary.replaceWith(nextSummary);
    }
  }

  const playheadIndicator = container.querySelector<HTMLElement>('.layered-timeline-playhead');
  playheadIndicator?.style.setProperty('--timeline-playhead', String(playhead + 1));

  if (playheadTimeSeconds !== undefined) {
    const workbenchPlayhead = container.querySelector<HTMLElement>('[data-workbench-playhead]')
      ?? container.querySelector<HTMLElement>('.studio-workbench-meta span:nth-child(2) b');
    if (workbenchPlayhead) workbenchPlayhead.textContent = `${playheadTimeSeconds.toFixed(2)}s`;
  }
}

export function syncLayeredAnimationPreviewPlaybackButton(container: HTMLElement, playing: boolean): void {
  const button = container.querySelector<HTMLButtonElement>('[data-action="play-preview"]');
  if (!button) return;
  button.textContent = playing ? '■ STOP' : '▶ PLAY';
  button.setAttribute('aria-label', playing ? 'Stop preview' : 'Play preview');
  button.setAttribute('aria-pressed', String(playing));
}
