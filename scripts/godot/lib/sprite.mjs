/**
 * Sprite2D geometry and draw order.
 *
 * - `centered = false`, `offset = visualOffset − origin·frameSize` with the
 *   frame size from assets.json (Phaser never uses the resource's frameWidth).
 * - `tint`/`alpha` → `self_modulate` (keeps `modulate` free for gameplay).
 * - Bands → z_index: ground-decals −1, world-entities 0, overhead-artwork 1,
 *   reveal-effects 2; an explicit depth in band b → Z(b) − 1 (the water-life
 *   fish sit below every world-sorted decal at −2).
 * - `depthBounds` sorts a world-sorted sprite on a line Δ = k·scaleY below its
 *   origin (k = offsetY + height − frameH·originY): the node moves down by Δ
 *   and the offset up by k, so the image stays put while Godot's y-sort uses
 *   the line.
 */
import { gd } from './tscn.mjs';

const BAND_Z = { 'ground-terrain': -2, 'ground-decals': -1, 'world-entities': 0, 'overhead-artwork': 1, 'reveal-effects': 2 };
const BAND_SPACING = 2_000_000_000;
const BAND_ORDER = ['ground-terrain', 'ground-decals', 'world-entities', 'overhead-artwork', 'reveal-effects'];

const vec = (value, fallback) => (Array.isArray(value) && value.length === 2 ? value : fallback);

/**
 * Texture, frame grid and geometry for a sprite with properties `p`:
 * { texture, grid, offsetBase: [x, y] (added to visualOffset), sortShiftY }.
 */
export function spriteGeometry(ctx, node, p) {
  const resource = p.texture?.resourceId ? ctx.resource(p.texture.resourceId) : null;
  const assets = ctx.project.assets;
  let grid = { frameW: 0, frameH: 0, cols: 1, rows: 1, count: 1 };
  let texture = null;
  if (resource && (resource.kind === 'sprite-sheet' || resource.kind === 'texture') && assets.has(resource.assetId)) {
    grid = assets.grid(resource.assetId);
    texture = assets.texture(resource.assetId);
    if (resource.kind === 'texture' && resource.frame !== undefined) {
      ctx.warn('sprite-texture-frame', `${ctx.label}: texture resource frame on a Sprite2D is not converted`);
    }
  } else if (resource) {
    ctx.warn('sprite-texture-missing', `${ctx.label}: texture '${resource.resourceId}' (${resource.kind}) has no known asset`);
  }
  const [originX, originY] = vec(p.origin, [0.5, 0.5]);
  let sortShiftY = 0;
  let offsetShiftY = 0;
  const bounds = p.depthBounds;
  if (bounds && (p.depthMode ?? 'world-sorted') === 'world-sorted') {
    const k = bounds.offsetY + bounds.height - grid.frameH * originY;
    const scaleY = Math.abs(vec(p.scale, [1, 1])[1]);
    sortShiftY = k * scaleY;
    offsetShiftY = -k;
  }
  return {
    texture,
    grid,
    offsetBase: [-originX * grid.frameW, -originY * grid.frameH + offsetShiftY],
    sortShiftY,
  };
}

function zIndexOf(p) {
  if (p.depthMode === 'explicit') {
    const band = Math.floor((p.depth ?? 0) / BAND_SPACING);
    return BAND_Z[BAND_ORDER[band]] - 1;
  }
  return BAND_Z[p.depthBand ?? 'world-entities'];
}

function selfModulate(p) {
  const alpha = p.alpha ?? 1;
  const tint = typeof p.tint === 'string' ? p.tint : '#ffffff';
  const match = /^#?([0-9a-f]{6})$/i.exec(tint);
  const rgb = match ? [0, 2, 4].map((i) => parseInt(match[1].slice(i, i + 2), 16) / 255) : [1, 1, 1];
  if (alpha === 1 && rgb.every((c) => c === 1)) return null;
  const round = (value) => Math.round(value * 1e6) / 1e6;
  return gd.color(round(rgb[0]), round(rgb[1]), round(rgb[2]), alpha);
}

/** Sprite2D properties (CanvasItem, Node2D and Sprite2D groups, in Godot's order). */
export function convertSpriteProps(ctx) {
  const p = ctx.props;
  const geometry = spriteGeometry(ctx, ctx.node, p);
  const props = [];
  if (p.visible === false) props.push(['visible', false]);
  const modulate = selfModulate(p);
  if (modulate) props.push(['self_modulate', modulate]);
  const z = zIndexOf(p);
  if (z === undefined) ctx.warn('unknown-depth-band', `${ctx.label}: depth band '${p.depthBand}' is unknown`);
  else if (z !== 0) props.push(['z_index', z]);
  const shift = ctx.scene.childShift(ctx.node);
  const [x, y] = vec(p.position, [0, 0]);
  const position = [x + shift[0], y + shift[1] + geometry.sortShiftY];
  ctx.node2d(props, { position });
  if (geometry.texture) props.push(['texture', geometry.texture]);
  props.push(['centered', false]);
  const [vx, vy] = vec(p.visualOffset, [0, 0]);
  const offset = [vx + geometry.offsetBase[0], vy + geometry.offsetBase[1]];
  if (offset[0] !== 0 || offset[1] !== 0) props.push(['offset', gd.vec2(offset[0], offset[1])]);
  if (p.flipX) props.push(['flip_h', true]);
  if (p.flipY) props.push(['flip_v', true]);
  if (geometry.grid.cols > 1) props.push(['hframes', geometry.grid.cols]);
  if (geometry.grid.rows > 1) props.push(['vframes', geometry.grid.rows]);
  const frame = p.frame ?? 0;
  if (frame >= geometry.grid.cols * geometry.grid.rows) {
    ctx.warn('sprite-frame-out-of-range', `${ctx.label}: frame ${frame} is outside the ${geometry.grid.cols}×${geometry.grid.rows} sheet`);
  } else if (frame > 0) props.push(['frame', frame]);
  if (p.occlusionBounds) ctx.report.dropped('Sprite2D', 'occlusionBounds');
  if (p.depthOffset !== undefined) ctx.report.dropped('Sprite2D', 'depthOffset');
  return props;
}
