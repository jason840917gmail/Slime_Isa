/**
 * Shared world-rendering depth policy.
 *
 * The Y component is always derived from a gameplay ground anchor. Render
 * offsets, animation frame size, and temporary visual elevation intentionally
 * never participate in this key.
 */

export const MAX_SORT_ANCHOR_Y = 65_536;
export const SORT_Y_QUANTA_PER_PIXEL = 16;
export const SORT_QUANTUM_SIZE = 1_024;
export const STABLE_TIE_SLOT_COUNT = 32;
export const MIN_ATTACHMENT_SLOT = -7;
export const MAX_ATTACHMENT_SLOT = 7;
export const DEPTH_BAND_SPACING = 2_000_000_000;

export type WorldDepthBand =
  | 'ground-terrain'
  | 'ground-decals'
  | 'world-entities'
  | 'overhead-artwork'
  | 'reveal-effects'
  | 'screen-ui'
  | 'editor-cursor'
  | 'editor-drag-lift'
  | 'editor-selection-marker'
  | 'editor-template-overlay';

/** Named bases keep gameplay and editor layers numerically disjoint. */
export const DEPTH_BANDS: Readonly<Record<WorldDepthBand, number>> = Object.freeze({
  'ground-terrain': 0,
  'ground-decals': DEPTH_BAND_SPACING,
  'world-entities': DEPTH_BAND_SPACING * 2,
  'overhead-artwork': DEPTH_BAND_SPACING * 3,
  'reveal-effects': DEPTH_BAND_SPACING * 4,
  'screen-ui': DEPTH_BAND_SPACING * 5,
  'editor-cursor': DEPTH_BAND_SPACING * 6,
  'editor-drag-lift': DEPTH_BAND_SPACING * 7,
  'editor-selection-marker': DEPTH_BAND_SPACING * 8,
  'editor-template-overlay': DEPTH_BAND_SPACING * 9,
});

export type DepthMode = 'world-sorted' | 'explicit';

export interface WorldDepthOptions {
  readonly band?: WorldDepthBand;
  readonly stableId?: string;
  readonly attachmentSlot?: number;
}

export interface ResolvedWorldDepth {
  readonly band: WorldDepthBand;
  readonly groundAnchorY: number;
  readonly stableId: string;
  readonly stableTieSlot: number;
  readonly attachmentSlot: number;
  readonly depth: number;
}

export function clampSortAnchorY(anchorY: number): number {
  return Math.max(0, Math.min(MAX_SORT_ANCHOR_Y, Number.isFinite(anchorY) ? anchorY : 0));
}

export function clampAttachmentSlot(slot: number): number {
  return Math.max(
    MIN_ATTACHMENT_SLOT,
    Math.min(MAX_ATTACHMENT_SLOT, Number.isFinite(slot) ? Math.round(slot) : 0),
  );
}

/** Small deterministic hash; stable IDs are never generated from display-list order. */
export function stableTieSlot(stableId: string): number {
  let hash = 2_166_136_261;
  for (let index = 0; index < stableId.length; index += 1) {
    hash ^= stableId.charCodeAt(index);
    hash = Math.imul(hash, 16_777_619);
  }
  return (hash >>> 0) % STABLE_TIE_SLOT_COUNT;
}

export function resolveWorldDepth(
  groundAnchorY: number,
  options: WorldDepthOptions = {},
): ResolvedWorldDepth {
  const band = options.band ?? 'world-entities';
  const stableId = options.stableId ?? 'anonymous';
  const clampedY = clampSortAnchorY(groundAnchorY);
  const attachment = clampAttachmentSlot(options.attachmentSlot ?? 0);
  const tie = stableTieSlot(stableId);
  const yQuantum = Math.round(clampedY * SORT_Y_QUANTA_PER_PIXEL);

  return {
    band,
    groundAnchorY: clampedY,
    stableId,
    stableTieSlot: tie,
    attachmentSlot: attachment,
    depth: DEPTH_BANDS[band] + yQuantum * SORT_QUANTUM_SIZE + tie * 16 + attachment,
  };
}

export function resolveExplicitDepth(
  band: Exclude<WorldDepthBand, 'world-entities' | 'ground-terrain' | 'ground-decals'>,
  slot = 0,
): number {
  const explicitSlot = Number.isFinite(slot) ? Math.round(slot) : 0;
  return DEPTH_BANDS[band] + explicitSlot;
}

export function resolveScreenUiDepth(slot = 0): number {
  return resolveExplicitDepth('screen-ui', slot);
}

export interface BodyGeometry {
  readonly y: number;
  readonly height: number;
}

export interface ObjectDepthBounds {
  readonly height: number;
  readonly offsetY: number;
}

export interface ObjectDepthGeometry {
  readonly sourceFrameHeight: number;
  readonly originY: number;
  readonly bounds?: ObjectDepthBounds;
  readonly scaleY?: number;
}

export function resolveBodyBottom(body: BodyGeometry): number {
  return body.y + body.height;
}

export function resolveBodyCenterY(body: BodyGeometry): number {
  return body.y + body.height / 2;
}

export function resolveObjectGroundAnchorY(objectAnchorY: number): number {
  return objectAnchorY;
}

/**
 * Resolves an authored source-frame depth rectangle to a world-space sort Y.
 * The rectangle's lower edge is the only part that affects front/behind order.
 */
export function resolveObjectDepthAnchorY(
  objectAnchorY: number,
  geometry: ObjectDepthGeometry,
): number {
  if (!geometry.bounds) return objectAnchorY;
  const scaleY = Math.abs(geometry.scaleY ?? 1);
  return objectAnchorY
    + (geometry.bounds.offsetY + geometry.bounds.height
      - geometry.sourceFrameHeight * geometry.originY) * scaleY;
}
