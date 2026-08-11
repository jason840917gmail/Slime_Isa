import type { AnimationTimelineKeyframeView, AnimationTimelineViewModel } from './AnimationTimelineView';

export interface AnimationTimelinePanelOptions {
  readonly panelClassName?: string;
  readonly kicker?: string;
  readonly titleHtml: string;
  readonly hint: string;
  readonly addTilesAction: string;
  readonly addTilesDisabled?: boolean;
  readonly addTilesLabel?: string;
  readonly headerActionsHtml?: string;
  readonly clipTabsHtml: string;
  readonly contextControlsHtml?: string;
  readonly timelineView: AnimationTimelineViewModel;
  readonly renderKeyframe: (keyframe: AnimationTimelineKeyframeView) => string;
  readonly timelineRowsHtml?: string;
  readonly timelineLocked?: boolean;
  readonly selectionHtml?: string;
  readonly toolbarHtml?: string;
  readonly helpHtml?: string;
  readonly playbackHtml?: string;
}

export function renderAnimationTimelineRuler(timelineView: AnimationTimelineViewModel): string {
  const ruler = timelineView.rulerTicks.map((tick) => `<span class="timeline-ruler-tick${tick.timeLabel ? ' is-labelled' : ''}" style="grid-column:${tick.gridColumn}" data-timeline-frame="${tick.frame}" aria-label="Timeline frame ${tick.frame}${tick.timeLabel ? ` at ${tick.timeLabel}` : ''}">${tick.timeLabel ? `<b>${tick.timeLabel}</b>` : ''}</span>`).join('');
  return `<div class="timeline-ruler-row"><span class="timeline-lane-label">TIME</span><div class="timeline-ruler">${ruler}</div></div>`;
}

/**
 * Shared animation editor shell used by character, enemy, and weapon adapters.
 * Adapters supply domain-specific tabs, thumbnails, tracks, and field bindings.
 */
export function renderAnimationTimelinePanel(options: AnimationTimelinePanelOptions): string {
  const panelClassName = options.panelClassName ? ` ${options.panelClassName}` : '';
  const addTilesLabel = options.addTilesLabel ?? '+ ADD TILES';
  const addTilesDisabled = options.addTilesDisabled ? 'disabled' : '';
  const timelineLocked = options.timelineLocked ? ' is-locked' : '';
  const keyframes = options.timelineView.keyframes.map(options.renderKeyframe).join('');

  return `<section class="studio-timeline-panel${panelClassName}">
    <div class="studio-section-bar"><div><span class="studio-kicker">${options.kicker ?? 'Animation timeline'}</span><strong>${options.titleHtml}</strong></div><span class="studio-muted">${options.hint}</span><div class="studio-clip-actions"><button type="button" class="studio-button studio-button--save studio-timeline-add-tiles" data-action="${options.addTilesAction}" ${addTilesDisabled}>${addTilesLabel}</button>${options.headerActionsHtml ?? ''}</div></div>
    <div class="studio-clip-tabs">${options.clipTabsHtml}</div>
    ${options.contextControlsHtml ?? ''}
    <div class="studio-timeline${timelineLocked}" tabindex="-1" style="--timeline-frame-count:${Math.max(1, options.timelineView.timelineFrames)}">${renderAnimationTimelineRuler(options.timelineView)}<div class="timeline-frame-row"><span class="timeline-lane-label">KEYS</span><div class="timeline-frames">${keyframes}</div></div>${options.timelineRowsHtml ?? ''}</div>
    ${options.selectionHtml ?? ''}
    ${options.toolbarHtml ?? ''}
    ${options.helpHtml ?? ''}
    ${options.playbackHtml ?? ''}
  </section>`;
}
