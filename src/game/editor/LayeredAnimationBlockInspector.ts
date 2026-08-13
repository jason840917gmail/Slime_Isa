import {
  normalizeAnimationBlockTransform,
  type AnimationVisualBlockDocument,
} from '../shared/animation';

export interface LayeredAnimationBlockInspectorOptions {
  readonly block: AnimationVisualBlockDocument;
  readonly framesPerSecond: number;
  readonly timelineFrames: number;
}

function transformField(
  label: string,
  field: string,
  value: number,
  unit: string,
  step: string,
  constraints = '',
): string {
  return `<label class="studio-field"><span>${label}<small>${unit}</small></span><input type="number" step="${step}" inputmode="decimal" value="${value}" ${constraints}data-block-transform-field="${field}" /></label>`;
}

/** Domain-neutral selected-block controls shared by layered animation adapters. */
export function renderLayeredAnimationBlockInspector(options: LayeredAnimationBlockInspectorOptions): string {
  const { block, framesPerSecond, timelineFrames } = options;
  const transform = normalizeAnimationBlockTransform(block.transform);
  const hold = block.through - block.from + 1;
  const maxStartSeconds = Math.max(0, timelineFrames - hold) / framesPerSecond;

  return `<div class="layered-block-inspector"><div class="studio-section-heading"><span class="studio-kicker">Selected tile</span><strong>Source frame ${block.sourceFrame}</strong></div><label class="studio-field"><span>Start time<small>frame ${block.from}</small></span><input type="number" min="0" max="${maxStartSeconds}" step="${1 / framesPerSecond}" value="${Number(block.from / framesPerSecond).toFixed(4)}" data-block-timing-field="startSeconds" /></label><div class="layered-block-transform-heading"><span>Tile transform</span><button type="button" class="studio-link-button" data-action="reset-block-transform">reset</button></div><div class="studio-field-grid layered-block-transform-fields">${transformField('Tile offset X', 'offsetX', transform.offset[0], 'source px', '0.25')}${transformField('Tile offset Y', 'offsetY', transform.offset[1], 'source px', '0.25')}${transformField('Tile scale X', 'scaleX', transform.scale[0], 'multiplier', '0.05', 'min="0.05" ')}${transformField('Tile scale Y', 'scaleY', transform.scale[1], 'multiplier', '0.05', 'min="0.05" ')}${transformField('Tile rotation', 'rotationDeg', transform.rotationDeg, 'degrees', '1')}</div><p class="studio-help">These values affect only this tile occurrence. Layer controls above affect every tile in the lane.</p></div>`;
}
