import type {
  WeaponAttackDirection,
  WeaponAttackTrackDocument,
  WeaponHitboxDocument,
} from '../content/weapons/types';
import { resolveWeaponHitboxPreviewGeometry, WEAPON_HITBOX_PREVIEW_SCALE } from './WeaponHitboxPreview';

export interface WeaponHitboxGuidesOptions {
  readonly hitboxes: Readonly<Record<string, WeaponHitboxDocument>>;
  readonly track?: Pick<WeaponAttackTrackDocument, 'hitboxSpans'>;
  readonly direction: WeaponAttackDirection;
  readonly timelineFrame: number;
  readonly selectedHitboxId?: string;
  readonly presentationOffsetY?: number;
}

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;',
  })[character] ?? character);
}

export function resolvedWeaponHitboxId(
  hitboxes: Readonly<Record<string, WeaponHitboxDocument>>,
  requestedId?: string,
): string | undefined {
  return requestedId && hitboxes[requestedId] ? requestedId : Object.keys(hitboxes)[0];
}

export function renderWeaponHitboxGuides(options: WeaponHitboxGuidesOptions): string {
  const selectedHitboxId = resolvedWeaponHitboxId(options.hitboxes, options.selectedHitboxId);
  const spans = options.track?.hitboxSpans ?? [];
  const presentationOffsetY = (options.presentationOffsetY ?? 0) * WEAPON_HITBOX_PREVIEW_SCALE;
  return Object.entries(options.hitboxes).map(([hitboxId, hitbox], hitboxIndex) => {
    const geometry = resolveWeaponHitboxPreviewGeometry(hitbox, options.direction);
    const active = spans.some((span) => (
      span.hitboxId === hitboxId
      && span.from <= options.timelineFrame
      && options.timelineFrame <= span.through
    ));
    const title = geometry.valid ? hitboxId : `${hitboxId}: ${geometry.invalidReason ?? 'Invalid geometry'}`;
    const classes = `stage-hitbox stage-hitbox--${geometry.shape}${active ? ' is-hot' : ''}${hitboxId === selectedHitboxId ? ' is-selected' : ''}${geometry.valid ? '' : ' is-invalid'}`;
    const selectButton = `<button type="button" class="stage-hitbox-select" style="--hitbox-label-index:${hitboxIndex}" data-select-hitbox="${escapeHtml(hitboxId)}" data-select-weapon-hitbox="${escapeHtml(hitboxId)}" aria-label="Edit ${escapeHtml(hitboxId)}">${escapeHtml(hitboxId)}</button>`;
    if (!geometry.valid) {
      return `<span class="${classes}" data-weapon-hitbox-id="${escapeHtml(hitboxId)}" data-weapon-hitbox-invalid style="transform:translate(-50%,-50%) translate(0,${presentationOffsetY}px)" title="${escapeHtml(title)}">${selectButton}</span>`;
    }
    const width = geometry.width * WEAPON_HITBOX_PREVIEW_SCALE;
    const height = geometry.height * WEAPON_HITBOX_PREVIEW_SCALE;
    const offsetX = geometry.centerX * WEAPON_HITBOX_PREVIEW_SCALE;
    const offsetY = geometry.centerY * WEAPON_HITBOX_PREVIEW_SCALE + presentationOffsetY;
    const style = `width:${width}px;height:${height}px;transform:translate(-50%,-50%) translate(${offsetX}px,${offsetY}px)`;
    const shape = geometry.shape === 'sector'
      ? `<svg class="weapon-hitbox-sector" viewBox="${geometry.sectorViewBox}" aria-hidden="true"><path class="weapon-hitbox-sector-area" fill-rule="evenodd" d="${geometry.sectorAreaPath ?? ''}"></path>${geometry.sectorBoundaryPath ? `<path class="weapon-hitbox-sector-boundary" d="${geometry.sectorBoundaryPath}"></path>` : ''}</svg>`
      : '';
    return `<span class="${classes}" data-weapon-hitbox-id="${escapeHtml(hitboxId)}" style="${style}" title="${escapeHtml(title)}">${shape}${selectButton}</span>`;
  }).join('');
}
