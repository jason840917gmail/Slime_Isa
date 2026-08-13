import type { LayeredAnimationTimelineViewModel } from './LayeredAnimationTimelineView';

export interface LayeredAnimationTimelinePanelOptions {
  readonly titleHtml: string;
  readonly hint: string;
  readonly timeline: LayeredAnimationTimelineViewModel;
  readonly selectedLayerId?: string;
  readonly selectedBlockIndex?: number;
  readonly playhead: number;
  readonly hostRowsHtml?: string;
  readonly renderBlock: (layerId: string, blockIndex: number) => string;
}

export function renderLayeredAnimationTimelinePanel(options: LayeredAnimationTimelinePanelOptions): string {
  const ruler = options.timeline.rulerTicks.map((tick) => `<span class="timeline-ruler-tick${tick.timeLabel ? ' is-labelled' : ''}" style="grid-column:${tick.gridColumn}" data-layered-playhead-frame="${tick.frame}">${tick.timeLabel ? `<b>${tick.timeLabel}</b>` : ''}</span>`).join('');
  const lanes = options.timeline.lanes.map((lane) => `<div class="layered-timeline-lane${lane.layerId === options.selectedLayerId ? ' is-selected' : ''}" data-layer-id="${lane.layerId}"><button type="button" class="timeline-lane-label layered-timeline-lane-label" data-select-layer="${lane.layerId}"><strong>${lane.displayName}</strong><small>${lane.assetId}</small></button><div class="timeline-frames layered-timeline-blocks" title="Click empty time to place the playhead">${lane.blocks.map((block) => options.renderBlock(lane.layerId, block.blockIndex)).join('')}</div></div>`).join('');
  return `<section class="studio-timeline-panel layered-timeline-panel"><div class="studio-section-bar"><div><span class="studio-kicker">Animation timeline</span><strong>${options.titleHtml}</strong></div><span class="studio-muted">${options.hint}</span><div class="studio-clip-actions"><button type="button" class="studio-button" data-action="add-layer">+ ADD LAYER</button><button type="button" class="studio-button studio-button--save" data-action="add-layer-tiles" title="Add selected source tiles at the playhead" ${options.selectedLayerId ? '' : 'disabled'}>+ ADD TILES</button></div></div><div class="studio-timeline" style="--timeline-frame-count:${options.timeline.timelineFrames}"><div class="timeline-ruler-row"><span class="timeline-lane-label">TIME</span><div class="timeline-ruler">${ruler}</div></div><span class="layered-timeline-playhead" style="--timeline-playhead:${options.playhead + 1}" aria-hidden="true"></span>${lanes}${options.hostRowsHtml ?? ''}</div></section>`;
}
